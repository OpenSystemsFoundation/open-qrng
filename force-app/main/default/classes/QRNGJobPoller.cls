/**
 * Queueable chain for polling quantum job status.
 * Implements exponential backoff: 5s, 10s, 20s, 40s, capped at 60s.
 *
 * Uses the QuantumProvider abstraction so the same poller works for
 * any registered provider (IBM, IonQ, Quantinuum, etc.).
 *
 * On completion: delegates to QRNGJobProcessor for result parsing,
 * validation, certificate creation, and event publishing.
 * On failure: updates job record, publishes QRNG_Failed__e.
 *
 * Governor limits per execution: 2 callouts (auth + status/results), ~5 SOQL, minimal DML
 */
public class QRNGJobPoller implements Queueable, Database.AllowsCallouts {
    private Id jobRecordId;
    private String externalJobId;
    private Integer pollCount;
    private static final Integer MAX_POLLS = 100;
    private static final Integer MAX_DELAY_SECONDS = 60;

    public QRNGJobPoller(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount
    ) {
        this.jobRecordId = jobRecordId;
        this.externalJobId = externalJobId;
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

            // Resolve provider from the job record
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();

            // Get job status via provider
            Map<String, Object> statusResponse = provider.getJobStatus(
                externalJobId
            );

            // Extract and normalize status via shared utility
            String rawStatus = IBMResponseParser.extractStatus(statusResponse);
            String normalized = IBMResponseParser.normalizeStatus(rawStatus);

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

            if (normalized == 'Completed') {
                handleCompletion(job, statusResponse, provider);
            } else if (normalized == 'Failed') {
                String errorMsg = IBMResponseParser.buildErrorMessage(
                    rawStatus,
                    statusResponse
                );
                job.Status__c = 'Failed';
                job.Error_Message__c = errorMsg;
                job.Completed_At__c = DateTime.now();
                update job;

                publishFailureEvent(errorMsg);
            } else {
                // Still queued or running - update status and re-enqueue
                job.Status__c = normalized;
                update job;

                // Schedule next poll via Schedulable to avoid Queueable chain depth limit
                if (!Test.isRunningTest()) {
                    QRNGJobPollScheduler.scheduleNextPoll(
                        jobRecordId,
                        externalJobId,
                        pollCount + 1
                    );
                }
            }
        } catch (Exception e) {
            handleFailure('Polling error: ' + e.getMessage());
        }
    }

    private void handleCompletion(
        Quantum_Job__c job,
        Map<String, Object> statusResponse,
        QuantumProvider provider
    ) {
        String resultsJson = provider.getJobResults(externalJobId);

        if (job.Program_Id__c == 'estimator') {
            QRNGJobProcessor.processEstimatorCompletion(
                job,
                resultsJson,
                statusResponse
            );
        } else {
            QRNGJobProcessor.processSamplerCompletion(
                job,
                resultsJson,
                statusResponse
            );
        }
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
