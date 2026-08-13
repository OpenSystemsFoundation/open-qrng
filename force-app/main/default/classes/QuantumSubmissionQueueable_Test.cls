@IsTest
private class QuantumSubmissionQueueable_Test {
    private class MockIBMApi implements HttpCalloutMock {
        // Instance state: statics reset between the test transaction and
        // the async queueable transaction, but the registered mock
        // instance is reused across both.
        private Boolean failSubmission = false;

        private MockIBMApi withFailingSubmission() {
            this.failSubmission = true;
            return this;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            res.setStatusCode(200);
            if (endpoint.contains('iam.cloud.ibm.com')) {
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (endpoint.contains('/properties')) {
                res.setBody('{"qubits":[]}');
            } else if (endpoint.contains('/configuration')) {
                res.setBody(
                    '{"coupling_map":[[0,1],[2,3],[4,5],[6,7],[8,9],[10,11]]}'
                );
            } else if (endpoint.endsWith('/v1/backends')) {
                res.setBody(
                    '{"devices":[' +
                        '{"name":"busy_backend","status":"online","is_simulator":false,"queue_length":50},' +
                        '{"name":"idle_backend","status":"online","is_simulator":false,"queue_length":2}' +
                        ']}'
                );
            } else if (endpoint.endsWith('/v1/jobs')) {
                if (this.failSubmission) {
                    res.setStatusCode(500);
                    res.setBody('{"errors":[{"message":"backend offline"}]}');
                } else {
                    res.setBody('{"id":"ibm_queue_test"}');
                }
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    private static void setupSettings() {
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test',
            IBM_API_Key__c = 'test-api-key'
        );
        upsert s;
    }

    private static Quantum_Job__c insertPendingJob(String backend) {
        QuantumRandomAssignment.AssignmentRequestData data = new QuantumRandomAssignment.AssignmentRequestData();
        data.recordIds = new List<String>{ '001000000000001' };
        data.assigneeIds = new List<String>{ '005000000000001' };
        data.assignmentType = 'Uniform';
        data.purpose = 'Queueable test';
        data.useBellTest = false;
        data.backend = backend;
        data.numQubits = 4;
        data.shots = 128;

        Quantum_Job__c job = new Quantum_Job__c(
            Status__c = 'Pending',
            Backend__c = backend,
            Shots__c = 128,
            Num_Qubits__c = 4,
            Purpose__c = 'Queueable test',
            Use_Bell_Test__c = false,
            Job_Type__c = 'Quantum',
            Provider__c = 'ibm',
            Requested_By__c = UserInfo.getUserId(),
            Submitted_At__c = DateTime.now(),
            Assignment_Type__c = 'Uniform',
            Assignment_Request__c = JSON.serialize(data)
        );
        insert job;
        return job;
    }

    @IsTest
    static void testSubmitsPendingJob() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();
        Quantum_Job__c job = insertPendingJob('test_backend');

        Test.startTest();
        System.enqueueJob(
            new QuantumSubmissionQueueable(new List<Id>{ job.Id })
        );
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, External_Job_ID__c, Circuit_QASM__c, Backend__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Submitted', updated.Status__c);
        System.assertEquals('ibm_queue_test', updated.External_Job_ID__c);
        System.assertEquals('test_backend', updated.Backend__c);
        System.assert(
            updated.Circuit_QASM__c.contains('OPENQASM'),
            'Circuit should be persisted on the job'
        );
    }

    @IsTest
    static void testResolvesLeastBusyBackendWhenBlank() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();
        Quantum_Job__c job = insertPendingJob(null);

        Test.startTest();
        System.enqueueJob(
            new QuantumSubmissionQueueable(new List<Id>{ job.Id })
        );
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Backend__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Submitted', updated.Status__c);
        System.assertEquals(
            'idle_backend',
            updated.Backend__c,
            'Should pick the backend with the lowest queue'
        );
    }

    @IsTest
    static void testSubmissionFailureMarksJobFailed() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockIBMApi().withFailingSubmission()
        );
        setupSettings();
        Quantum_Job__c job = insertPendingJob('test_backend');

        Test.startTest();
        System.enqueueJob(
            new QuantumSubmissionQueueable(new List<Id>{ job.Id })
        );
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Error_Message__c, Completed_At__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', updated.Status__c);
        System.assert(
            updated.Error_Message__c.contains('Job submission failed'),
            'Should record the failure: ' + updated.Error_Message__c
        );
        System.assertNotEquals(null, updated.Completed_At__c);
    }

    @IsTest
    static void testSkipsJobNoLongerPending() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();
        Quantum_Job__c job = insertPendingJob('test_backend');
        job.Status__c = 'Failed';
        job.Error_Message__c = 'Swept by JobSweeper';
        update job;

        Test.startTest();
        System.enqueueJob(
            new QuantumSubmissionQueueable(new List<Id>{ job.Id })
        );
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, External_Job_ID__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Failed', updated.Status__c);
        System.assertEquals(null, updated.External_Job_ID__c);
        System.assertEquals('Swept by JobSweeper', updated.Error_Message__c);
    }

    @IsTest
    static void testBellTestCircuitPath() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();
        Quantum_Job__c job = insertPendingJob('test_backend');
        job.Use_Bell_Test__c = true;
        job.Num_Qubits__c = 8;
        update job;

        Test.startTest();
        System.enqueueJob(
            new QuantumSubmissionQueueable(new List<Id>{ job.Id })
        );
        Test.stopTest();

        Quantum_Job__c updated = [
            SELECT Status__c, Circuit_QASM__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Submitted', updated.Status__c);
        System.assert(
            updated.Circuit_QASM__c.contains('OPENQASM'),
            'Bell-test circuit should be persisted'
        );
    }

    @IsTest
    static void testChainProcessesOneJobPerExecution() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();
        Quantum_Job__c job1 = insertPendingJob('test_backend');
        Quantum_Job__c job2 = insertPendingJob('test_backend');

        Test.startTest();
        System.enqueueJob(
            new QuantumSubmissionQueueable(new List<Id>{ job1.Id, job2.Id })
        );
        Test.stopTest();

        // One job per execution; the chain to the next job is suppressed
        // in test context, so job2 stays Pending
        System.assertEquals(
            'Submitted',
            [SELECT Status__c FROM Quantum_Job__c WHERE Id = :job1.Id].Status__c
        );
        System.assertEquals(
            'Pending',
            [SELECT Status__c FROM Quantum_Job__c WHERE Id = :job2.Id].Status__c
        );
    }

    @IsTest
    static void testEmptyJobListIsNoOp() {
        Test.startTest();
        System.enqueueJob(new QuantumSubmissionQueueable(new List<Id>()));
        System.enqueueJob(new QuantumSubmissionQueueable(null));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Quantum_Job__c]);
    }
}
