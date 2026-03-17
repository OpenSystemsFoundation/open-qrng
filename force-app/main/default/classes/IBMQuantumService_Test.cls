@IsTest
private class IBMQuantumService_Test {
    private class MockSubmitSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token-abc","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs') &&
                req.getMethod() == 'POST'
            ) {
                res.setStatusCode(200);
                res.setBody('{"id":"job_abc123","backend":"test_backend"}');
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
                    '{"id":"job_abc123","status":"Completed","state":{"status":"Completed"}}'
                );
            } else if (req.getEndpoint().contains('/v1/backends')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"devices":[{"name":"test_backend","status":"online","qubits":156}]}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testSubmitJob() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        // Pre-set auth token to avoid IAM callout during submit
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        String qasm = QRNGCircuitBuilder.buildStandardCircuit(4);

        Test.startTest();
        Id jobId = IBMQuantumService.submitJob(
            qasm,
            'test_backend',
            1024,
            'Test purpose',
            false,
            4
        );
        Test.stopTest();

        Quantum_Job__c job = [
            SELECT Id, External_Job_ID__c, Status__c, Backend__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
        ];
        System.assertEquals('job_abc123', job.External_Job_ID__c);
        System.assertEquals('test_backend', job.Backend__c);
    }

    @IsTest
    static void testGetJobStatus() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Test.startTest();
        Map<String, Object> status = IBMQuantumService.getJobStatus(
            'job_abc123'
        );
        Test.stopTest();

        System.assertNotEquals(null, status);
    }

    @IsTest
    static void testGetJobResults() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Test.startTest();
        String results = IBMQuantumService.getJobResults('job_abc123');
        Test.stopTest();

        System.assert(
            results.contains('samples'),
            'Results should contain samples'
        );
    }

    @IsTest
    static void testGetBackends() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Test.startTest();
        String backends = IBMQuantumService.getBackends();
        Test.stopTest();

        System.assert(
            backends.contains('test_backend'),
            'Should contain backend info'
        );
    }
}
