/**
 * Shared service for processing completed IBM Quantum jobs.
 * Centralizes sampler and estimator completion logic that was previously
 * duplicated across JobPoller, JobSweeper, and SetupController.
 *
 * Responsibilities:
 *   - Parse IBM results (sampler or estimator)
 *   - Run validation gates (frequency, runs, CHSH)
 *   - Update Quantum_Job__c with results
 *   - Create Fairness_Certificate__c (sampler only)
 *   - Update Quantum_Backend__c verification (estimator only)
 *   - Enqueue extended validation (sampler only)
 *   - Publish Platform Events
 *
 * Governor limits per call: 1 callout (getJobResults), ~6 SOQL, 3-4 DML
 */
public with sharing class JobProcessor {
    /**
     * Maximum length of the LongTextArea fields that store encoded results.
     * Results exceeding this are FAILED, never truncated — a truncated
     * bitstring would be hashed into the certificate and silently break
     * third-party audit replay (H-R3).
     */
    @TestVisible
    private static Integer maxStoredResultChars = 131072;

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
        // Idempotency guard: lock the job row so concurrent completion
        // signals (poller + sweeper + manual retrieve) serialize; if the
        // job is already terminal and certified, this is a duplicate —
        // return the existing outcome without re-processing or
        // re-publishing events.
        Quantum_Job__c lockedJob = [
            SELECT Id, Status__c, Assignment_Request__c, Assignment_Type__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
            FOR UPDATE
        ];
        ProcessingResult duplicate = checkAlreadyProcessed(lockedJob);
        if (duplicate != null) {
            return duplicate;
        }

        Integer numQubits = job.Num_Qubits__c != null
            ? (Integer) job.Num_Qubits__c
            : 8;
        List<String> bitstrings = ResultParser.parseSamplerResults(
            resultsJson,
            numQubits
        );
        String rawBits = ResultParser.concatenateBitstrings(bitstrings);
        // Per-qubit debiasing (H-M1); Bell jobs exclude correlated pair bits
        String debiasedBits = job.Use_Bell_Test__c == true
            ? ResultParser.vonNeumannDebiasBellPairs(rawBits, numQubits)
            : ResultParser.vonNeumannDebias(rawBits, numQubits);

        // Critical realtime gate: frequency test (blocks certification)
        Map<String, Object> validationResults = RandomnessValidator.validate(
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
            Map<String, Object> chshStats = RandomnessValidator.calculateCHSHWithStats(
                shots,
                numPairs
            );
            validationResults.putAll(chshStats);

            if ((Boolean) chshStats.get('bellTestPassed') != true) {
                isValid = false;
                validationResults.put('passed', false);
            }
        }

        // Defensive truncation guard (H-R3): results that cannot be stored
        // in full are FAILED, never truncated-and-hashed. The primary guard
        // rejects oversized configs at submission time.
        String encodedRaw = ResultParser.encodeForStorage(rawBits);
        String encodedDebiased = ResultParser.encodeForStorage(debiasedBits);
        if (
            encodedRaw.length() > maxStoredResultChars ||
            encodedDebiased.length() > maxStoredResultChars
        ) {
            return failJob(
                job,
                'Result too large to store without truncation (' +
                    encodedRaw.length() +
                    ' encoded chars, maximum ' +
                    maxStoredResultChars +
                    '). Truncating would break the audit chain. Lower ' +
                    'qubits x shots so that ceil(qubits*shots/4) + 2 <= ' +
                    maxStoredResultChars +
                    ' and resubmit.'
            );
        }

        // Update job record
        String validationJson = JSON.serialize(validationResults);
        job.Status__c = 'Completed';
        job.Raw_Results__c = encodedRaw;
        job.Result_Fingerprint__c = ResultParser.generateFingerprint(rawBits);
        job.Debiased_Results__c = encodedDebiased;
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

        // Wire the assignment engine (B1): after certification, replay the
        // persisted assignment request against the certified debiased pool.
        // Assignment failure must never lose the certificate: errors are
        // logged on the job and no partial assignments are kept.
        if (
            isValid &&
            String.isNotBlank(lockedJob.Assignment_Request__c) &&
            String.isNotBlank(lockedJob.Assignment_Type__c)
        ) {
            try {
                createAssignments(
                    job.Id,
                    certId,
                    lockedJob.Assignment_Type__c,
                    lockedJob.Assignment_Request__c,
                    debiasedBits
                );
            } catch (Exception e) {
                appendJobError(
                    job.Id,
                    ('Assignment failed: ' + e.getMessage()).left(4000)
                );
            }
        }

        // Enqueue async extended validation tests (non-blocking)
        if (!Test.isRunningTest()) {
            System.enqueueJob(new ValidationRunner(job.Id));
        }

        // Publish completion event
        Quantum_Job_Complete__e completeEvent = new Quantum_Job_Complete__e(
            Job_Id__c = job.Id,
            Certificate_Id__c = certId,
            Num_Random_Bits__c = debiasedBits.length(),
            Status__c = certStatus
        );
        publishSafely(completeEvent, job.Id);

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
        // Idempotency guard (see processSamplerCompletion)
        Quantum_Job__c lockedJob = [
            SELECT Id, Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
            FOR UPDATE
        ];
        ProcessingResult duplicate = checkAlreadyProcessed(lockedJob);
        if (duplicate != null) {
            return duplicate;
        }

        // Parse individual expectation values (one per PUB/observable)
        List<Double> evs = ResultParser.parseAllEstimatorResults(resultsJson);
        List<Double> stds = ResultParser.parseAllEstimatorStds(resultsJson);

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

        // Update Quantum_Backend__c with verification result
        updateBackendVerification(job.Backend__c, sValueAbs, job.Id);

        // Publish completion event (no certificate for verification jobs)
        String certStatus = sValueAbs > 2.0 ? 'Certified' : 'Failed';
        publishSafely(
            new Quantum_Job_Complete__e(
                Job_Id__c = job.Id,
                Status__c = certStatus
            ),
            job.Id
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
        publishSafely(
            new Quantum_Job_Complete__e(
                Job_Id__c = job.Id,
                Status__c = certStatus
            ),
            job.Id
        );

        ProcessingResult result = new ProcessingResult();
        result.status = 'Completed';
        result.chshSValue = sValue;
        result.bellTestPassed = sValue > 2.0;
        return result;
    }

    /**
     * Update Quantum_Backend__c with CHSH verification results.
     */
    @TestVisible
    private static void updateBackendVerification(
        String backendName,
        Double sValue,
        Id jobId
    ) {
        List<Quantum_Backend__c> backends = [
            SELECT Id
            FROM Quantum_Backend__c
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

    /**
     * Idempotency check: returns the prior outcome when the (locked) job is
     * already terminal AND a certificate exists for it; null otherwise.
     */
    private static ProcessingResult checkAlreadyProcessed(
        Quantum_Job__c lockedJob
    ) {
        if (
            lockedJob.Status__c != 'Completed' &&
            lockedJob.Status__c != 'Failed'
        ) {
            return null;
        }
        List<Fairness_Certificate__c> existingCerts = [
            SELECT Id
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :lockedJob.Id
            LIMIT 1
        ];
        if (existingCerts.isEmpty()) {
            return null;
        }
        ProcessingResult result = new ProcessingResult();
        result.status = lockedJob.Status__c;
        result.certificateId = existingCerts[0].Id;
        return result;
    }

    /**
     * Fail a job without creating a certificate (e.g. oversized results).
     */
    private static ProcessingResult failJob(
        Quantum_Job__c job,
        String errorMessage
    ) {
        job.Status__c = 'Failed';
        job.Error_Message__c = errorMessage.left(32768);
        job.Completed_At__c = DateTime.now();
        update job;

        publishSafely(
            new Quantum_Job_Failed__e(
                Job_Id__c = job.Id,
                Error_Message__c = errorMessage.left(255)
            ),
            job.Id
        );

        ProcessingResult result = new ProcessingResult();
        result.status = 'Failed';
        return result;
    }

    /**
     * Deserialize the persisted assignment request, dispatch to the
     * assignment engine by type, insert the assignments (all-or-nothing),
     * and stamp the canonical assignment hash on the certificate.
     */
    @TestVisible
    private static void createAssignments(
        Id jobId,
        Id certificateId,
        String assignmentType,
        String requestJson,
        String debiasedBits
    ) {
        QuantumRandomAssignment.AssignmentRequestData req = (QuantumRandomAssignment.AssignmentRequestData) JSON.deserialize(
            requestJson,
            QuantumRandomAssignment.AssignmentRequestData.class
        );

        List<Quantum_Assignment__c> assignments;
        if (assignmentType == 'Uniform') {
            assignments = QuantumAssignmentEngine.assignUniform(
                req.recordIds,
                req.assigneeIds,
                debiasedBits,
                jobId,
                certificateId
            );
        } else if (assignmentType == 'Weighted') {
            assignments = QuantumAssignmentEngine.assignWeighted(
                req.recordIds,
                req.assigneeIds,
                req.weights,
                debiasedBits,
                jobId,
                certificateId
            );
        } else if (assignmentType == 'Subset') {
            assignments = QuantumAssignmentEngine.selectSubset(
                req.recordIds,
                req.sampleSize,
                debiasedBits,
                jobId,
                certificateId
            );
        } else {
            throw new QuantumException(
                'Unknown assignment type: ' + assignmentType
            );
        }

        // All-or-nothing: any failure throws and no assignments are kept
        insert assignments;

        FairnessCertificateService.updateAssignmentHash(
            certificateId,
            canonicalAssignmentString(assignments)
        );
    }

    /**
     * Canonical assignment serialization hashed into the certificate:
     * assignments sorted by Assignment_Index__c, one line per assignment
     * formatted 'index:recordId:assigneeId' (assigneeId empty for Subset
     * selections), joined with '\n'.
     */
    @TestVisible
    private static String canonicalAssignmentString(
        List<Quantum_Assignment__c> assignments
    ) {
        Map<Integer, Quantum_Assignment__c> byIndex = new Map<Integer, Quantum_Assignment__c>();
        List<Integer> indexes = new List<Integer>();
        for (Quantum_Assignment__c a : assignments) {
            Integer idx = (Integer) a.Assignment_Index__c;
            byIndex.put(idx, a);
            indexes.add(idx);
        }
        indexes.sort();

        List<String> lines = new List<String>();
        for (Integer idx : indexes) {
            Quantum_Assignment__c a = byIndex.get(idx);
            lines.add(
                idx +
                    ':' +
                    a.Assigned_Record_ID__c +
                    ':' +
                    (a.Assigned_To_ID__c == null ? '' : a.Assigned_To_ID__c)
            );
        }
        return String.join(lines, '\n');
    }

    /**
     * Publish a Platform Event, capturing the SaveResult. On failure,
     * append a truncated note to the job's Error_Message__c — never throw
     * (event delivery is best-effort; the job record is the source of truth).
     */
    private static void publishSafely(SObject event, Id jobId) {
        Database.SaveResult sr = EventBus.publish(event);
        if (!sr.isSuccess()) {
            List<String> messages = new List<String>();
            for (Database.Error err : sr.getErrors()) {
                messages.add(err.getMessage());
            }
            appendJobError(
                jobId,
                ('Event publish failed: ' + String.join(messages, '; '))
                    .left(1000)
            );
        }
    }

    /**
     * Append a note to the job's Error_Message__c without overwriting
     * existing content. Best-effort: never throws.
     */
    private static void appendJobError(Id jobId, String note) {
        try {
            Quantum_Job__c job = [
                SELECT Id, Error_Message__c
                FROM Quantum_Job__c
                WHERE Id = :jobId
                LIMIT 1
            ];
            String existing = String.isBlank(job.Error_Message__c)
                ? ''
                : job.Error_Message__c + '\n';
            job.Error_Message__c = (existing + note).left(32768);
            update job;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'JobProcessor.appendJobError failed for ' +
                    jobId +
                    ': ' +
                    e.getMessage()
            );
        }
    }
}
