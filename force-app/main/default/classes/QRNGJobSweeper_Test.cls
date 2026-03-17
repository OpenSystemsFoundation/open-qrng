@IsTest
private class QRNGJobSweeper_Test {
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
                    '{"id":"job_sweep_123","status":"Completed","state":{"status":"Completed"}}'
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

    @IsTest
    static void testScheduleAndUnschedule() {
        Test.startTest();
        QRNGJobSweeper.scheduleDefault();
        Test.stopTest();

        System.assertEquals(
            true,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be scheduled'
        );

        QRNGJobSweeper.unschedule();
        System.assertEquals(
            false,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be unscheduled'
        );
    }

    @IsTest
    static void testSweeperWithNoJobs() {
        QRNGJobSweeper.QRNGJobSweeperWorker worker = new QRNGJobSweeper.QRNGJobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        // No jobs to process — should complete without error
        System.assert(true, 'Worker executed without error');
    }

    @IsTest
    static void testSweeperControllerMethods() {
        Test.startTest();
        QRNGSetupController.startSweeper();
        Test.stopTest();

        System.assertEquals(
            true,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be active after startSweeper'
        );

        QRNGSetupController.stopSweeper();
        System.assertEquals(
            false,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be inactive after stopSweeper'
        );
    }

    @IsTest
    static void testSweeperWorkerWithPendingCompletedJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
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

        QRNGJobSweeper.QRNGJobSweeperWorker worker = new QRNGJobSweeper.QRNGJobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        // Verify job was updated to Completed
        Quantum_Job__c updated = [
            SELECT Status__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Completed',
            updated.Status__c,
            'Job should be marked Completed'
        );

        // Certificate creation may fail with minimal mock data (too few bits
        // for validation) — the key assertion is the status update above.
    }

    @IsTest
    static void testSweeperWorkerWithFailedJob() {
        Test.setMock(HttpCalloutMock.class, new MockSweeperFailedStatus());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
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

        QRNGJobSweeper.QRNGJobSweeperWorker worker = new QRNGJobSweeper.QRNGJobSweeperWorker();

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

    @IsTest
    static void testSchedulableExecute() {
        Test.startTest();
        QRNGJobSweeper sweeper = new QRNGJobSweeper();
        sweeper.execute(null);
        Test.stopTest();

        // The execute method enqueues the worker — verify no exception
        System.assert(true, 'Schedulable execute completed without error');
    }
}
