/**
 * Queueable chain for polling quantum job status.
 *
 * Poll cadence: the first 5 polls run 1 minute apart, then the interval
 * stretches (2, 3, 5, 7 minutes) and caps at 10 minutes. The chain stops
 * when the job reaches a terminal state or the wall-clock polling budget
 * (POLL_BUDGET_MINUTES, measured from Submitted_At__c) is exhausted.
 *
 * Error handling: transient errors (callout failures, HTTP 5xx/429,
 * timeouts, IAM/auth exchange failures, unrecognized IBM statuses) never
 * terminally fail a job — the error is appended to Error_Message__c
 * (status unchanged) and the next poll is scheduled. A job is only marked
 * Failed when:
 *   (a) IBM reports a terminal failed/cancelled state,
 *   (b) the wall-clock polling budget is exhausted (the IBM job id is left
 *       intact so results can still be recovered via Retrieve Results), or
 *   (c) MAX_CONSECUTIVE_TRANSIENT_ERRORS transient errors occur in a row
 *       (safety valve).
 *
 * Uses the QuantumProvider abstraction so the same poller works for
 * any registered provider (IBM, IonQ, Quantinuum, etc.).
 *
 * On completion: delegates to JobProcessor for result parsing,
 * validation, certificate creation, and event publishing.
 * On terminal failure: updates job record, publishes Quantum_Job_Failed__e
 * (publish results are checked; failures are noted on the job).
 *
 * Sharing: declared `without sharing` deliberately. The re-scheduled poll
 * chain runs as whichever user triggered it; with Private OWD a
 * `with sharing` poller could silently lose visibility of the very job it
 * is maintaining. The class touches only the package-owned Quantum_Job__c
 * record it was constructed with (system maintenance, no user-data
 * traversal).
 *
 * Governor limits per execution: 2 callouts (auth + status/results), ~5 SOQL, minimal DML
 */
