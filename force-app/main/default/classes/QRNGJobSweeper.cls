/**
 * Scheduled fallback job that checks all pending quantum jobs.
 * Runs every X minutes (configurable via QRNG_Settings__c.Poll_Interval_Minutes__c).
 *
 * This catches any jobs where the initial per-job polling chain failed
 * (e.g. due to Queueable depth limits or transient errors).
 *
 * Governor limits per execution: up to 10 callouts (auth + status per job),
 * batched to stay within the 100-callout limit.
 */
public class QRNGJobSweeper implements Schedulable {
    private static final Integer MAX_JOBS_PER_RUN = 10;
    public static final String JOB_NAME = 'QRNG_Job_Sweeper';

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new QRNGJobSweeperWorker());

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
        System.schedule(JOB_NAME, cronExp, new QRNGJobSweeper());
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
        QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
        if (settings != null && settings.Poll_Interval_Minutes__c != null) {
            Integer val = (Integer) settings.Poll_Interval_Minutes__c;
            return val > 0 ? val : 5;
        }
        return 5;
    }

    /**
     * Queueable worker that does the actual callouts.
     * Schedulable cannot make callouts directly.
     */
    public class QRNGJobSweeperWorker implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext context) {
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
                    Validation_Results__c
                FROM Quantum_Job__c
                WHERE
                    Status__c IN ('Submitted', 'Queued', 'Running')
                    AND External_Job_ID__c != NULL
                ORDER BY Submitted_At__c ASC
                LIMIT :MAX_JOBS_PER_RUN
            ];

            if (pendingJobs.isEmpty()) {
                return;
            }

            List<Quantum_Job__c> jobsToUpdate = new List<Quantum_Job__c>();
            List<Quantum_Job__c> completedJobs = new List<Quantum_Job__c>();
            List<Map<String, Object>> completedResponses = new List<Map<String, Object>>();

            for (Quantum_Job__c job : pendingJobs) {
                try {
                    Map<String, Object> statusResponse = IBMQuantumService.getJobStatus(
                        job.External_Job_ID__c
                    );
                    String rawStatus = IBMResponseParser.extractStatus(
                        statusResponse
                    );
                    String normalized = IBMResponseParser.normalizeStatus(
                        rawStatus
                    );

                    job.Status__c = normalized;

                    if (normalized == 'Completed') {
                        job.Queue_Time_ms__c = IBMResponseParser.extractQueueTimeMs(
                            statusResponse
                        );
                        completedJobs.add(job);
                        completedResponses.add(statusResponse);
                    } else if (normalized == 'Failed') {
                        job.Error_Message__c = IBMResponseParser.buildErrorMessage(
                            rawStatus,
                            statusResponse
                        );
                        job.Completed_At__c = DateTime.now();
                    }

                    jobsToUpdate.add(job);
                } catch (Exception e) {
                    // Don't fail the whole batch for one job
                    job.Error_Message__c = 'Sweep error: ' + e.getMessage();
                    jobsToUpdate.add(job);
                }
            }

            if (!jobsToUpdate.isEmpty()) {
                update jobsToUpdate;
            }

            // Process completed jobs (results + certificates)
            for (Integer i = 0; i < completedJobs.size(); i++) {
                Quantum_Job__c job = completedJobs[i];
                try {
                    String resultsJson = IBMQuantumService.getJobResults(
                        job.External_Job_ID__c
                    );
                    if (job.Program_Id__c == 'estimator') {
                        QRNGJobProcessor.processEstimatorCompletion(
                            job,
                            resultsJson,
                            completedResponses[i]
                        );
                    } else {
                        QRNGJobProcessor.processSamplerCompletion(
                            job,
                            resultsJson,
                            completedResponses[i]
                        );
                    }
                } catch (Exception e) {
                    job.Error_Message__c =
                        'Result processing error: ' + e.getMessage();
                    update job;
                }
            }
        }
    }
}
