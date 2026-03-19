/**
 * Shared service for processing completed IBM Quantum jobs.
 * Centralizes sampler and estimator completion logic that was previously
 * duplicated across QRNGJobPoller, QRNGJobSweeper, and QRNGSetupController.
 *
 * Responsibilities:
 *   - Parse IBM results (sampler or estimator)
 *   - Run validation gates (frequency, runs, CHSH)
 *   - Update Quantum_Job__c with results
 *   - Create Fairness_Certificate__c (sampler only)
 *   - Update QRNG_Backend__c verification (estimator only)
 *   - Enqueue extended validation (sampler only)
 *   - Publish Platform Events
 *
 * Governor limits per call: 1 callout (getJobResults), ~3 SOQL, 2-3 DML
 */
public with sharing class QRNGJobProcessor {
    /**
     * Result DTO returned after processing a completed job.
     */
    public class ProcessingResult {
        public String status;
        public Id certificateId;
        public Double chshSValue;
        public Boolean bellTestPassed;
        public Integer rawBitsLength;
        public Integer debiasedBitsLength;
    }

    /**
     * Process a completed sampler job: parse results, validate, certify, publish.
     * @param job The Quantum_Job__c record (must have Id, Num_Qubits__c, Use_Bell_Test__c, Submitted_At__c)
     * @param resultsJson Raw JSON from IBMQuantumService.getJobResults()
     * @param statusResponse The IBM status response (for queue time extraction); may be null
     * @return ProcessingResult with certificate ID and bit lengths
     */
    public static ProcessingResult processSamplerCompletion(
        Quantum_Job__c job,
        String resultsJson,
        Map<String, Object> statusResponse
    ) {
        Integer numQubits = job.Num_Qubits__c != null
            ? (Integer) job.Num_Qubits__c
            : 8;
        List<String> bitstrings = QRNGResultParser.parseSamplerResults(
            resultsJson,
            numQubits
        );
        String rawBits = QRNGResultParser.concatenateBitstrings(bitstrings);
        String debiasedBits = QRNGResultParser.vonNeumannDebias(rawBits);

        // Critical realtime gate: frequency test (blocks certification)
        Map<String, Object> validationResults = QRNGValidator.validate(
            debiasedBits
        );
        Boolean isValid = (Boolean) validationResults.get('passed');

        // For Bell test jobs, compute CHSH S-value (also blocks certification)
        Boolean isBellTest = job.Use_Bell_Test__c == true;
        if (isBellTest) {
            Integer numPairs = numQubits / 2;
            // Re-split raw bits into per-shot bitstrings for CHSH calculation
            List<String> shots = new List<String>();
            for (
                Integer i = 0; i + numQubits <= rawBits.length(); i += numQubits
            ) {
                shots.add(rawBits.substring(i, i + numQubits));
            }
            Double sValue = QRNGValidator.calculateCHSH(shots, numPairs);
            validationResults.put('chshSValue', sValue);
            validationResults.put('bellTestPassed', sValue > 2.0);

            if (sValue <= 2.0) {
                isValid = false;
                validationResults.put('passed', false);
            }
        }

        // Update job record
        String validationJson = JSON.serialize(validationResults);
        String encodedRaw = QRNGResultParser.encodeForStorage(rawBits);
        job.Status__c = 'Completed';
        job.Raw_Results__c = encodedRaw.left(131072);
        job.Result_Fingerprint__c = QRNGResultParser.generateFingerprint(
            rawBits
        );
        String encodedDebiased = QRNGResultParser.encodeForStorage(
            debiasedBits
        );
        job.Debiased_Results__c = encodedDebiased.left(131072);
        job.Completed_At__c = DateTime.now();
        stampExecutionTime(job);
        if (statusResponse != null) {
            job.Queue_Time_ms__c = IBMResponseParser.extractQueueTimeMs(
                statusResponse
            );
            stampQpuTime(job, statusResponse);
        }
        job.Validation_Results__c = validationJson;
        update job;

        // Create certificate
        String certStatus = isValid ? 'Certified' : 'Failed';
        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            validationJson,
            certStatus
        );

        // Enqueue async extended validation tests (non-blocking)
        if (!Test.isRunningTest()) {
            System.enqueueJob(new QRNGValidationRunner(job.Id));
        }

        // Publish completion event
        QRNG_Complete__e completeEvent = new QRNG_Complete__e(
            Job_Id__c = job.Id,
            Certificate_Id__c = certId,
            Num_Random_Bits__c = debiasedBits.length(),
            Status__c = certStatus
        );
        EventBus.publish(completeEvent);

        ProcessingResult result = new ProcessingResult();
        result.status = 'Completed';
        result.certificateId = certId;
        result.chshSValue = isBellTest
            ? (Double) validationResults.get('chshSValue')
            : null;
        result.bellTestPassed = isBellTest
            ? (Boolean) validationResults.get('bellTestPassed')
            : null;
        result.rawBitsLength = rawBits.length();
        result.debiasedBitsLength = debiasedBits.length();
        return result;
    }

    /**
     * Process a completed estimator job (CHSH verification).
     * Supports both legacy single-PUB and multi-PUB with observable metadata.
     * @param job The Quantum_Job__c record (must have Id, Backend__c, Validation_Results__c, Submitted_At__c)
     * @param resultsJson Raw JSON from IBMQuantumService.getJobResults()
     * @param statusResponse The IBM status response (for queue time extraction); may be null
     * @return ProcessingResult with CHSH S-value
     */
    public static ProcessingResult processEstimatorCompletion(
        Quantum_Job__c job,
        String resultsJson,
        Map<String, Object> statusResponse
    ) {
        // Parse individual expectation values (one per PUB/observable)
        List<Double> evs = QRNGResultParser.parseAllEstimatorResults(
            resultsJson
        );
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(resultsJson);

        // Retrieve observable labels stored at submission time
        List<String> labels = new List<String>();
        Map<String, Double> coeffs = new Map<String, Double>();
        if (String.isNotBlank(job.Validation_Results__c)) {
            Map<String, Object> meta = (Map<String, Object>) JSON.deserializeUntyped(
                job.Validation_Results__c
            );
            if (meta.containsKey('observableLabels')) {
                for (Object lbl : (List<Object>) meta.get('observableLabels')) {
                    labels.add((String) lbl);
                }
            }
            if (meta.containsKey('observableCoeffs')) {
                Map<String, Object> rawCoeffs = (Map<String, Object>) meta.get(
                    'observableCoeffs'
                );
                for (String k : rawCoeffs.keySet()) {
                    coeffs.put(
                        k,
                        Double.valueOf(String.valueOf(rawCoeffs.get(k)))
                    );
                }
            }
        }

        // Fallback for old jobs without observable metadata:
        // treat the single result as the composite S-value
        if (labels.isEmpty() && !evs.isEmpty()) {
            return processLegacyEstimator(job, evs[0], statusResponse);
        }

        // Compute S = Σ(coefficient × expectation value) per term
        Double sValue = 0;
        Map<String, Object> termBreakdown = new Map<String, Object>();
        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String label = labels[i];
            Double ev = evs[i];
            Double coeff = coeffs.containsKey(label) ? coeffs.get(label) : 1.0;
            sValue += coeff * ev;

            String shortLabel = label.replaceAll('I', '');
            Map<String, Object> term = new Map<String, Object>();
            term.put('expectationValue', ev);
            term.put('coefficient', coeff);
            term.put('contribution', coeff * ev);
            if (i < stds.size() && stds[i] != null) {
                term.put('std', stds[i]);
            }
            termBreakdown.put(shortLabel, term);
        }
        Double sValueAbs = Math.abs(sValue);

        // Build validation results with full breakdown
        Map<String, Object> validationResults = new Map<String, Object>();
        validationResults.put('chshSValue', sValueAbs);
        validationResults.put('bellTestPassed', sValueAbs > 2.0);
        validationResults.put('passed', sValueAbs > 2.0);
        validationResults.put('programId', 'estimator');
        validationResults.put('termBreakdown', termBreakdown);

        // Build human-readable summary
        job.Raw_Results__c = buildEstimatorSummary(
            sValueAbs,
            evs,
            stds,
            labels,
            coeffs
        );

        String validationJson = JSON.serialize(validationResults);

        // Update job record
        job.Status__c = 'Completed';
        job.Completed_At__c = DateTime.now();
        stampExecutionTime(job);
        if (statusResponse != null) {
            job.Queue_Time_ms__c = IBMResponseParser.extractQueueTimeMs(
                statusResponse
            );
            stampQpuTime(job, statusResponse);
        }
        job.Validation_Results__c = validationJson;
        update job;

        // Update QRNG_Backend__c with verification result
        updateBackendVerification(job.Backend__c, sValueAbs, job.Id);

        // Publish completion event (no certificate for verification jobs)
        String certStatus = sValueAbs > 2.0 ? 'Certified' : 'Failed';
        EventBus.publish(
            new QRNG_Complete__e(Job_Id__c = job.Id, Status__c = certStatus)
        );

        ProcessingResult result = new ProcessingResult();
        result.status = 'Completed';
        result.chshSValue = sValueAbs;
        result.bellTestPassed = sValueAbs > 2.0;
        return result;
    }

    /**
     * Process a legacy single-PUB estimator result (no observable metadata).
     */
    @TestVisible
    private static ProcessingResult processLegacyEstimator(
        Quantum_Job__c job,
        Double rawValue,
        Map<String, Object> statusResponse
    ) {
        Double sValue = Math.abs(rawValue);

        Map<String, Object> vr = new Map<String, Object>();
        vr.put('chshSValue', sValue);
        vr.put('bellTestPassed', sValue > 2.0);
        vr.put('passed', sValue > 2.0);
        vr.put('programId', 'estimator');

        job.Raw_Results__c = 'S-Value (legacy single-PUB): ' + sValue;
        job.Validation_Results__c = JSON.serialize(vr);
        job.Status__c = 'Completed';
        job.Completed_At__c = DateTime.now();
        stampExecutionTime(job);
        if (statusResponse != null) {
            job.Queue_Time_ms__c = IBMResponseParser.extractQueueTimeMs(
                statusResponse
            );
            stampQpuTime(job, statusResponse);
        }
        update job;

        updateBackendVerification(job.Backend__c, sValue, job.Id);

        String certStatus = sValue > 2.0 ? 'Certified' : 'Failed';
        EventBus.publish(
            new QRNG_Complete__e(Job_Id__c = job.Id, Status__c = certStatus)
        );

        ProcessingResult result = new ProcessingResult();
        result.status = 'Completed';
        result.chshSValue = sValue;
        result.bellTestPassed = sValue > 2.0;
        return result;
    }

    /**
     * Update QRNG_Backend__c with CHSH verification results.
     */
    @TestVisible
    private static void updateBackendVerification(
        String backendName,
        Double sValue,
        Id jobId
    ) {
        List<QRNG_Backend__c> backends = [
            SELECT Id
            FROM QRNG_Backend__c
            WHERE Name = :backendName
            LIMIT 1
        ];
        if (!backends.isEmpty()) {
            backends[0].CHSH_S_Value__c = sValue;
            backends[0].CHSH_Verified_At__c = DateTime.now();
            backends[0].CHSH_Job_Id__c = jobId;
            update backends;
        }
    }

    /**
     * Set Execution_Time_ms__c based on Submitted_At__c.
     */
    private static void stampExecutionTime(Quantum_Job__c job) {
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c =
                DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
    }

    /**
     * Extract and stamp QPU time from IBM status response.
     */
    private static void stampQpuTime(
        Quantum_Job__c job,
        Map<String, Object> statusResponse
    ) {
        Decimal qpuSeconds = IBMResponseParser.extractQpuTimeSeconds(
            statusResponse
        );
        if (qpuSeconds != null) {
            job.QPU_Time_seconds__c = qpuSeconds;
        }
    }

    /**
     * Build a human-readable CHSH estimator summary string.
     */
    @TestVisible
    private static String buildEstimatorSummary(
        Double sValueAbs,
        List<Double> evs,
        List<Double> stds,
        List<String> labels,
        Map<String, Double> coeffs
    ) {
        String summary = '=== CHSH Bell Test Results ===\n\n';
        summary += 'S-Value:           ' + sValueAbs + '\n';
        summary += 'Classical Bound:   2.0\n';
        summary += 'Quantum Maximum:   2.828 (2\u221A2)\n';
        summary +=
            'Result:            ' +
            (sValueAbs > 2.0
                ? 'PASS - Quantum behavior confirmed'
                : 'FAIL - Below classical bound') +
            '\n';

        summary += '\n=== Per-Observable Breakdown ===\n';
        summary += 'S = ';
        List<String> formulaParts = new List<String>();
        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String shortLabel = labels[i].replaceAll('I', '');
            Double coeff = coeffs.containsKey(labels[i])
                ? coeffs.get(labels[i])
                : 1.0;
            String sign = coeff >= 0 ? '+' : '-';
            if (i == 0 && coeff >= 0) {
                sign = '';
            }
            formulaParts.add(sign + '<' + shortLabel + '>');
        }
        summary += String.join(formulaParts, ' ') + '\n\n';

        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String shortLabel = labels[i].replaceAll('I', '');
            Double coeff = coeffs.containsKey(labels[i])
                ? coeffs.get(labels[i])
                : 1.0;
            String coeffStr = coeff == 1.0
                ? '+1'
                : (coeff == -1.0 ? '-1' : String.valueOf(coeff));
            summary += '<' + shortLabel + '> = ' + evs[i];
            if (i < stds.size() && stds[i] != null) {
                summary += '  (std: ' + stds[i] + ')';
            }
            summary +=
                '  [coeff: ' +
                coeffStr +
                ', contribution: ' +
                (coeff * evs[i]) +
                ']\n';
        }
        summary += '\nS = ' + sValueAbs + '\n';
        return summary;
    }
}
