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

        // Salesforce System.schedule only supports single-fire cron expressions.
        // To run every N minutes, we schedule multiple jobs (one per time slot).
        // For simplicity, schedule one job that runs hourly at minute 0,
        // then use the execute() method to self-reschedule N minutes later.
        // Alternative: schedule multiple jobs for each interval slot.
        //
        // Simplest approach: schedule at the next interval from now.
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
                        job.Queue_Time_ms__c = extractQueueTimeMs(
                            statusResponse
                        );
                        completedJobs.add(job);
                    } else if (normalized == 'Failed') {
                        job.Error_Message__c = buildErrorMessage(
                            status,
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
            if (job.Program_Id__c == 'estimator') {
                processEstimatorJob(job);
            } else {
                processSamplerJob(job);
            }
        }

        private void processEstimatorJob(Quantum_Job__c job) {
            String resultsJson = IBMQuantumService.getJobResults(
                job.External_Job_ID__c
            );

            Double sValue = QRNGResultParser.parseEstimatorResult(resultsJson);
            Double sValueAbs = Math.abs(sValue);

            Map<String, Object> validationResults = new Map<String, Object>();
            validationResults.put('chshSValue', sValueAbs);
            validationResults.put('bellTestPassed', sValueAbs > 2.0);
            validationResults.put('passed', sValueAbs > 2.0);
            validationResults.put('programId', 'estimator');

            try {
                Double std = QRNGResultParser.parseEstimatorStd(resultsJson);
                if (std != null) {
                    validationResults.put('chshStd', std);
                }
            } catch (Exception e) {
                // Non-critical
            }

            String validationJson = JSON.serialize(validationResults);

            job.Completed_At__c = DateTime.now();
            if (job.Submitted_At__c != null) {
                job.Execution_Time_ms__c =
                    DateTime.now().getTime() - job.Submitted_At__c.getTime();
            }
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

            String certStatus = sValueAbs > 2.0 ? 'Certified' : 'Failed';
            QRNG_Complete__e completeEvent = new QRNG_Complete__e(
                Job_Id__c = job.Id,
                Status__c = certStatus
            );
            EventBus.publish(completeEvent);
        }

        private void processSamplerJob(Quantum_Job__c job) {
            String resultsJson = IBMQuantumService.getJobResults(
                job.External_Job_ID__c
            );

            Integer numQubits = job.Num_Qubits__c != null
                ? (Integer) job.Num_Qubits__c
                : 8;
            List<String> bitstrings = QRNGResultParser.parseSamplerResults(
                resultsJson,
                numQubits
            );
            String rawBits = QRNGResultParser.concatenateBitstrings(bitstrings);
            String debiasedBits = QRNGResultParser.vonNeumannDebias(rawBits);

            String encodedRaw = QRNGResultParser.encodeForStorage(rawBits);
            job.Raw_Results__c = encodedRaw.left(131072);
            job.Result_Fingerprint__c = QRNGResultParser.generateFingerprint(
                rawBits
            );
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
            Boolean passed = validation.containsKey('passed')
                ? (Boolean) validation.get('passed')
                : true;

            // CHSH for Bell test jobs
            if (job.Use_Bell_Test__c == true) {
                Integer numPairs = numQubits / 2;
                List<String> shots = new List<String>();
                for (
                    Integer i = 0;
                    i + numQubits <= rawBits.length();
                    i += numQubits
                ) {
                    shots.add(rawBits.substring(i, i + numQubits));
                }
                Double sValue = QRNGValidator.calculateCHSH(shots, numPairs);
                validation.put('chshSValue', sValue);
                validation.put('bellTestPassed', sValue > 2.0);
                if (sValue <= 2.0) {
                    passed = false;
                    validation.put('passed', false);
                }
            }

            String validationJson = JSON.serialize(validation);
            job.Validation_Results__c = validationJson;
            update job;

            String certStatus = passed ? 'Certified' : 'Failed';
            Id certId = FairnessCertificateService.createCertificate(
                job.Id,
                validationJson,
                certStatus
            );

            // Enqueue async extended tests
            if (!Test.isRunningTest()) {
                System.enqueueJob(new QRNGValidationRunner(job.Id));
            }

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

        private String buildErrorMessage(
            String status,
            Map<String, Object> statusResponse
        ) {
            String msg = 'IBM job status: ' + status;
            if (statusResponse == null) {
                return msg;
            }
            if (statusResponse.containsKey('error')) {
                Object errObj = statusResponse.get('error');
                if (errObj instanceof Map<String, Object>) {
                    Map<String, Object> error = (Map<String, Object>) errObj;
                    if (error.containsKey('code')) {
                        msg += '\nError code: ' + error.get('code');
                    }
                    if (error.containsKey('message')) {
                        msg +=
                            '\nError message: ' + (String) error.get('message');
                    }
                    if (error.containsKey('solution')) {
                        msg += '\nSolution: ' + (String) error.get('solution');
                    }
                    if (error.containsKey('more_info')) {
                        msg +=
                            '\nMore info: ' + (String) error.get('more_info');
                    }
                } else {
                    msg += '\nError: ' + String.valueOf(errObj);
                }
            }
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

        private Decimal extractQueueTimeMs(Map<String, Object> statusResponse) {
            if (
                statusResponse == null ||
                !statusResponse.containsKey('timestamps')
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
