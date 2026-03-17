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
    }

    /**
     * Schedule the sweeper to run at the configured interval.
     * Removes any existing schedule first.
     */
    public static void scheduleDefault() {
        unschedule();

        Integer intervalMinutes = getIntervalMinutes();

        // Salesforce cron: seconds minutes hours day_of_month month day_of_week
        // Note: Salesforce doesn't support step values (0/N) in System.schedule
        // Use a specific minute offset instead, or run every hour
        // For intervals <= 60 min, schedule at specific minutes past the hour
        String cronExp;
        if (intervalMinutes <= 1) {
            // Every minute not supported in scheduled apex — minimum is every hour
            cronExp = '0 0 * * * ?';
        } else if (intervalMinutes <= 60) {
            // Run at specific minute intervals using comma-separated list
            List<String> minutes = new List<String>();
            for (Integer m = 0; m < 60; m += intervalMinutes) {
                minutes.add(String.valueOf(m));
            }
            cronExp = '0 ' + String.join(minutes, ',') + ' * * * ?';
        } else {
            cronExp = '0 0 * * * ?';
        }
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
                    Submitted_At__c
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

            for (Quantum_Job__c job : pendingJobs) {
                try {
                    Map<String, Object> statusResponse = IBMQuantumService.getJobStatus(
                        job.External_Job_ID__c
                    );
                    String status = extractStatus(statusResponse);
                    String normalized = normalizeStatus(status);

                    job.Status__c = normalized;

                    if (normalized == 'Completed') {
                        completedJobs.add(job);
                    } else if (normalized == 'Failed') {
                        String errorMsg = 'IBM job status: ' + status;
                        if (statusResponse.containsKey('error')) {
                            Map<String, Object> errorObj = (Map<String, Object>) statusResponse.get(
                                'error'
                            );
                            if (
                                errorObj != null &&
                                errorObj.containsKey('message')
                            ) {
                                errorMsg +=
                                    ' - ' + (String) errorObj.get('message');
                            }
                        }
                        job.Error_Message__c = errorMsg;
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
            for (Quantum_Job__c job : completedJobs) {
                try {
                    processCompletedJob(job);
                } catch (Exception e) {
                    job.Error_Message__c =
                        'Result processing error: ' + e.getMessage();
                    update job;
                }
            }
        }

        private void processCompletedJob(Quantum_Job__c job) {
            String resultsJson = IBMQuantumService.getJobResults(
                job.External_Job_ID__c
            );

            List<String> bitstrings = QRNGResultParser.parseSamplerResults(
                resultsJson
            );
            String rawBits = QRNGResultParser.concatenateBitstrings(bitstrings);
            String debiasedBits = QRNGResultParser.vonNeumannDebias(rawBits);

            job.Raw_Results__c = rawBits.left(131072);
            job.Debiased_Results__c = debiasedBits.left(131072);
            job.Completed_At__c = DateTime.now();
            if (job.Submitted_At__c != null) {
                job.Execution_Time_ms__c =
                    DateTime.now().getTime() - job.Submitted_At__c.getTime();
            }
            update job;

            Map<String, Object> validation = QRNGValidator.validate(
                debiasedBits
            );
            String validationJson = JSON.serialize(validation);
            Boolean passed = validation.containsKey('passed')
                ? (Boolean) validation.get('passed')
                : true;
            String certStatus = passed ? 'Certified' : 'Failed';
            Id certId = FairnessCertificateService.createCertificate(
                job.Id,
                validationJson,
                certStatus
            );

            QRNG_Complete__e completeEvent = new QRNG_Complete__e(
                Job_Id__c = job.Id,
                Certificate_Id__c = certId,
                Num_Random_Bits__c = debiasedBits.length(),
                Status__c = certStatus
            );
            EventBus.publish(completeEvent);
        }

        private String extractStatus(Map<String, Object> response) {
            if (response.containsKey('state')) {
                Object stateObj = response.get('state');
                if (stateObj instanceof Map<String, Object>) {
                    Map<String, Object> state = (Map<String, Object>) stateObj;
                    if (state.containsKey('status')) {
                        return (String) state.get('status');
                    }
                }
            }
            if (response.containsKey('status')) {
                return (String) response.get('status');
            }
            return 'Unknown';
        }

        private String normalizeStatus(String ibmStatus) {
            if (ibmStatus == null)
                return 'Submitted';
            String lower = ibmStatus.toLowerCase();
            if (lower == 'completed' || lower == 'result_ready')
                return 'Completed';
            if (lower == 'running')
                return 'Running';
            if (lower == 'queued' || lower == 'pending_in_queue')
                return 'Queued';
            if (
                lower == 'failed' ||
                lower == 'cancelled' ||
                lower == 'canceled'
            )
                return 'Failed';
            return 'Submitted';
        }
    }
}
