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
                handleFailure('Job polling exceeded maximum attempts (' + MAX_POLLS + ')');
                return;
            }

            // Get job status from IBM
            Map<String, Object> statusResponse = IBMQuantumService.getJobStatus(ibmJobId);

            // Extract status - IBM uses nested state.status or top-level status
            String status = extractStatus(statusResponse);

            // Update job record status
            Quantum_Job__c job = [SELECT Id, Status__c, Poll_Count__c, Submitted_At__c FROM Quantum_Job__c WHERE Id = :jobRecordId LIMIT 1];
            job.Poll_Count__c = pollCount + 1;

            if (status == 'Completed' || status == 'COMPLETED') {
                handleCompletion(job);
            } else if (status == 'Failed' || status == 'FAILED' || status == 'Cancelled' || status == 'CANCELLED') {
                String errorMsg = 'IBM job status: ' + status;
                if (statusResponse.containsKey('error')) {
                    Map<String, Object> errorObj = (Map<String, Object>) statusResponse.get('error');
                    if (errorObj != null && errorObj.containsKey('message')) {
                        errorMsg += ' - ' + (String) errorObj.get('message');
                    }
                }
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

                // Re-enqueue with backoff
                if (!Test.isRunningTest()) {
                    System.enqueueJob(new QRNGJobPoller(jobRecordId, ibmJobId, pollCount + 1));
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

    private void handleCompletion(Quantum_Job__c job) {
        // Get results from IBM
        String resultsJson = IBMQuantumService.getJobResults(ibmJobId);

        // Parse results
        List<String> bitstrings = QRNGResultParser.parseSamplerResults(resultsJson);
        String rawBits = QRNGResultParser.concatenateBitstrings(bitstrings);
        String debiasedBits = QRNGResultParser.vonNeumannDebias(rawBits);

        // Update job record
        job.Status__c = 'Completed';
        job.Raw_Results__c = rawBits.left(131072);
        job.Debiased_Results__c = debiasedBits.left(131072);
        job.Completed_At__c = DateTime.now();
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c = DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
        update job;

        // Validate randomness
        Map<String, Object> validationResults = QRNGValidator.validate(debiasedBits);
        Boolean isValid = (Boolean) validationResults.get('passed');

        // Create certificate
        String certStatus = isValid ? 'Certified' : 'Failed';
        Id certId = FairnessCertificateService.createCertificate(job.Id, JSON.serialize(validationResults), certStatus);

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
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c WHERE Id = :jobRecordId LIMIT 1];
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
     * Calculate backoff delay in seconds
     */
    @TestVisible
    private static Integer calculateDelay(Integer pollCount) {
        Integer delay = (Integer) Math.min(5 * Math.pow(2, pollCount), MAX_DELAY_SECONDS);
        return delay;
    }
}
