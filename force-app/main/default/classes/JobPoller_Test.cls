@IsTest
private class JobPoller_Test {
    private class MockCompletedJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/results')) {
                res.setBody(
                    '{"results":[{"data":{"meas":{"samples":["0x66","0x99","0xe3","0x35","0xaa","0x55","0xcc","0x3c"]}}}]}'
                );
            } else {
                res.setBody(
                    '{"id":"job_test","status":"Completed","state":{"status":"Completed"},' +
                    '"timestamps":{"created":"2026-03-17T10:00:00Z","running":"2026-03-17T10:00:05Z","completed":"2026-03-17T10:00:08Z"}}'
                );
            }
            return res;
        }
    }

    private class MockQueuedJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"id":"job_test","status":"Queued","state":{"status":"Queued"}}'
            );
            return res;
        }
    }

    private class MockRunningJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"id":"job_test","status":"Running","state":{"status":"Running"}}'
            );
            return res;
        }
    }

    private class MockFailedJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"id":"job_test","status":"Failed","state":{"status":"Failed"},"error":{"message":"Hardware error"}}'
            );
            return res;
        }
    }

    private class MockCancelledJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"id":"job_test","status":"Cancelled","state":{"status":"Cancelled","reason":"User cancelled","reason_code":1001}}'
            );
            return res;
        }
    }

    private class MockUnknownStatusJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"id":"job_test","status":"mystery_state","state":{"status":"mystery_state"}}'
            );
            return res;
        }
    }

    /**
     * Simulates a transport-level callout failure (timeout, connection
     * reset, etc.) — the classic transient error.
     */
    private class MockCalloutTimeout implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new System.CalloutException('Read timed out');
        }
    }

    private class MockEstimatorCompletedJob implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('/results')) {
                res.setBody(
                    '{"results":[{"data":{"evs":[2.61],"stds":[0.04]}}]}'
                );
            } else {
                res.setBody(
                    '{"id":"job_est","status":"Completed","state":{"status":"Completed"},' +
                    '"timestamps":{"created":"2026-03-17T10:00:00Z","running":"2026-03-17T10:00:05Z","completed":"2026-03-17T10:00:08Z"}}'
                );
            }
            return res;
        }
    }

    private static Quantum_Job__c makeJob(String status, DateTime submittedAt) {
        return new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = status,
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Submitted_At__c = submittedAt
        );
    }

    @IsTest
    static void testPollCompletedJob() {
        Test.setMock(HttpCalloutMock.class, new MockCompletedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        job.Shots__c = 8;
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT
                Id,
                Status__c,
                Queue_Time_ms__c,
                Raw_Results__c,
                Debiased_Results__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Completed', job.Status__c);
        System.assertEquals(
            5000,
            job.Queue_Time_ms__c,
            'Queue time should be 5000ms (5s)'
        );
    }

    @IsTest
    static void testPollQueuedJob() {
        Test.setMock(HttpCalloutMock.class, new MockQueuedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Poll_Count__c, Last_Polled_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Queued', job.Status__c);
        System.assertEquals(
            1,
            job.Poll_Count__c,
            'Poll counter should increment'
        );
        System.assertNotEquals(
            null,
            job.Last_Polled_At__c,
            'Every poll should stamp Last_Polled_At__c (sweeper freshness signal)'
        );
    }

    @IsTest
    static void testPollRunningJob() {
        Test.setMock(HttpCalloutMock.class, new MockRunningJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Running', job.Status__c);
    }

    @IsTest
    static void testPollFailedJob() {
        Test.setMock(HttpCalloutMock.class, new MockFailedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', job.Status__c);
        System.assert(
            job.Error_Message__c.contains('Failed'),
            'Should contain failure info'
        );
    }

    @IsTest
    static void testPollCancelledJob() {
        Test.setMock(HttpCalloutMock.class, new MockCancelledJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', job.Status__c);
        System.assert(
            job.Error_Message__c.contains('User cancelled'),
            'Should contain cancellation reason'
        );
        System.assertNotEquals(null, job.Completed_At__c);
    }

    @IsTest
    static void testTransientErrorKeepsJobPending() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutTimeout());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Running', DateTime.now());
        insert job;

        Test.startTest();
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 3));
        Test.stopTest();

        job = [
            SELECT
                Id,
                Status__c,
                Poll_Count__c,
                Error_Message__c,
                Last_Polled_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Running',
            job.Status__c,
            'A transient error must NOT flip the job status'
        );
        System.assertEquals(
            4,
            job.Poll_Count__c,
            'Poll counter should still increment on a transient error'
        );
        System.assert(
            job.Error_Message__c.contains('Transient polling error'),
            'The transient error should be logged on the job: ' +
            job.Error_Message__c
        );
        System.assert(
            job.Error_Message__c.contains('Read timed out'),
            'The underlying error text should be preserved'
        );
        System.assertNotEquals(null, job.Last_Polled_At__c);
    }

    @IsTest
    static void testConsecutiveTransientCapFailsTerminally() {
        Test.setMock(HttpCalloutMock.class, new MockCalloutTimeout());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Running', DateTime.now());
        insert job;

        Test.startTest();
        // 9 prior consecutive transient errors — this one is the 10th
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 12, 9));
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Failed',
            job.Status__c,
            'Consecutive-transient safety cap should fail the job'
        );
        System.assert(
            job.Error_Message__c.contains('consecutive transient'),
            'Should explain the transient-error cap: ' + job.Error_Message__c
        );
        System.assertNotEquals(null, job.Completed_At__c);
    }

    @IsTest
    static void testUnknownStatusTreatedAsTransient() {
        Test.setMock(HttpCalloutMock.class, new MockUnknownStatusJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        insert job;

        Test.startTest();
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 0));
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Poll_Count__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Submitted',
            job.Status__c,
            'An unknown IBM status must not change the job status'
        );
        System.assertEquals(1, job.Poll_Count__c);
        System.assert(
            job.Error_Message__c.contains('mystery_state'),
            'The raw unrecognized status should be logged: ' +
            job.Error_Message__c
        );
    }

    @IsTest
    static void testUnknownStatusCountsTowardTransientCap() {
        Test.setMock(HttpCalloutMock.class, new MockUnknownStatusJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        insert job;

        Test.startTest();
        // 9 prior consecutive transient errors — this unknown status is the 10th
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 9, 9));
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', job.Status__c);
        System.assert(
            job.Error_Message__c.contains('mystery_state'),
            'Terminal message should include the raw status: ' +
            job.Error_Message__c
        );
    }

    @IsTest
    static void testPollBudgetExhausted() {
        // Any mock — the poller should fail before making the callout
        Test.setMock(HttpCalloutMock.class, new MockQueuedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        // Submitted 7 hours ago — past the 6-hour wall-clock budget
        Quantum_Job__c job = makeJob('Running', DateTime.now().addHours(-7));
        insert job;

        Test.startTest();
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 5));
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c, External_Job_ID__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', job.Status__c);
        System.assert(
            job.Error_Message__c.contains('Polling budget exceeded'),
            'Should explain budget exhaustion: ' + job.Error_Message__c
        );
        System.assert(
            job.Error_Message__c.contains('Retrieve Results'),
            'Should point at the recovery path: ' + job.Error_Message__c
        );
        System.assertEquals(
            'job_test',
            job.External_Job_ID__c,
            'IBM job id must stay intact for manual recovery'
        );
    }

    @IsTest
    static void testPollBudgetNotExhaustedForFreshJob() {
        Test.setMock(HttpCalloutMock.class, new MockQueuedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        // High poll count but fresh Submitted_At__c — wall-clock budget
        // governs, not the poll count
        Quantum_Job__c job = makeJob('Running', DateTime.now());
        insert job;

        Test.startTest();
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 150));
        Test.stopTest();

        job = [
            SELECT Id, Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Queued',
            job.Status__c,
            'A fresh job must keep polling regardless of poll count'
        );
    }

    @IsTest
    static void testPollFallbackCapWhenSubmittedAtMissing() {
        Test.setMock(HttpCalloutMock.class, new MockQueuedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Running', null);
        insert job;

        Test.startTest();
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 100));
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', job.Status__c);
        System.assert(
            job.Error_Message__c.contains('maximum attempts'),
            'Should indicate the fallback poll cap: ' + job.Error_Message__c
        );
    }

    @IsTest
    static void testPollSkipsAlreadyFinalizedJob() {
        Test.setMock(HttpCalloutMock.class, new MockQueuedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        // Another actor (sweeper / manual retrieval) already completed it
        Quantum_Job__c job = makeJob('Completed', DateTime.now());
        insert job;

        Test.startTest();
        System.enqueueJob(new JobPoller(job.Id, 'job_test', 1));
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Poll_Count__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Completed',
            job.Status__c,
            'A finalized job must not be touched'
        );
        System.assertEquals(
            0,
            job.Poll_Count__c,
            'No poll should be recorded on a finalized job'
        );
    }

    @IsTest
    static void testPollCompletedEstimatorJob() {
        Test.setMock(HttpCalloutMock.class, new MockEstimatorCompletedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        // Create backend record
        Quantum_Provider__c provider = new Quantum_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        Quantum_Backend__c backend = new Quantum_Backend__c(
            Name = 'test_backend',
            Backend_Key__c = 'ibm:test_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 127
        );
        insert backend;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_est',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 4096,
            Num_Qubits__c = 2,
            Program_Id__c = 'estimator',
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_est', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Completed', job.Status__c);
        System.assert(
            job.Validation_Results__c.contains('chshSValue'),
            'Should contain CHSH S-value in validation results'
        );

        // Backend should be updated with verification data
        backend = [
            SELECT CHSH_S_Value__c, CHSH_Verified_At__c
            FROM Quantum_Backend__c
            WHERE Id = :backend.Id
        ];
        System.assertEquals(
            2.61,
            backend.CHSH_S_Value__c,
            'Backend CHSH S-value should be updated'
        );
        System.assertNotEquals(
            null,
            backend.CHSH_Verified_At__c,
            'Backend should have verification timestamp'
        );
    }

    @IsTest
    static void testPollCompletedBellTestJob() {
        Test.setMock(HttpCalloutMock.class, new MockCompletedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = makeJob('Submitted', DateTime.now());
        job.Shots__c = 8;
        job.Use_Bell_Test__c = true;
        insert job;

        Test.startTest();
        JobPoller poller = new JobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Completed', job.Status__c);

        // Certificate should exist with CHSH value
        List<Fairness_Certificate__c> certs = [
            SELECT Id, CHSH_S_Value__c, Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :job.Id
        ];
        System.assertEquals(1, certs.size(), 'Should create a certificate');
        System.assert(
            certs[0].Validation_Results__c.contains('chshSValue'),
            'Validation results should contain CHSH S-value'
        );
    }

    @IsTest
    static void testCalculateDelayMinutes() {
        // First 5 polls: 1 minute apart
        System.assertEquals(1, JobPoller.calculateDelayMinutes(0));
        System.assertEquals(1, JobPoller.calculateDelayMinutes(4));
        // Then the interval stretches
        System.assertEquals(2, JobPoller.calculateDelayMinutes(5));
        System.assertEquals(3, JobPoller.calculateDelayMinutes(6));
        System.assertEquals(5, JobPoller.calculateDelayMinutes(7));
        System.assertEquals(7, JobPoller.calculateDelayMinutes(8));
        // Capped at 10 minutes
        System.assertEquals(10, JobPoller.calculateDelayMinutes(9));
        System.assertEquals(10, JobPoller.calculateDelayMinutes(50));
    }

    @IsTest
    static void testIsTransientErrorClassification() {
        System.assertEquals(
            true,
            JobPoller.isTransientError(
                new System.CalloutException('Read timed out')
            ),
            'CalloutException is transient'
        );
        System.assertEquals(
            true,
            JobPoller.isTransientError(
                new QuantumException('Failed to get job status: 503')
            ),
            '5xx is transient'
        );
        System.assertEquals(
            true,
            JobPoller.isTransientError(
                new QuantumException('Failed to get job status: 429')
            ),
            '429 is transient'
        );
        System.assertEquals(
            true,
            JobPoller.isTransientError(
                new QuantumException(
                    'IBM IAM token exchange failed: 400 bad key'
                )
            ),
            'IAM exchange failures are transient'
        );
        System.assertEquals(
            true,
            JobPoller.isTransientError(
                new QuantumException('Request timeout while contacting IBM')
            ),
            'Timeout signatures are transient'
        );
        System.assertEquals(
            false,
            JobPoller.isTransientError(
                new QuantumException('Failed to get job status: 404')
            ),
            '404 is not transient'
        );
        System.assertEquals(
            false,
            JobPoller.isTransientError(
                new QuantumException('No results found in IBM response')
            ),
            'Parse/processing errors are not transient'
        );
    }

    @IsTest
    static void testAppendErrorKeepsNewestContent() {
        String appended = JobPoller.appendError('first', 'second');
        System.assertEquals('first\nsecond', appended);
        System.assertEquals('only', JobPoller.appendError(null, 'only'));
        System.assertEquals('only', JobPoller.appendError('', 'only'));

        String longExisting = 'x'.repeat(32760);
        String truncated = JobPoller.appendError(longExisting, 'NEWEST-NOTE');
        System.assertEquals(32768, truncated.length());
        System.assert(
            truncated.endsWith('NEWEST-NOTE'),
            'Truncation must keep the newest note'
        );
    }
}
