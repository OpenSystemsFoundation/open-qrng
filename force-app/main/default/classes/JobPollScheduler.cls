/**
 * Schedulable wrapper for JobPoller.
 * Breaks the Queueable chain depth limit by scheduling the next poll
 * as a Scheduled Apex job instead of direct re-enqueue.
 *
 * Salesforce limits Queueable chaining to 5 in Developer Edition.
 * The scheduler fires `delayMinutes` in the future (JobPoller supplies the
 * stretching backoff schedule: 1 minute for the first polls, capped at 10),
 * then enqueues the poller, carrying the consecutive-transient-error streak
 * through the hop.
 *
 * If System.schedule fails (e.g. the org's 100 scheduled-jobs limit is
 * exhausted), the failure is swallowed instead of terminally failing the
 * job: a note is appended to the job record and the JobSweeper safety net
 * picks the job up on its next run.
 *
 * Sharing: declared `without sharing` deliberately. The scheduling-failure
 * fallback must be able to read/update the package-owned Quantum_Job__c
 * record regardless of which user's context the async chain runs in
 * (system maintenance only, no user-data traversal).
 */
public without sharing class JobPollScheduler implements Schedulable {
    private static final Integer ERROR_FIELD_MAX_LENGTH = 32768;

    private Id jobRecordId;
    private String externalJobId;
    private Integer pollCount;
    private Integer consecutiveTransientErrors;

    public JobPollScheduler(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount
    ) {
        this(jobRecordId, externalJobId, pollCount, 0);
    }

    public JobPollScheduler(
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

    public void execute(SchedulableContext sc) {
        System.enqueueJob(
            new JobPoller(
                jobRecordId,
                externalJobId,
                pollCount,
                consecutiveTransientErrors
            )
        );
    }

    /**
     * Schedule the next poll 1 minute from now (legacy entry point).
     */
    public static void scheduleNextPoll(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount
    ) {
        scheduleNextPoll(jobRecordId, externalJobId, pollCount, 1, 0);
    }

    /**
     * Schedule the next poll `delayMinutes` from now.
     * Uses a unique job name to avoid conflicts. Never throws: on a
     * scheduling failure (scheduled-job limit, duplicate name, ...) the
     * job is left for the sweeper and a note is appended to the record.
     */
    public static void scheduleNextPoll(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount,
        Integer delayMinutes,
        Integer consecutiveTransientErrors
    ) {
        Integer effectiveDelay = (delayMinutes == null ||
            delayMinutes < 1)
            ? 1
            : delayMinutes;
        DateTime nextRun = DateTime.now().addMinutes(effectiveDelay);
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
        String jobName = 'QuantumPoll_' + jobRecordId + '_' + pollCount;

        try {
            System.schedule(
                jobName,
                cronExp,
                new JobPollScheduler(
                    jobRecordId,
                    externalJobId,
                    pollCount,
                    consecutiveTransientErrors
                )
            );
        } catch (Exception e) {
            // Scheduler slot unavailable — do NOT fail the job. The sweeper
            // safety net monitors all non-terminal jobs and will resume.
            leaveForSweeper(jobRecordId, e.getMessage());
        }
    }

    /**
     * Record on the job that per-job polling could not be scheduled and
     * the sweeper will monitor it instead. Never throws.
     */
    private static void leaveForSweeper(Id jobRecordId, String reason) {
        try {
            List<Quantum_Job__c> jobs = [
                SELECT Id, Error_Message__c
                FROM Quantum_Job__c
                WHERE Id = :jobRecordId
                LIMIT 1
            ];
            if (jobs.isEmpty()) {
                return;
            }
            String note =
                'Poll scheduling unavailable; sweeper will monitor. (' +
                reason +
                ')';
            String existing = jobs[0].Error_Message__c;
            String combined = String.isBlank(existing)
                ? note
                : existing + '\n' + note;
            jobs[0].Error_Message__c = combined.length() >
                ERROR_FIELD_MAX_LENGTH
                ? combined.right(ERROR_FIELD_MAX_LENGTH)
                : combined;
            update jobs[0];
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'JobPollScheduler: could not record scheduling failure: ' +
                e.getMessage()
            );
        }
    }
}