public without sharing class JobPoller implements Queueable, Database.AllowsCallouts {
    /** Wall-clock polling budget measured from Submitted_At__c (6 hours). */
    public static final Integer POLL_BUDGET_MINUTES = 360;

    /** Consecutive transient-error safety cap before failing terminally. */
    @TestVisible
    private static final Integer MAX_CONSECUTIVE_TRANSIENT_ERRORS = 10;

    /** Fallback poll-count cap, used only when Submitted_At__c is missing. */
    @TestVisible
    private static final Integer MAX_POLLS_FALLBACK = 100;

    private static final Integer MAX_DELAY_MINUTES = 10;
    private static final Integer ERROR_FIELD_MAX_LENGTH = 32768;

    private Id jobRecordId;
    private String externalJobId;
    private Integer pollCount;
    private Integer consecutiveTransientErrors;

    public JobPoller(Id jobRecordId, String externalJobId, Integer pollCount) {
        this(jobRecordId, externalJobId, pollCount, 0);
    }

    public JobPoller(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount,
        Integer consecutiveTransientErrors
    ) {
        this.jobRecordId = jobRecordId;
        this.externalJobId = externalJobId;
        this.pollCount = pollCount;
        this.consecutiveTransientErrors = consecutiveTransientErrors == null
            ? 0
            : consecutiveTransientErrors;
    }

    public void execute(QueueableContext context) {
        Quantum_Job__c job = queryJob();
        if (
            job == null ||
            job.Status__c == 'Completed' ||
            job.Status__c == 'Failed'
        ) {
            // Job deleted or already finalized by another actor
            // (sweeper / manual retrieval) — nothing to do.
            return;
        }

        if (isBudgetExhausted(job)) {
            String budgetMsg = job.Submitted_At__c != null
                ? budgetExceededMessage()
                : 'Job polling exceeded maximum attempts (' +
                  MAX_POLLS_FALLBACK +
                  ')';
            failTerminally(job, budgetMsg);
            return;
        }

        try {
            // Resolve provider from the job record
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();

            // Get job status via provider
            Map<String, Object> statusResponse = provider.getJobStatus(
                externalJobId
            );

            // Extract and normalize status via shared utility
            String rawStatus = IBMResponseParser.extractStatus(statusResponse);
            String normalized = IBMResponseParser.normalizeStatus(rawStatus);

            job.Poll_Count__c = pollCount + 1;
            job.Last_Polled_At__c = DateTime.now();

            if (normalized == 'Completed') {
                handleCompletion(job, statusResponse, provider);
            } else if (normalized == 'Failed') {
                failTerminally(
                    job,
                    IBMResponseParser.buildErrorMessage(
                        rawStatus,
                        statusResponse
                    )
                );
            } else if (normalized == 'Unknown') {
                // Unrecognized IBM status — treat as transient: keep the
                // current status and count toward the transient safety cap.
                handleTransient(
                    job,
                    'Unrecognized IBM status "' + rawStatus + '"'
                );
            } else {
                // Still queued or running — update status and re-schedule.
                job.Status__c = normalized;
                update job;

                // Healthy poll resets the transient-error streak.
                scheduleNext(0);
            }
        } catch (Exception e) {
            if (isTransientError(e)) {
                // Re-read to avoid persisting partially mutated state.
                Quantum_Job__c freshJob = queryJob();
                if (
                    freshJob == null ||
                    freshJob.Status__c == 'Completed' ||
                    freshJob.Status__c == 'Failed'
                ) {
                    return;
                }
                freshJob.Poll_Count__c = pollCount + 1;
                freshJob.Last_Polled_At__c = DateTime.now();
                handleTransient(
                    freshJob,
                    'Transient polling error: ' + e.getMessage()
                );
            } else {
                handleFailure('Polling error: ' + e.getMessage());
            }
        }
    }

    private void handleCompletion(
        Quantum_Job__c job,
        Map<String, Object> statusResponse,
        QuantumProvider provider
    ) {
        String resultsJson = provider.getJobResults(externalJobId);

        if (job.Program_Id__c == 'estimator') {
            JobProcessor.processEstimatorCompletion(
                job,
                resultsJson,
                statusResponse
            );
        } else {
            JobProcessor.processSamplerCompletion(
                job,
                resultsJson,
                statusResponse
            );
        }
    }

    /**
     * Handle a transient error: log it on the job (status unchanged),
     * then re-schedule the next poll — unless the consecutive-transient
     * safety cap is reached, in which case the job fails terminally.
     */
    private void handleTransient(Quantum_Job__c job, String note) {
        Integer streak = consecutiveTransientErrors + 1;

        if (streak >= MAX_CONSECUTIVE_TRANSIENT_ERRORS) {
            failTerminally(
                job,
                streak +
                    ' consecutive transient polling errors — giving up. Last error: ' +
                    note
            );
            return;
        }

        // Log the error without flipping the job status.
        job.Error_Message__c = appendError(
            job.Error_Message__c,
            'Poll ' + (pollCount + 1) + ': ' + note
        );
        update job;

        scheduleNext(streak);
    }

    /**
     * Mark the job terminally Failed and publish Quantum_Job_Failed__e.
     * External_Job_ID__c is left intact so results can still be recovered
     * from the provider (e.g. via Retrieve Results in the Jobs tab).
     */
    private void failTerminally(Quantum_Job__c job, String errorMessage) {
        job.Status__c = 'Failed';
        job.Error_Message__c = appendError(job.Error_Message__c, errorMessage);
        job.Completed_At__c = DateTime.now();
        update job;

        publishFailureEvent(job, errorMessage);
    }

    private void handleFailure(String errorMessage) {
        Quantum_Job__c job = queryJob();
        if (job == null) {
            return;
        }
        failTerminally(job, errorMessage);
    }

    /**
     * Schedule the next poll via Schedulable to avoid the Queueable
     * chain depth limit. Delay follows the stretching backoff schedule.
     */
    private void scheduleNext(Integer nextTransientStreak) {
        if (Test.isRunningTest()) {
            return;
        }
        JobPollScheduler.scheduleNextPoll(
            jobRecordId,
            externalJobId,
            pollCount + 1,
            calculateDelayMinutes(pollCount + 1),
            nextTransientStreak
        );
    }

    /**
     * Publish the failure event and verify the publish result.
     * A dropped publish is noted on the job's Error_Message__c so the
     * event-driven monitor gap is at least visible on the record.
     */
    private void publishFailureEvent(Quantum_Job__c job, String errorMessage) {
        Quantum_Job_Failed__e failEvent = new Quantum_Job_Failed__e(
            Job_Id__c = jobRecordId,
            Error_Message__c = errorMessage.left(255)
        );
        Database.SaveResult publishResult = EventBus.publish(failEvent);

        if (!publishResult.isSuccess()) {
            List<String> publishErrors = new List<String>();
            for (Database.Error err : publishResult.getErrors()) {
                publishErrors.add(err.getMessage());
            }
            try {
                update new Quantum_Job__c(
                    Id = jobRecordId,
                    Error_Message__c = appendError(
                        job.Error_Message__c,
                        'Quantum_Job_Failed__e publish failed: ' +
                        String.join(publishErrors, '; ')
                    )
                );
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'JobPoller: could not record event publish failure: ' +
                    e.getMessage()
                );
            }
        }
    }

    /**
     * Wall-clock budget check. Measured from Submitted_At__c; falls back
     * to a poll-count cap when Submitted_At__c was never stamped.
     */
    @TestVisible
    private Boolean isBudgetExhausted(Quantum_Job__c job) {
        if (job.Submitted_At__c != null) {
            return DateTime.now() >=
                job.Submitted_At__c.addMinutes(POLL_BUDGET_MINUTES);
        }
        return pollCount >= MAX_POLLS_FALLBACK;
    }

    /**
     * Shared terminal message for budget/zombie expiry (also used by
     * JobSweeper). The IBM job may still complete server-side.
     */
    public static String budgetExceededMessage() {
        return 'Polling budget exceeded (' +
            (POLL_BUDGET_MINUTES / 60) +
            'h); job may still complete on IBM — use Retrieve Results to recover.';
    }

    /**
     * Classify an exception as transient (retry) vs terminal.
     * Transient: callout-layer failures, timeouts, IAM/auth token exchange
     * failures, and HTTP 5xx/429 signatures in provider error messages.
     */
    @TestVisible
    private static Boolean isTransientError(Exception e) {
        if (e instanceof System.CalloutException) {
            return true;
        }
        String msg = e.getMessage() == null ? '' : e.getMessage().toLowerCase();
        if (msg.contains('timed out') || msg.contains('timeout')) {
            return true;
        }
        if (msg.contains('iam token exchange')) {
            return true;
        }
        return Pattern.compile('\\b(429|5\\d\\d)\\b').matcher(msg).find();
    }

    /**
     * Backoff schedule in minutes: polls 0-4 fire 1 minute apart, then the
     * interval stretches (2, 3, 5, 7) and caps at MAX_DELAY_MINUTES.
     */
    @TestVisible
    private static Integer calculateDelayMinutes(Integer pollCount) {
        if (pollCount <= 4) {
            return 1;
        }
        if (pollCount == 5) {
            return 2;
        }
        if (pollCount == 6) {
            return 3;
        }
        if (pollCount == 7) {
            return 5;
        }
        if (pollCount == 8) {
            return 7;
        }
        return MAX_DELAY_MINUTES;
    }

    /**
     * Append a note to an Error_Message__c value, keeping the newest
     * content when the field limit is exceeded.
     */
    @TestVisible
    private static String appendError(String existing, String note) {
        String combined = String.isBlank(existing)
            ? note
            : existing + '\n' + note;
        return combined.length() > ERROR_FIELD_MAX_LENGTH
            ? combined.right(ERROR_FIELD_MAX_LENGTH)
            : combined;
    }

    private Quantum_Job__c queryJob() {
        List<Quantum_Job__c> jobs = [
            SELECT
                Id,
                Status__c,
                Poll_Count__c,
                Submitted_At__c,
                Num_Qubits__c,
                Use_Bell_Test__c,
                Program_Id__c,
                Backend__c,
                Validation_Results__c,
                Error_Message__c,
                External_Job_ID__c,
                Last_Polled_At__c
            FROM Quantum_Job__c
            WHERE Id = :jobRecordId
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0];
    }
}
