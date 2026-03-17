/**
 * Schedulable wrapper for QRNGJobPoller.
 * Breaks the Queueable chain depth limit by scheduling the next poll
 * as a Scheduled Apex job instead of direct re-enqueue.
 *
 * Salesforce limits Queueable chaining to 5 in Developer Edition.
 * This scheduler runs 1 minute in the future, then enqueues the poller.
 */
public class QRNGJobPollScheduler implements Schedulable {
    private Id jobRecordId;
    private String externalJobId;
    private Integer pollCount;

    public QRNGJobPollScheduler(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount
    ) {
        this.jobRecordId = jobRecordId;
        this.externalJobId = externalJobId;
        this.pollCount = pollCount;
    }

    public void execute(SchedulableContext sc) {
        System.enqueueJob(
            new QRNGJobPoller(jobRecordId, externalJobId, pollCount)
        );
    }

    /**
     * Schedule the next poll 1 minute from now.
     * Uses a unique job name to avoid conflicts.
     */
    public static void scheduleNextPoll(
        Id jobRecordId,
        String externalJobId,
        Integer pollCount
    ) {
        DateTime nextRun = DateTime.now().addMinutes(1);
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
        String jobName =
            'QRNGPoll_' +
            jobRecordId +
            '_' +
            pollCount;

        System.schedule(
            jobName,
            cronExp,
            new QRNGJobPollScheduler(jobRecordId, externalJobId, pollCount)
        );
    }
}
