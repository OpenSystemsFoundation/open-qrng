@IsTest
private class JobSweeper_Test {
    /**
     * Mock for IBM Quantum API callouts used in sweeper worker tests.
     */
    private class MockSweeperCallouts implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs/') &&
                req.getEndpoint().contains('/results')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"results":[{"data":{"meas":{"samples":["0110","1001","1110","0011"]}}}]}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_123","status":"Completed","state":{"status":"Completed"},' +
                    '"timestamps":{"created":"2026-03-17T10:00:00Z","running":"2026-03-17T10:00:07Z"}}'
                );
            }
            return res;
        }
    }

    /**
     * Mock that returns a failed status for testing error handling.
     */
    private class MockSweeperFailedStatus implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_fail","status":"Failed","state":{"status":"Failed"},"error":{"message":"Backend error"}}'
                );
            }
            return res;
        }
    }

    /**
     * Mock that returns estimator results for CHSH verification.
     */
    private class MockSweeperEstimatorCallouts implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs/') &&
                req.getEndpoint().contains('/results')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"results":[{"data":{"evs":[2.55],"stds":[0.03]}}]}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_est","status":"Completed","state":{"status":"Completed"}}'
                );
            }
            return res;
        }
    }

    /**
     * Mock that returns a Queued status (not terminal).
     */
    private class MockSweeperQueuedStatus implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_q","status":"Queued","state":{"status":"Queued"}}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testScheduleAndUnschedule() {
        Test.startTest();
        JobSweeper.scheduleDefault();
        Test.stopTest();

        System.assertEquals(
            true,
            JobSweeper.isScheduled(),
            'Sweeper should be scheduled'
        );

        JobSweeper.unschedule();
        System.assertEquals(
            false,
            JobSweeper.isScheduled(),
            'Sweeper should be unscheduled'
        );
    }

    @IsTest
    static void testSweeperWithNoJobs() {
        JobSweeper.JobSweeperWorker worker = new JobSweeper.JobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        // No jobs to process — should complete without error
        System.assert(true, 'Worker executed without error');
    }

    @IsTest
    static void testSweeperControllerMethods() {
        // startSweeper/stopSweeper are gated on QuantumFair_Administer (B6)
        SetupController.adminOverrideForTests = true;
        Test.startTest();
        SetupController.startSweeper();
        Test.stopTest();

        System.assertEquals(
            true,
            JobSweeper.isScheduled(),
            'Sweeper should be active after startSweeper'
        );

        SetupController.stopSweeper();
        System.assertEquals(
            false,
            JobSweeper.isScheduled(),
            'Sweeper should be inactive after stopSweeper'
        );
    }

    @IsTest
    static void testSweeperWorkerWithPendingCompletedJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_sweep_123',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Circuit_QASM__c = 'OPENQASM 3.0;',
            Shots__c = 1024,
            Num_Qubits__c = 4,
            Purpose__c = 'Test sweep',
            Use_Bell_Test__c = false,
            Submitted_At__c = DateTime.now().addMinutes(-10)
        );
        insert job;

        JobSweeper.JobSweeperWorker worker = new JobSweeper.JobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Completed_At__c, Queue_Time_ms__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Completed',
            updated.Status__c,
            'Job should be marked Completed'
        );
        System.assertEquals(
            7000,
            updated.Queue_Time_ms__c,
            'Queue time should be extracted'
        );
    }

    @IsTest
    static void testSweeperWorkerWithFailedJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperFailedStatus());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_sweep_fail',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 4,
            Submitted_At__c = DateTime.now().addMinutes(-10)
        );
        insert job;

        JobSweeper.JobSweeperWorker worker = new JobSweeper.JobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Error_Message__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Failed',
            updated.Status__c,
            'Job should be marked Failed'
        );
        System.assert(
            updated.Error_Message__c.contains('Backend error'),
            'Error message should contain IBM error: ' +
            updated.Error_Message__c
        );
        System.assertNotEquals(
            null,
            updated.Completed_At__c,
            'Failed job should have completed timestamp'
        );
    }

    /**
     * Mock that returns a failed status with full error detail.
     */
    private class MockSweeperVerboseFailedStatus implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_verbose","status":"Failed",' +
                        '"state":{"status":"Failed","reason":"QPU offline","reason_code":9001},' +
                        '"error":{"code":5678,"message":"Transpilation error","solution":"Simplify circuit","more_info":"https://ibm.com/help/5678"}}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testSweeperWorkerWithVerboseFailedJob() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockSweeperVerboseFailedStatus()
        );
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_sweep_verbose',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 4,
            Submitted_At__c = DateTime.now().addMinutes(-10)
        );
        insert job;

        JobSweeper.JobSweeperWorker worker = new JobSweeper.JobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Error_Message__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', updated.Status__c);
        System.assert(
            updated.Error_Message__c.contains('5678'),
            'Should contain error code'
        );
        System.assert(
            updated.Error_Message__c.contains('Transpilation error'),
            'Should contain error message'
        );
        System.assert(
            updated.Error_Message__c.contains('Simplify circuit'),
            'Should contain solution'
        );
        System.assert(
            updated.Error_Message__c.contains('QPU offline'),
            'Should contain reason'
        );
    }

    @IsTest
    static void testSweeperWorkerWithEstimatorJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperEstimatorCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Provider__c provider = new Quantum_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        Quantum_Backend__c backend = new Quantum_Backend__c(
            Name = 'sweep_est_backend',
            Backend_Key__c = 'ibm:sweep_est_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 127
        );
        insert backend;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_sweep_est',
            Backend__c = 'sweep_est_backend',
            Status__c = 'Submitted',
            Program_Id__c = 'estimator',
            Shots__c = 4096,
            Num_Qubits__c = 2,
            Submitted_At__c = DateTime.now().addMinutes(-5)
        );
        insert job;

        JobSweeper.JobSweeperWorker worker = new JobSweeper.JobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Validation_Results__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Completed', updated.Status__c);
        System.assertNotEquals(
            null,
            updated.Validation_Results__c,
            'Validation_Results__c should be set. Error: ' +
            updated.Error_Message__c
        );
        System.assert(
            updated.Validation_Results__c.contains('chshSValue'),
            'Should have CHSH results'
        );

        Quantum_Backend__c updatedBk = [
            SELECT CHSH_S_Value__c
            FROM Quantum_Backend__c
            WHERE Id = :backend.Id
        ];
        System.assertEquals(2.55, updatedBk.CHSH_S_Value__c);
    }

    @IsTest
    static void testSweeperWorkerWithQueuedJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperQueuedStatus());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_sweep_q',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 4,
            Submitted_At__c = DateTime.now().addMinutes(-2)
        );
        insert job;

        JobSweeper.JobSweeperWorker worker = new JobSweeper.JobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Queued',
            updated.Status__c,
            'Non-terminal job should stay in queue'
        );
    }

    /**
     * Mock that reports Completed but returns malformed results, so
     * completion processing throws.
     */
    private class MockSweeperGarbageResults implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs/') &&
                req.getEndpoint().contains('/results')
            ) {
                res.setStatusCode(200);
                res.setBody('{"unexpected":true}');
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_garbage","status":"Completed","state":{"status":"Completed"}}'
                );
            }
            return res;
        }
    }

    /**
     * Mock that returns an unrecognized IBM status.
     */
    private class MockSweeperUnknownStatus implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_sweep_u","status":"weird_status","state":{"status":"weird_status"}}'
                );
            }
            return res;
        }
    }

    private static void setupAuthAndSettings() {
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;
    }

    private static Quantum_Job__c makeSweepJob(
        String externalJobId,
        String status
    ) {
        return new Quantum_Job__c(
            External_Job_ID__c = externalJobId,
            Backend__c = 'test_backend',
            Status__c = status,
            Shots__c = 1024,
            Num_Qubits__c = 4,
            Submitted_At__c = DateTime.now().addMinutes(-10)
        );
    }

    @IsTest
    static void testSweeperSkipsFreshlyPolledJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperQueuedStatus());
        setupAuthAndSettings();

        Quantum_Job__c job = makeSweepJob('job_sweep_q', 'Submitted');
        job.Last_Polled_At__c = DateTime.now().addMinutes(-1);
        insert job;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Submitted',
            updated.Status__c,
            'A job polled within the fresh window must be skipped (would be Queued if swept)'
        );
    }

    @IsTest
    static void testSweeperSweepsStalePolledJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperQueuedStatus());
        setupAuthAndSettings();

        Quantum_Job__c job = makeSweepJob('job_sweep_q', 'Submitted');
        job.Last_Polled_At__c = DateTime.now().addMinutes(-10);
        insert job;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Last_Polled_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Queued',
            updated.Status__c,
            'A job with a stale Last_Polled_At__c must be swept'
        );
        System.assert(
            updated.Last_Polled_At__c >= DateTime.now().addMinutes(-2),
            'The sweep should re-stamp Last_Polled_At__c'
        );
    }

    @IsTest
    static void testSweeperFailsStalePendingJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperQueuedStatus());
        setupAuthAndSettings();

        // 'Pending' = created but never submitted to IBM: no external id
        Quantum_Job__c job = new Quantum_Job__c(
            Backend__c = 'test_backend',
            Status__c = 'Pending',
            Shots__c = 1024,
            Num_Qubits__c = 4
        );
        insert job;
        Test.setCreatedDate(job.Id, DateTime.now().addMinutes(-20));

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Error_Message__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Failed',
            updated.Status__c,
            'A Pending job older than the submission timeout must fail'
        );
        System.assert(
            updated.Error_Message__c.contains('Submission never completed'),
            'Should explain the stuck submission: ' + updated.Error_Message__c
        );
        System.assertNotEquals(null, updated.Completed_At__c);
    }

    @IsTest
    static void testSweeperKeepsFreshPendingJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperQueuedStatus());
        setupAuthAndSettings();

        Quantum_Job__c job = new Quantum_Job__c(
            Backend__c = 'test_backend',
            Status__c = 'Pending',
            Shots__c = 1024,
            Num_Qubits__c = 4
        );
        insert job;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Pending',
            updated.Status__c,
            'A freshly created Pending job must be left for the submitter'
        );
    }

    @IsTest
    static void testSweeperFailsZombieJobPastBudget() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperQueuedStatus());
        setupAuthAndSettings();

        Quantum_Job__c job = makeSweepJob('job_sweep_zombie', 'Running');
        job.Submitted_At__c = DateTime.now().addHours(-7);
        insert job;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT
                Status__c,
                Error_Message__c,
                Completed_At__c,
                External_Job_ID__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Failed',
            updated.Status__c,
            'A job past the wall-clock budget must be terminally failed'
        );
        System.assert(
            updated.Error_Message__c.contains('Polling budget exceeded'),
            'Should carry the recoverable-results message: ' +
            updated.Error_Message__c
        );
        System.assertEquals(
            'job_sweep_zombie',
            updated.External_Job_ID__c,
            'IBM job id must stay intact for manual recovery'
        );
        System.assertNotEquals(null, updated.Completed_At__c);
    }

    @IsTest
    static void testSweeperLeavesStatusPendingWhenProcessingThrows() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperGarbageResults());
        setupAuthAndSettings();

        Quantum_Job__c job = makeSweepJob('job_sweep_garbage', 'Submitted');
        insert job;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Submitted',
            updated.Status__c,
            'The job must NOT be flipped to Completed when processing throws — the next sweep retries'
        );
        System.assert(
            updated.Error_Message__c.contains('Result processing error'),
            'The processing error should be recorded: ' +
            updated.Error_Message__c
        );
    }

    @IsTest
    static void testSweeperUnknownStatusKeepsJobPending() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperUnknownStatus());
        setupAuthAndSettings();

        Quantum_Job__c job = makeSweepJob('job_sweep_u', 'Submitted');
        insert job;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Submitted',
            updated.Status__c,
            'An unrecognized IBM status must keep the job in its pending status'
        );
        System.assert(
            updated.Error_Message__c.contains('weird_status'),
            'The raw unrecognized status should be logged: ' +
            updated.Error_Message__c
        );
    }

    @IsTest
    static void testSweeperCapsCompletionsPerRun() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperCallouts());
        setupAuthAndSettings();

        List<Quantum_Job__c> jobs = new List<Quantum_Job__c>();
        for (Integer i = 0; i < 5; i++) {
            jobs.add(makeSweepJob('job_sweep_cap_' + i, 'Submitted'));
        }
        insert jobs;

        Test.startTest();
        new JobSweeper.JobSweeperWorker().execute(null);
        Test.stopTest();

        Integer completedCount = [
            SELECT COUNT()
            FROM Quantum_Job__c
            WHERE Id IN :jobs AND Status__c = 'Completed'
        ];
        Integer deferredCount = [
            SELECT COUNT()
            FROM Quantum_Job__c
            WHERE
                Id IN :jobs
                AND Status__c = 'Submitted'
                AND Last_Polled_At__c != NULL
        ];
        System.assertEquals(
            3,
            completedCount,
            'At most 3 completions may be processed per sweep (heap bound)'
        );
        System.assertEquals(
            2,
            deferredCount,
            'Deferred completions keep their pending status with a fresh poll stamp'
        );
    }

    @IsTest
    static void testPublishFailureEventsChecksSaveResults() {
        Quantum_Job__c job = makeSweepJob('job_sweep_evt', 'Failed');
        job.Error_Message__c = 'Backend error';
        insert job;

        Test.startTest();
        List<Database.SaveResult> results = JobSweeper.publishFailureEvents(
            new List<Quantum_Job__c>{ job }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One event per failed job');
        System.assertEquals(
            true,
            results[0].isSuccess(),
            'The failure event should publish successfully'
        );

        // Empty and null input are no-ops
        System.assertEquals(
            0,
            JobSweeper.publishFailureEvents(new List<Quantum_Job__c>()).size()
        );
        System.assertEquals(0, JobSweeper.publishFailureEvents(null).size());
    }

    @IsTest
    static void testSchedulableExecute() {
        Test.startTest();
        JobSweeper sweeper = new JobSweeper();
        sweeper.execute(null);
        Test.stopTest();

        // The execute method enqueues the worker — verify no exception
        System.assert(true, 'Schedulable execute completed without error');
    }

    @IsTest
    static void testScheduleWithCustomInterval() {
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Poll_Interval_Minutes__c = 15
        );
        upsert s;

        Test.startTest();
        JobSweeper.scheduleDefault();
        Test.stopTest();

        System.assertEquals(true, JobSweeper.isScheduled());
        JobSweeper.unschedule();
    }
}
