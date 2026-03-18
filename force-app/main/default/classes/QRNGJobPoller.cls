/**
 * Queueable chain for polling IBM Quantum job status.
 * Implements exponential backoff: 5s, 10s, 20s, 40s, capped at 60s.
 *
 * On completion: parses results, runs validation, creates certificate, publishes events.
 * On failure: updates job record, publishes QRNG_Failed__e.
 *
 * Governor limits per execution: 2 callouts (auth + status/results), ~5 SOQL, minimal DML
 */
public class QRNGJobPoller implements Queueable, Database.AllowsCallouts {
    private Id jobRecordId;
    private String ibmJobId;
    private Integer pollCount;
    private static final Integer MAX_POLLS = 100;
    private static final Integer MAX_DELAY_SECONDS = 60;

    public QRNGJobPoller(Id jobRecordId, String ibmJobId, Integer pollCount) {
        this.jobRecordId = jobRecordId;
        this.ibmJobId = ibmJobId;
        this.pollCount = pollCount;
    }

    public void execute(QueueableContext context) {
        try {
            // Check poll limit
            if (pollCount >= MAX_POLLS) {
                handleFailure(
                    'Job polling exceeded maximum attempts (' + MAX_POLLS + ')'
                );
                return;
            }

            // Get job status from IBM
            Map<String, Object> statusResponse = IBMQuantumService.getJobStatus(
                ibmJobId
            );

            // Extract status - IBM uses nested state.status or top-level status
            String status = extractStatus(statusResponse);

            // Update job record status
            Quantum_Job__c job = [
                SELECT
                    Id,
                    Status__c,
                    Poll_Count__c,
                    Submitted_At__c,
                    Num_Qubits__c,
                    Use_Bell_Test__c,
                    Program_Id__c,
                    Backend__c,
                    Validation_Results__c
                FROM Quantum_Job__c
                WHERE Id = :jobRecordId
                LIMIT 1
            ];
            job.Poll_Count__c = pollCount + 1;

            if (status == 'Completed' || status == 'COMPLETED') {
                if (job.Program_Id__c == 'estimator') {
                    handleEstimatorCompletion(job, statusResponse);
                } else {
                    handleCompletion(job, statusResponse);
                }
            } else if (
                status == 'Failed' ||
                status == 'FAILED' ||
                status == 'Cancelled' ||
                status == 'CANCELLED'
            ) {
                String errorMsg = buildErrorMessage(status, statusResponse);
                job.Status__c = 'Failed';
                job.Error_Message__c = errorMsg;
                job.Completed_At__c = DateTime.now();
                update job;

                publishFailureEvent(errorMsg);
            } else {
                // Still queued or running - update status and re-enqueue
                if (status == 'Running' || status == 'RUNNING') {
                    job.Status__c = 'Running';
                } else {
                    job.Status__c = 'Queued';
                }
                update job;

                // Schedule next poll via Schedulable to avoid Queueable chain depth limit
                if (!Test.isRunningTest()) {
                    QRNGJobPollScheduler.scheduleNextPoll(
                        jobRecordId,
                        ibmJobId,
                        pollCount + 1
                    );
                }
            }
        } catch (Exception e) {
            handleFailure('Polling error: ' + e.getMessage());
        }
    }

    private String extractStatus(Map<String, Object> response) {
        // Try nested state.status first (newer API)
        if (response.containsKey('state')) {
            Object stateObj = response.get('state');
            if (stateObj instanceof Map<String, Object>) {
                Map<String, Object> state = (Map<String, Object>) stateObj;
                if (state.containsKey('status')) {
                    return (String) state.get('status');
                }
            }
        }
        // Fall back to top-level status
        if (response.containsKey('status')) {
            return (String) response.get('status');
        }
        return 'Unknown';
    }

    private void handleCompletion(
        Quantum_Job__c job,
        Map<String, Object> statusResponse
    ) {
        // Get results from IBM
        String resultsJson = IBMQuantumService.getJobResults(ibmJobId);

        // Parse results — handle hex-encoded samples from IBM Sampler
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
            Double sValue = QRNGValidator.calculateCHSH(bitstrings, numPairs);
            validationResults.put('chshSValue', sValue);
            validationResults.put('bellTestPassed', sValue > 2.0);

            // Bell test S > 2 is a hard gate for certification
            if (sValue <= 2.0) {
                isValid = false;
                validationResults.put('passed', false);
            }
        }

