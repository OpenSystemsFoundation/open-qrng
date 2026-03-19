@IsTest
private class QRNGJobPoller_Test {
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

    @IsTest
    static void testPollCompletedJob() {
        Test.setMock(HttpCalloutMock.class, new MockCompletedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 8,
            Num_Qubits__c = 8,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 0);
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

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 0);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Poll_Count__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Queued', job.Status__c);
    }

    @IsTest
    static void testPollRunningJob() {
        Test.setMock(HttpCalloutMock.class, new MockRunningJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 0);
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

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 0);
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

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 0);
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
    static void testPollExceededMaxPolls() {
        // Use any mock — the poller should fail before making the callout
        Test.setMock(HttpCalloutMock.class, new MockQueuedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Running',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        // Pass pollCount = 100 (MAX_POLLS) to trigger the limit
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 100);
        System.enqueueJob(poller);
        Test.stopTest();

        job = [
            SELECT Id, Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', job.Status__c);
        System.assert(
            job.Error_Message__c.contains('maximum attempts'),
            'Should indicate max polls exceeded'
        );
    }

    @IsTest
    static void testPollCompletedEstimatorJob() {
        Test.setMock(HttpCalloutMock.class, new MockEstimatorCompletedJob());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        // Create backend record
        QRNG_Provider__c provider = new QRNG_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        QRNG_Backend__c backend = new QRNG_Backend__c(
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
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_est', 0);
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
            FROM QRNG_Backend__c
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

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_test',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 8,
            Num_Qubits__c = 8,
            Use_Bell_Test__c = true,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        QRNGJobPoller poller = new QRNGJobPoller(job.Id, 'job_test', 0);
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
    static void testCalculateDelay() {
        System.assertEquals(5, QRNGJobPoller.calculateDelay(0));
        System.assertEquals(10, QRNGJobPoller.calculateDelay(1));
        System.assertEquals(20, QRNGJobPoller.calculateDelay(2));
        System.assertEquals(40, QRNGJobPoller.calculateDelay(3));
        System.assertEquals(60, QRNGJobPoller.calculateDelay(4)); // capped
        System.assertEquals(60, QRNGJobPoller.calculateDelay(10)); // still capped
    }
}
