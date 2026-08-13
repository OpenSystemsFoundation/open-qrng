/**
 * Integration test for IBM Quantum API connectivity.
 *
 * Since Apex test methods cannot make real HTTP callouts,
 * this class always uses mocks to validate the connection code path.
 *
 * The REAL integration test (with live IBM API) runs as anonymous Apex
 * via scripts/apex/integration-test-connection.apex in CI only.
 *
 * This test class ensures the connection logic works correctly
 * regardless of whether an API key is configured.
 */
@IsTest
private class IBMQuantumConnection_IntTest {
    private class MockIBMSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"mock-token","token_type":"Bearer","expires_in":3600}'
                );
            } else if (req.getEndpoint().contains('/v1/backends')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"devices":[' +
                        '{"name":"test_backend","status":"online","qubits":156},' +
                        '{"name":"ibm_sherbrooke","status":"online","qubits":127}' +
                        ']}'
                );
            }
            return res;
        }
    }

    private class MockIBMAuthFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody(
                '{"errorCode":"BXNIM0415E","errorMessage":"Provided API key could not be found."}'
            );
            return res;
        }
    }

    @IsTest
    static void testConnectionSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockIBMSuccess());

        // Simulate having a configured API key
        Quantum_Settings__c settings = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'mock-api-key',
            Default_Backend__c = 'test_backend'
        );
        upsert settings;

        IBMQuantumAuth.clearCache();

        Test.startTest();
        Map<String, Object> result = SetupController.testConnection();
        Test.stopTest();

        System.assertEquals(
            true,
            result.get('connected'),
            'Connection should succeed with valid mock'
        );
        System.assertEquals('Connected to ibm', result.get('message'));
    }

    @IsTest
    static void testConnectionFailsWithBadKey() {
        Test.setMock(HttpCalloutMock.class, new MockIBMAuthFailure());

        Quantum_Settings__c settings = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'bad-key'
        );
        upsert settings;

        IBMQuantumAuth.clearCache();

        Test.startTest();
        Map<String, Object> result = SetupController.testConnection();
        Test.stopTest();

        System.assertEquals(
            false,
            result.get('connected'),
            'Connection should fail with bad key'
        );
    }

    @IsTest
    static void testConnectionFailsWithNoKey() {
        // No settings configured — API key is blank
        IBMQuantumAuth.clearCache();

        Test.startTest();
        Map<String, Object> result = SetupController.testConnection();
        Test.stopTest();

        System.assertEquals(
            false,
            result.get('connected'),
            'Connection should fail without API key'
        );
    }

    @IsTest
    static void testListBackendsSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockIBMSuccess());

        Quantum_Settings__c settings = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'mock-api-key'
        );
        upsert settings;

        IBMQuantumAuth.clearCache();

        // getAvailableBackends is gated on QuantumFair_Administer (B6)
        SetupController.adminOverrideForTests = true;
        Test.startTest();
        List<Map<String, Object>> backends = SetupController.getAvailableBackends();
        Test.stopTest();

        System.assertEquals(
            2,
            backends.size(),
            'Should return 2 mock backends'
        );
        System.assertEquals('test_backend', backends[0].get('name'));
        System.assertEquals('ibm_sherbrooke', backends[1].get('name'));
    }
}
