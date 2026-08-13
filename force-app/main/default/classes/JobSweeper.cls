/**
 * Scheduled fallback job that checks all pending quantum jobs.
 * Runs every X minutes (configurable via Quantum_Settings__c.Poll_Interval_Minutes__c).
 *
 * This catches any jobs where the initial per-job polling chain failed
 * (e.g. Queueable depth limits, scheduler-slot exhaustion, transient errors).
 *
 * Safety-net behaviors:
 *  - Skips jobs the poller touched within the last FRESH_POLL_WINDOW_MINUTES
 *    (Last_Polled_At__c), so the sweeper never races an active poll chain.
 *  - Terminally fails 'Pending' jobs older than
 *    PENDING_SUBMISSION_TIMEOUT_MINUTES: those were created but never
 *    submitted to IBM (no external job id), so they are never polled.
 *  - Terminally fails zombie jobs older than the wall-clock polling budget
 *    (JobPoller.POLL_BUDGET_MINUTES from Submitted_At__c). The external job
 *    id is left intact — results may still be recoverable on IBM via
 *    Retrieve Results.
 *  - Publishes Quantum_Job_Failed__e for every job it terminally fails
 *    (publish results are checked; failures are noted on the job).
 *  - Processes at most MAX_COMPLETIONS_PER_RUN completed jobs per sweep to
 *    bound heap (full result payloads can exceed 1MB each); remaining
 *    completed jobs are picked up on the next run.
 *  - Never flips a job to 'Completed' before processing: JobProcessor
 *    performs the status flip as part of successful completion processing.
 *    If processing throws, the job keeps its pending status so the next
 *    sweep retries, and the error is appended to Error_Message__c.
 *
 * Governor limits per execution: up to ~14 callouts (auth + one status call
 * per job + results for up to MAX_COMPLETIONS_PER_RUN completed jobs),
 * well within the 100-callout limit.
 */
