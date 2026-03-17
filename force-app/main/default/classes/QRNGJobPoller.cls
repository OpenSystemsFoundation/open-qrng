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
                    Num_Qubits__c
                FROM Quantum_Job__c
                WHERE Id = :jobRecordId
                LIMIT 1
            ];
            job.Poll_Count__c = pollCount + 1;

            if (status == 'Completed' || status == 'COMPLETED') {
                handleCompletion(job, statusResponse);
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

        // Update job record
        job.Status__c = 'Completed';
        job.Raw_Results__c = rawBits.left(131072);
        job.Debiased_Results__c = debiasedBits.left(131072);
        job.Completed_At__c = DateTime.now();
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c =
                DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
        // Extract queue time from IBM timestamps
        job.Queue_Time_ms__c = extractQueueTimeMs(statusResponse);
        update job;

        // Validate randomness
        Map<String, Object> validationResults = QRNGValidator.validate(
            debiasedBits
        );
        Boolean isValid = (Boolean) validationResults.get('passed');

        // Create certificate
        String certStatus = isValid ? 'Certified' : 'Failed';
        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            JSON.serialize(validationResults),
            certStatus
        );

        // Publish completion event
        QRNG_Complete__e completeEvent = new QRNG_Complete__e(
            Job_Id__c = job.Id,
            Certificate_Id__c = certId,
            Num_Random_Bits__c = debiasedBits.length(),
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
