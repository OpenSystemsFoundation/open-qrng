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
        // Raw results should be binary, not hex
        System.assert(
            !job.Raw_Results__c.contains('0x'),
            'Raw results should be binary, not hex: ' +
            job.Raw_Results__c.left(40)
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
    static void testExtractQueueTimeMsWithTimestamps() {
        Map<String, Object> statusResponse = new Map<String, Object>{
            'status' => 'Completed',
            'timestamps' => new Map<String, Object>{
                'created' => '2026-03-17T10:00:00Z',
                'running' => '2026-03-17T10:00:12Z',
                'completed' => '2026-03-17T10:00:15Z'
            }
        };
        Decimal queueMs = QRNGJobPoller.extractQueueTimeMs(statusResponse);
        System.assertEquals(12000, queueMs, 'Queue time should be 12000ms');
    }

    @IsTest
    static void testExtractQueueTimeMsNoTimestamps() {
        Map<String, Object> statusResponse = new Map<String, Object>{
            'status' => 'Completed'
        };
        Decimal queueMs = QRNGJobPoller.extractQueueTimeMs(statusResponse);
        System.assertEquals(
            null,
            queueMs,
            'Should return null when no timestamps'
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