public with sharing class JobSweeper implements Schedulable {
    @TestVisible
    private static final Integer MAX_JOBS_PER_RUN = 10;
    @TestVisible
    private static final Integer MAX_COMPLETIONS_PER_RUN = 3;
    @TestVisible
    private static final Integer FRESH_POLL_WINDOW_MINUTES = 3;
    @TestVisible
    private static final Integer PENDING_SUBMISSION_TIMEOUT_MINUTES = 15;
    private static final Integer ERROR_FIELD_MAX_LENGTH = 32768;
    public static final String JOB_NAME = 'Quantum_Job_Sweeper';

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new JobSweeperWorker());

        // Re-schedule for next interval (skip in test context)
        if (!Test.isRunningTest()) {
            try {
                scheduleDefault();
            } catch (Exception e) {
                System.debug('Sweeper re-schedule failed: ' + e.getMessage());
            }
        }
    }

    /**
     * Schedule the sweeper to run at the configured interval.
     * Removes any existing schedule first.
     */
    public static void scheduleDefault() {
        unschedule();

        Integer intervalMinutes = getIntervalMinutes();

        // Schedule at the next interval from now.
        // The execute() method re-schedules itself after running.
        DateTime nextRun = DateTime.now().addMinutes(intervalMinutes);
        String cronExp =
            nextRun.second() +
            ' ' +
            nextRun.minute() +
            ' ' +
            nextRun.hour() +
            ' ' +
            nextRun.day() +
            ' ' +
            nextRun.month() +
            ' ? ' +
            nextRun.year();
        System.schedule(JOB_NAME, cronExp, new JobSweeper());
    }

    /**
     * Remove the sweeper schedule.
     */
    public static void unschedule() {
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ];
        for (CronTrigger ct : existing) {
            System.abortJob(ct.Id);
        }
    }

    /**
     * Check if the sweeper is currently scheduled.
     */
    public static Boolean isScheduled() {
        return [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :JOB_NAME
            ] > 0;
    }

    private static Integer getIntervalMinutes() {
        Quantum_Settings__c settings = Quantum_Settings__c.getOrgDefaults();
        if (settings != null && settings.Poll_Interval_Minutes__c != null) {
            Integer val = (Integer) settings.Poll_Interval_Minutes__c;
            return val > 0 ? val : 5;
        }
        return 5;
    }

    /**
     * Queueable worker that does the actual callouts.
     * Schedulable cannot make callouts directly.
     *
     * Sharing: declared `without sharing` deliberately. The sweeper is
     * scheduled by whichever admin toggled it on; under Private OWD a
     * `with sharing` worker would silently miss other users' stuck jobs.
     * It operates exclusively on package-owned Quantum_Job__c records for
     * system maintenance — no user-data traversal.
     */
    public without sharing class JobSweeperWorker implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext context) {
            DateTime sweepStart = DateTime.now();
            DateTime freshPollCutoff = sweepStart.addMinutes(
                -FRESH_POLL_WINDOW_MINUTES
            );
            DateTime pendingCutoff = sweepStart.addMinutes(
                -PENDING_SUBMISSION_TIMEOUT_MINUTES
            );
            DateTime budgetCutoff = sweepStart.addMinutes(
                -JobPoller.POLL_BUDGET_MINUTES
            );

            List<Quantum_Job__c> pendingJobs = [
                SELECT
                    Id,
                    External_Job_ID__c,
                    Status__c,
                    Backend__c,
                    Circuit_QASM__c,
                    Shots__c,
                    Num_Qubits__c,
                    Purpose__c,
                    Use_Bell_Test__c,
                    Program_Id__c,
                    Submitted_At__c,
                    Validation_Results__c,
                    Error_Message__c,
                    Last_Polled_At__c,
                    CreatedDate
                FROM Quantum_Job__c
                WHERE
                    ((Status__c IN ('Submitted', 'Queued', 'Running')
                    AND External_Job_ID__c != NULL)
                    OR Status__c = 'Pending')
                    AND (Last_Polled_At__c = NULL
                    OR Last_Polled_At__c < :freshPollCutoff)
                ORDER BY Submitted_At__c ASC
                LIMIT :MAX_JOBS_PER_RUN
            ];

            if (pendingJobs.isEmpty()) {
                return;
            }

            // Resolve provider lazily — Pending/zombie jobs need no callouts
            QuantumProvider provider = null;

            List<Quantum_Job__c> jobsToUpdate = new List<Quantum_Job__c>();
            List<Quantum_Job__c> failedJobs = new List<Quantum_Job__c>();
            List<Quantum_Job__c> completedJobs = new List<Quantum_Job__c>();
            List<Map<String, Object>> completedResponses = new List<Map<String, Object>>();
            List<String> completedResults = new List<String>();

            for (Quantum_Job__c job : pendingJobs) {
                // 'Pending' = created but never submitted to IBM. There is
                // no external job id, so never poll it — fail it once the
                // submission window has clearly lapsed.
                if (job.Status__c == 'Pending') {
                    if (job.CreatedDate < pendingCutoff) {
                        markFailed(
                            job,
                            'Submission never completed — please retry.'
                        );
                        jobsToUpdate.add(job);
                        failedJobs.add(job);
                    }
                    continue;
                }

                // Zombie: past the wall-clock polling budget — stop
                // re-polling forever. IBM job id stays for manual recovery.
                if (
                    job.Submitted_At__c != null &&
                    job.Submitted_At__c < budgetCutoff
                ) {
                    markFailed(job, JobPoller.budgetExceededMessage());
                    jobsToUpdate.add(job);
                    failedJobs.add(job);
                    continue;
                }

                try {
                    if (provider == null) {
                        provider = QuantumProviderFactory.getActiveProvider();
                    }
                    Map<String, Object> statusResponse = provider.getJobStatus(
                        job.External_Job_ID__c
                    );
                    String rawStatus = IBMResponseParser.extractStatus(
                        statusResponse
                    );
                    String normalized = IBMResponseParser.normalizeStatus(
                        rawStatus
                    );

                    job.Last_Polled_At__c = DateTime.now();

                    if (normalized == 'Completed') {
                        if (completedJobs.size() >= MAX_COMPLETIONS_PER_RUN) {
                            // Bound heap: defer this completion to the next
                            // sweep; only stamp the poll time.
                            jobsToUpdate.add(job);
                            continue;
                        }
                        job.Queue_Time_ms__c = IBMResponseParser.extractQueueTimeMs(
                            statusResponse
                        );
                        // Fetch results now (before any DML) to avoid
                        // "uncommitted work pending" callout restriction.
                        String resultsJson = provider.getJobResults(
                            job.External_Job_ID__c
                        );
                        // Do NOT flip Status__c here — JobProcessor performs
                        // the flip only when processing succeeds.
                        completedJobs.add(job);
                        completedResponses.add(statusResponse);
                        completedResults.add(resultsJson);
                    } else if (normalized == 'Failed') {
                        markFailed(
                            job,
                            IBMResponseParser.buildErrorMessage(
                                rawStatus,
                                statusResponse
                            )
                        );
                        jobsToUpdate.add(job);
                        failedJobs.add(job);
                    } else if (normalized == 'Unknown') {
                        // Unrecognized IBM status — keep the job pending
                        // (it stays sweeper-visible until budget exhaustion).
                        job.Error_Message__c = appendError(
                            job.Error_Message__c,
                            'Sweep: unrecognized IBM status "' + rawStatus + '"'
                        );
                        jobsToUpdate.add(job);
                    } else {
                        job.Status__c = normalized;
                        jobsToUpdate.add(job);
                    }
                } catch (Exception e) {
                    // Don't fail the whole batch — or the job — for one
                    // (likely transient) error; the next sweep retries.
                    job.Error_Message__c = appendError(
                        job.Error_Message__c,
                        'Sweep error: ' + e.getMessage()
                    );
                    jobsToUpdate.add(job);
                }
            }

            if (!jobsToUpdate.isEmpty()) {
                update jobsToUpdate;
            }

            publishFailureEvents(failedJobs);

            // Process completed jobs (results already fetched above).
            for (Integer i = 0; i < completedJobs.size(); i++) {
                Quantum_Job__c job = completedJobs[i];
                try {
                    if (job.Program_Id__c == 'estimator') {
                        JobProcessor.processEstimatorCompletion(
                            job,
                            completedResults[i],
                            completedResponses[i]
                        );
                    } else {
                        JobProcessor.processSamplerCompletion(
                            job,
                            completedResults[i],
                            completedResponses[i]
                        );
                    }
                } catch (Exception e) {
                    // Leave the job in its pending status so the next sweep
                    // retries. Write only Id + error/poll fields — never the
                    // in-memory record, whose Status__c may have been
                    // mutated before the exception.
                    try {
                        update new Quantum_Job__c(
                            Id = job.Id,
                            Last_Polled_At__c = DateTime.now(),
                            Error_Message__c = appendError(
                                job.Error_Message__c,
                                'Result processing error: ' + e.getMessage()
                            )
                        );
                    } catch (Exception innerEx) {
                        System.debug(
                            LoggingLevel.ERROR,
                            'JobSweeper: failed to record processing error: ' +
                            innerEx.getMessage()
                        );
                    }
                }
            }
        }

        /**
         * Mark a job terminally Failed in memory (caller performs the DML
         * and queues the failure event).
         */
        private void markFailed(Quantum_Job__c job, String errorMessage) {
            job.Status__c = 'Failed';
            job.Error_Message__c = appendError(
                job.Error_Message__c,
                errorMessage
            );
            job.Completed_At__c = DateTime.now();
        }
    }

    /**
     * Publish Quantum_Job_Failed__e for every job the sweeper terminally
     * failed, mirroring the poller's failure path so event-driven monitors
     * stay informed. Publish failures are appended to Error_Message__c.
     */
    @TestVisible
    private static List<Database.SaveResult> publishFailureEvents(
        List<Quantum_Job__c> failedJobs
    ) {
        if (failedJobs == null || failedJobs.isEmpty()) {
            return new List<Database.SaveResult>();
        }

        List<Quantum_Job_Failed__e> events = new List<Quantum_Job_Failed__e>();
        for (Quantum_Job__c job : failedJobs) {
            String message = job.Error_Message__c == null
                ? 'Job failed'
                : job.Error_Message__c;
            events.add(
                new Quantum_Job_Failed__e(
                    Job_Id__c = job.Id,
                    Error_Message__c = message.left(255)
                )
            );
        }

        List<Database.SaveResult> publishResults = EventBus.publish(events);

        List<Quantum_Job__c> noteUpdates = new List<Quantum_Job__c>();
        for (Integer i = 0; i < publishResults.size(); i++) {
            if (!publishResults[i].isSuccess()) {
                List<String> publishErrors = new List<String>();
                for (Database.Error err : publishResults[i].getErrors()) {
                    publishErrors.add(err.getMessage());
                }
                noteUpdates.add(
                    new Quantum_Job__c(
                        Id = failedJobs[i].Id,
                        Error_Message__c = appendError(
                            failedJobs[i].Error_Message__c,
                            'Quantum_Job_Failed__e publish failed: ' +
                            String.join(publishErrors, '; ')
                        )
                    )
                );
            }
        }
        if (!noteUpdates.isEmpty()) {
            try {
                update noteUpdates;
            } catch (Exception e) {
                System.debug(
                    LoggingLevel.ERROR,
                    'JobSweeper: could not record event publish failure: ' +
                    e.getMessage()
                );
            }
        }
        return publishResults;
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
}