        // Single update with results + validation in one DML
        String validationJson = JSON.serialize(validationResults);
        job.Status__c = 'Completed';
        job.Raw_Results__c = rawBits.left(131072);
        job.Debiased_Results__c = debiasedBits.left(131072);
        job.Completed_At__c = DateTime.now();
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c =
                DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
        job.Queue_Time_ms__c = extractQueueTimeMs(statusResponse);
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
    }

    /**
     * Handle completion of an Estimator V2 job (CHSH verification).
     * Parses the expectation value as the S-value and updates the
     * QRNG_Backend__c record with the verification result.
     */
    private void handleEstimatorCompletion(
        Quantum_Job__c job,
        Map<String, Object> statusResponse
    ) {
        String resultsJson = IBMQuantumService.getJobResults(ibmJobId);

        // Parse individual expectation values (one per PUB/observable)
        List<Double> evs = QRNGResultParser.parseAllEstimatorResults(resultsJson);
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
                    coeffs.put(k, Double.valueOf(String.valueOf(rawCoeffs.get(k))));
                }
            }
        }

        // Fallback for old jobs without observable metadata:
        // treat the single result as the composite S-value
        if (labels.isEmpty() && !evs.isEmpty()) {
            Double fallbackS = Math.abs(evs[0]);
            Map<String, Object> vr = new Map<String, Object>();
            vr.put('chshSValue', fallbackS);
            vr.put('bellTestPassed', fallbackS > 2.0);
            vr.put('passed', fallbackS > 2.0);
            vr.put('programId', 'estimator');
            job.Raw_Results__c = 'S-Value (legacy single-PUB): ' + fallbackS;
            job.Validation_Results__c = JSON.serialize(vr);
            job.Status__c = 'Completed';
            job.Completed_At__c = DateTime.now();
            if (job.Submitted_At__c != null) {
                job.Execution_Time_ms__c =
                    DateTime.now().getTime() - job.Submitted_At__c.getTime();
            }
            job.Queue_Time_ms__c = extractQueueTimeMs(statusResponse);
            update job;

            List<QRNG_Backend__c> bkFallback = [
                SELECT Id FROM QRNG_Backend__c
                WHERE Name = :job.Backend__c LIMIT 1
            ];
            if (!bkFallback.isEmpty()) {
                bkFallback[0].CHSH_S_Value__c = fallbackS;
                bkFallback[0].CHSH_Verified_At__c = DateTime.now();
                bkFallback[0].CHSH_Job_Id__c = job.Id;
                update bkFallback;
            }

            String certSt = fallbackS > 2.0 ? 'Certified' : 'Failed';
            EventBus.publish(new QRNG_Complete__e(
                Job_Id__c = job.Id, Status__c = certSt
            ));
            return;
        }

        // Compute S = Σ(coefficient × expectation value) per term
        Double sValue = 0;
        Map<String, Object> termBreakdown = new Map<String, Object>();
        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String label = labels[i];
            Double ev = evs[i];
            Double coeff = coeffs.containsKey(label) ? coeffs.get(label) : 1.0;
            sValue += coeff * ev;

            // Identify the 2-qubit Pauli by extracting non-I characters
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
        String summary = '=== CHSH Bell Test Results ===\n\n';
        summary += 'S-Value:           ' + sValueAbs + '\n';
        summary += 'Classical Bound:   2.0\n';
        summary += 'Quantum Maximum:   2.828 (2\u221A2)\n';
        summary += 'Result:            ' +
            (sValueAbs > 2.0
                ? 'PASS - Quantum behavior confirmed'
                : 'FAIL - Below classical bound') + '\n';

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
            String coeffStr = coeff == 1.0 ? '+1' : (coeff == -1.0 ? '-1' : String.valueOf(coeff));
            summary += '<' + shortLabel + '> = ' + evs[i];
            if (i < stds.size() && stds[i] != null) {
                summary += '  (std: ' + stds[i] + ')';
            }
            summary += '  [coeff: ' + coeffStr + ', contribution: ' +
                (coeff * evs[i]) + ']\n';
        }
        summary += '\nS = ' + sValueAbs + '\n';

        job.Raw_Results__c = summary;

        String validationJson = JSON.serialize(validationResults);

        // Update job record
        job.Status__c = 'Completed';
        job.Completed_At__c = DateTime.now();
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c =
                DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
        job.Queue_Time_ms__c = extractQueueTimeMs(statusResponse);
        job.Validation_Results__c = validationJson;
        update job;

        // Update QRNG_Backend__c with verification result
        List<QRNG_Backend__c> backends = [
            SELECT Id
            FROM QRNG_Backend__c
            WHERE Name = :job.Backend__c
            LIMIT 1
        ];
        if (!backends.isEmpty()) {
            backends[0].CHSH_S_Value__c = sValueAbs;
            backends[0].CHSH_Verified_At__c = DateTime.now();
            backends[0].CHSH_Job_Id__c = job.Id;
            update backends;
        }

        // Publish completion event (no certificate for verification jobs)
        String certStatus = sValueAbs > 2.0 ? 'Certified' : 'Failed';
        QRNG_Complete__e completeEvent = new QRNG_Complete__e(
            Job_Id__c = job.Id,
            Status__c = certStatus
        );
        EventBus.publish(completeEvent);
    }

    private void handleFailure(String errorMessage) {
        Quantum_Job__c job = [
            SELECT Id
            FROM Quantum_Job__c
            WHERE Id = :jobRecordId
            LIMIT 1
        ];
        job.Status__c = 'Failed';
        job.Error_Message__c = errorMessage;
        job.Completed_At__c = DateTime.now();
        update job;

        publishFailureEvent(errorMessage);
    }

    private void publishFailureEvent(String errorMessage) {
        QRNG_Failed__e failEvent = new QRNG_Failed__e(
            Job_Id__c = jobRecordId,
            Error_Message__c = errorMessage.left(255)
        );
        EventBus.publish(failEvent);
    }

    /**
     * Build a verbose error message from the IBM status response.
     * Extracts error code, message, solution, and any nested details.
     */
    @TestVisible
    private static String buildErrorMessage(
        String status,
        Map<String, Object> statusResponse
    ) {
        String msg = 'IBM job status: ' + status;

        if (statusResponse == null) {
            return msg;
        }

        // Extract error object
        if (statusResponse.containsKey('error')) {
            Object errObj = statusResponse.get('error');
            if (errObj instanceof Map<String, Object>) {
                Map<String, Object> error = (Map<String, Object>) errObj;

                if (error.containsKey('code')) {
                    msg += '\nError code: ' + error.get('code');
                }
                if (error.containsKey('message')) {
                    msg += '\nError message: ' + (String) error.get('message');
                }
                if (error.containsKey('solution')) {
                    msg += '\nSolution: ' + (String) error.get('solution');
                }
                if (error.containsKey('more_info')) {
                    msg += '\nMore info: ' + (String) error.get('more_info');
                }
            } else {
                msg += '\nError: ' + String.valueOf(errObj);
            }
        }

        // Some IBM responses include state.reason
        if (statusResponse.containsKey('state')) {
            Object stateObj = statusResponse.get('state');
            if (stateObj instanceof Map<String, Object>) {
                Map<String, Object> state = (Map<String, Object>) stateObj;
                if (state.containsKey('reason')) {
                    msg += '\nReason: ' + (String) state.get('reason');
                }
                if (state.containsKey('reason_code')) {
                    msg += '\nReason code: ' + state.get('reason_code');
                }
            }
        }

        return msg;
    }

    /**
     * Extract queue time in milliseconds from IBM status response timestamps.
     * IBM returns timestamps: { created: "...", running: "...", completed: "..." }
     * Queue time = running - created.
     */
    @TestVisible
    private static Decimal extractQueueTimeMs(
        Map<String, Object> statusResponse
    ) {
        if (
            statusResponse == null || !statusResponse.containsKey('timestamps')
        ) {
            return null;
        }
        Object tsObj = statusResponse.get('timestamps');
        if (!(tsObj instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> timestamps = (Map<String, Object>) tsObj;
        String created = (String) timestamps.get('created');
        String running = (String) timestamps.get('running');
        if (String.isBlank(created) || String.isBlank(running)) {
            return null;
        }
        try {
            DateTime createdDt = DateTime.valueOf(
                created.replace('T', ' ').replace('Z', '')
            );
            DateTime runningDt = DateTime.valueOf(
                running.replace('T', ' ').replace('Z', '')
            );
            return runningDt.getTime() - createdDt.getTime();
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Calculate backoff delay in seconds
     */
    @TestVisible
    private static Integer calculateDelay(Integer pollCount) {
        Integer delay = (Integer) Math.min(
            5 * Math.pow(2, pollCount),
            MAX_DELAY_SECONDS
        );
        return delay;
    }
}
