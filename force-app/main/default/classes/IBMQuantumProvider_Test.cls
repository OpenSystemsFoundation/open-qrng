@IsTest
private class IBMQuantumProvider_Test {
    private class MockIBMCallouts implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token-abc","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('resource-controller.cloud.ibm.com')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"resources":[{"name":"test-instance","crn":"crn:v1:bluemix:public:quantum-computing:us-east:a/123:456::","state":"active"}]}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs') &&
                req.getMethod() == 'POST'
            ) {
                res.setStatusCode(200);
                res.setBody('{"id":"job_prov_123","backend":"test_backend"}');
            } else if (
                req.getEndpoint().contains('/v1/jobs/') &&
                req.getEndpoint().contains('/results')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"results":[{"data":{"meas":{"samples":["0110","1001"]}}}]}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_prov_123","status":"Completed","state":{"status":"Completed"}}'
                );
            } else if (
                req.getEndpoint().contains('/v1/backends/') &&
                req.getEndpoint().contains('/properties')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"qubits":[[{"name":"T1","value":200.5}]],"gates":[],"last_update_date":"2026-03-15T10:00:00Z"}'
                );
            } else if (req.getEndpoint().contains('/v1/backends')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"devices":[{"name":"ibm_test","status":"online","qubits":127}]}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testGetProviderName() {
        IBMQuantumProvider provider = new IBMQuantumProvider();
        System.assertEquals(
            'ibm',
            provider.getProviderName(),
            'Provider name should be ibm'
        );
    }

    @IsTest
    static void testAuthenticate() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        // Set up settings with API key for IAM exchange
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        String token = provider.authenticate();
        Test.stopTest();

        System.assertEquals(
            'test-token-abc',
            token,
            'Should return the IAM access token'
        );
    }

    @IsTest
    static void testSubmitJob() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        String jobId = provider.submitJob(
            'OPENQASM 3.0; include "stdgates.inc"; qubit[2] q; h q[0]; measure q;',
            'test_backend',
            1024
        );
        Test.stopTest();

        System.assertEquals(
            'job_prov_123',
            jobId,
            'Should return the external job ID'
        );
    }

    @IsTest
    static void testGetJobStatus() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        Map<String, Object> status = provider.getJobStatus('job_prov_123');
        Test.stopTest();

        System.assertNotEquals(null, status, 'Status should not be null');
    }

    @IsTest
    static void testGetJobResults() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        String results = provider.getJobResults('job_prov_123');
        Test.stopTest();

        System.assert(
            results.contains('samples'),
            'Results should contain samples'
        );
    }

    @IsTest
    static void testListBackends() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        List<Map<String, Object>> backends = provider.listBackends();
        Test.stopTest();

        System.assertEquals(1, backends.size(), 'Should return one backend');
        System.assertEquals(
            'ibm_test',
            backends[0].get('name'),
            'Backend name should match'
        );
    }

    @IsTest
    static void testGetBackendProperties() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        Map<String, Object> props = provider.getBackendProperties(
            'test_backend'
        );
        Test.stopTest();

        System.assertNotEquals(null, props, 'Properties should not be null');
        System.assert(props.containsKey('qubits'), 'Should contain qubits key');
    }

    @IsTest
    static void testTestConnection() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        Boolean connected = provider.testConnection();
        Test.stopTest();

        System.assertEquals(true, connected, 'Should connect successfully');
    }

    @IsTest
    static void testDiscoverInstances() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        IBMQuantumProvider provider = new IBMQuantumProvider();

        Test.startTest();
        List<Map<String, String>> instances = provider.discoverInstances();
        Test.stopTest();

        System.assertNotEquals(null, instances, 'Instances should not be null');
    }

    @IsTest
    static void testBuildPauliString() {
        // 4-qubit system, ZZ on qubits 1 and 3
        String zz = IBMQuantumProvider.buildPauliString(4, 1, 3);
        System.assertEquals(4, zz.length());
        // qubit 3 is at position 0 (reversed), qubit 1 is at position 2
        System.assertEquals('Z', zz.substring(0, 1));
        System.assertEquals('Z', zz.substring(2, 3));
        System.assertEquals('I', zz.substring(1, 2));
        System.assertEquals('I', zz.substring(3, 4));
    }
}
