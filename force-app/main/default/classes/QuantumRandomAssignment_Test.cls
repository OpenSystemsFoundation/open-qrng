@IsTest
private class QuantumRandomAssignment_Test {
    private class MockIBMApi implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
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
            } else if (endpoint.endsWith('/v1/jobs')) {
                res.setBody('{"id":"job_flow_test","backend":"test_backend"}');
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
            Default_Backend__c = 'test_backend',
            IBM_API_Key__c = 'test-api-key'
        );
        upsert s;
    }

    private static QuantumRandomAssignment.AssignmentRequest buildUniformRequest(
        Integer suffix
    ) {
        QuantumRandomAssignment.AssignmentRequest req = new QuantumRandomAssignment.AssignmentRequest();
        req.recordIds = new List<String>{
            '00100000000000' + suffix,
            '00100000000001' + suffix
        };
        req.assigneeIds = new List<String>{
            '005000000000001',
            '005000000000002'
        };
        req.assignmentType = 'Uniform';
        req.purpose = 'Test assignment ' + suffix;
        req.numQubits = 4;
        return req;
    }

    @IsTest
    static void testInvocableActionQueuesJob() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();

        QuantumRandomAssignment.AssignmentRequest req = buildUniformRequest(1);

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{ req }
        );

        // Before the queueable runs: job exists in Pending with the full
        // request persisted — no callouts happened in this transaction
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].jobId);

        Quantum_Job__c pending = [
            SELECT
                Status__c,
                Assignment_Type__c,
                Assignment_Request__c,
                Num_Qubits__c,
                Shots__c
            FROM Quantum_Job__c
            WHERE Id = :results[0].jobId
        ];
        System.assertEquals('Pending', pending.Status__c);
        System.assertEquals('Uniform', pending.Assignment_Type__c);
        System.assertEquals(4, pending.Num_Qubits__c);
        System.assertNotEquals(null, pending.Assignment_Request__c);

        QuantumRandomAssignment.AssignmentRequestData data = (QuantumRandomAssignment.AssignmentRequestData) JSON.deserialize(
            pending.Assignment_Request__c,
            QuantumRandomAssignment.AssignmentRequestData.class
        );
        System.assertEquals(2, data.recordIds.size());
        System.assertEquals(2, data.assigneeIds.size());
        System.assertEquals('Uniform', data.assignmentType);
        System.assertEquals(1024, data.shots);
        Test.stopTest();

        // After Test.stopTest the queueable ran: job submitted to IBM
        Quantum_Job__c submitted = [
            SELECT Status__c, External_Job_ID__c
            FROM Quantum_Job__c
            WHERE Id = :results[0].jobId
        ];
        System.assertEquals('Submitted', submitted.Status__c);
        System.assertEquals('job_flow_test', submitted.External_Job_ID__c);
    }

    @IsTest
    static void testBulkInvocationQueuesAllRequests() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();

        List<QuantumRandomAssignment.AssignmentRequest> requests = new List<QuantumRandomAssignment.AssignmentRequest>();
        for (Integer i = 0; i < 5; i++) {
            requests.add(buildUniformRequest(i));
        }

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            requests
        );

        // All 5 requests must be queued — the old callout-in-loop design
        // failed every request after the first with uncommitted-work errors
        System.assertEquals(5, results.size());
        Set<Id> jobIds = new Set<Id>();
        for (QuantumRandomAssignment.AssignmentResult r : results) {
            System.assertEquals(true, r.success, 'err: ' + r.errorMessage);
            System.assertNotEquals(null, r.jobId);
            jobIds.add(r.jobId);
        }
        System.assertEquals(5, jobIds.size(), 'Each request gets its own job');

        System.assertEquals(
            5,
            [
                SELECT COUNT()
                FROM Quantum_Job__c
                WHERE Status__c = 'Pending' AND Id IN :jobIds
            ]
        );

        // Exactly one submission queueable coordinates all pending jobs
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE
                    JobType = 'Queueable'
                    AND ApexClass.Name = 'QuantumSubmissionQueueable'
            ]
        );
        Test.stopTest();
    }

    @IsTest
    static void testMixedBatchValidationFailureDoesNotBlockOthers() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        setupSettings();

        QuantumRandomAssignment.AssignmentRequest good = buildUniformRequest(1);
        QuantumRandomAssignment.AssignmentRequest bad = new QuantumRandomAssignment.AssignmentRequest();
        bad.recordIds = new List<String>{ '001000000000001' };
        bad.assignmentType = 'Uniform';
        bad.purpose = 'No assignees';
        // missing assigneeIds → invalid

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{ good, bad }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(false, results[1].success);
        System.assert(
            results[1].errorMessage.contains('Assignee IDs'),
            'Should explain the failure: ' + results[1].errorMessage
        );
        System.assertEquals(null, results[1].jobId);
    }

    @IsTest
    static void testOversizedConfigurationRejected() {
        setupSettings();

        // 1000 qubits x 1024 shots = 1,024,000 bits → 256,002 encoded chars,
        // which cannot be stored without truncation (limit 131,072)
        QuantumRandomAssignment.AssignmentRequest req = buildUniformRequest(1);
        req.numQubits = 1000;

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(
            results[0].errorMessage.contains('exceeding the storable maximum'),
            'Should explain size limit: ' + results[0].errorMessage
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Quantum_Job__c],
            'No job record should be created for a rejected configuration'
        );
    }

    @IsTest
    static void testWeightedRequestValidation() {
        setupSettings();

        QuantumRandomAssignment.AssignmentRequest req = buildUniformRequest(1);
        req.assignmentType = 'Weighted';
        req.weights = '70, 30';

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(
            true,
            results[0].success,
            'err: ' + results[0].errorMessage
        );

        Quantum_Job__c job = [
            SELECT Assignment_Request__c
            FROM Quantum_Job__c
            WHERE Id = :results[0].jobId
        ];
        QuantumRandomAssignment.AssignmentRequestData data = (QuantumRandomAssignment.AssignmentRequestData) JSON.deserialize(
            job.Assignment_Request__c,
            QuantumRandomAssignment.AssignmentRequestData.class
        );
        System.assertEquals(2, data.weights.size());
        System.assertEquals(70.0, data.weights[0]);
        System.assertEquals(30.0, data.weights[1]);
    }

    @IsTest
    static void testWeightedRequestBadWeightsRejected() {
        setupSettings();

        QuantumRandomAssignment.AssignmentRequest mismatch = buildUniformRequest(
            1
        );
        mismatch.assignmentType = 'Weighted';
        mismatch.weights = '70, 20, 10'; // 3 weights, 2 assignees

        QuantumRandomAssignment.AssignmentRequest invalid = buildUniformRequest(
            2
        );
        invalid.assignmentType = 'Weighted';
        invalid.weights = '70, abc';

        QuantumRandomAssignment.AssignmentRequest negative = buildUniformRequest(
            3
        );
        negative.assignmentType = 'Weighted';
        negative.weights = '70, -30';

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{
                mismatch,
                invalid,
                negative
            }
        );
        Test.stopTest();

        for (QuantumRandomAssignment.AssignmentResult r : results) {
            System.assertEquals(false, r.success);
            System.assertNotEquals(null, r.errorMessage);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Quantum_Job__c]);
    }

    @IsTest
    static void testSubsetRequestValidation() {
        setupSettings();

        QuantumRandomAssignment.AssignmentRequest missing = buildUniformRequest(
            1
        );
        missing.assignmentType = 'Subset';
        missing.sampleSize = null;

        QuantumRandomAssignment.AssignmentRequest tooLarge = buildUniformRequest(
            2
        );
        tooLarge.assignmentType = 'Subset';
        tooLarge.sampleSize = 99;

        QuantumRandomAssignment.AssignmentRequest valid = buildUniformRequest(
            3
        );
        valid.assignmentType = 'Subset';
        valid.sampleSize = 1;

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{
                missing,
                tooLarge,
                valid
            }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assertEquals(false, results[1].success);
        System.assertEquals(
            true,
            results[2].success,
            'err: ' + results[2].errorMessage
        );
    }

    @IsTest
    static void testUnknownAssignmentTypeRejected() {
        setupSettings();

        QuantumRandomAssignment.AssignmentRequest req = buildUniformRequest(1);
        req.assignmentType = 'Lottery';

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(
            results[0].errorMessage.contains('Unknown assignment type')
        );
    }
}
