@IsTest
private class IBMQuantumAuth_Test {
    @IsTest
    static void testGetAccessTokenNoApiKey() {
        try {
            IBMQuantumAuth.getAccessToken();
            System.assert(
                false,
                'Should throw exception when no API key configured'
            );
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('not configured'),
                'Should indicate missing config'
            );
            System.assert(
                e.getMessage().contains('QuantumFair Setup tab'),
                'Should point at the Setup tab (not the raw custom setting): ' +
                e.getMessage()
            );
        }
    }

    @IsTest
    static void testGetAccessTokenCached() {
        // Simulate a cached token
        IBMQuantumAuth.cachedToken = 'test-token-123';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        String token = IBMQuantumAuth.getAccessToken();
        System.assertEquals(
            'test-token-123',
            token,
            'Should return cached token'
        );
    }

    @IsTest
    static void testGetAccessTokenExpired() {
        // Set an expired token - should try to refresh (and fail without API key)
        IBMQuantumAuth.cachedToken = 'expired-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(-5);

        try {
            IBMQuantumAuth.getAccessToken();
            System.assert(
                false,
                'Should throw when refreshing with no API key'
            );
        } catch (QuantumException e) {
            System.assert(true, 'Exception thrown as expected');
        }
    }

    @IsTest
    static void testClearCache() {
        IBMQuantumAuth.cachedToken = 'some-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now();

        IBMQuantumAuth.clearCache();

        System.assertEquals(null, IBMQuantumAuth.cachedToken);
        System.assertEquals(null, IBMQuantumAuth.tokenExpiry);
    }

    @IsTest
    static void testTestApiKeyFalse() {
        Boolean result = IBMQuantumAuth.testApiKey();
        System.assertEquals(
            false,
            result,
            'Should return false when no API key configured'
        );
    }

    private class MockDiscoverInstances implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token-disc","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('resource-controller.cloud.ibm.com')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"resources":[' +
                        '{"name":"instance-1","crn":"crn:v1:instance1","state":"active"},' +
                        '{"name":"instance-2","crn":"crn:v1:instance2","state":"active"}' +
                        ']}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testDiscoverInstances() {
        Test.setMock(HttpCalloutMock.class, new MockDiscoverInstances());
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key'
        );
        upsert s;

        Test.startTest();
        List<Map<String, String>> instances = IBMQuantumAuth.discoverInstances();
        Test.stopTest();

        System.assertEquals(2, instances.size(), 'Should find two instances');
        System.assertEquals(
            'instance-1',
            instances[0].get('name'),
            'First instance name should match'
        );
        System.assertEquals(
            'crn:v1:instance1',
            instances[0].get('crn'),
            'First instance CRN should match'
        );
        System.assertEquals(
            'active',
            instances[1].get('state'),
            'Second instance state should be active'
        );
    }

    private class MockTokenExchange implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"access_token":"fresh-token-xyz","token_type":"Bearer","expires_in":3600}'
            );
            return res;
        }
    }

    @IsTest
    static void testGetAccessTokenViaExchange() {
        Test.setMock(HttpCalloutMock.class, new MockTokenExchange());
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key'
        );
        upsert s;

        // Ensure no cached token
        IBMQuantumAuth.clearCache();

        Test.startTest();
        String token = IBMQuantumAuth.getAccessToken();
        Test.stopTest();

        System.assertEquals(
            'fresh-token-xyz',
            token,
            'Should return token from IAM exchange'
        );
    }

    /**
     * Counting mock so tests can assert how many token exchanges happened.
     */
    private class MockCountingTokenExchange implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            calloutCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"access_token":"counted-token","token_type":"Bearer","expires_in":3600}'
            );
            return res;
        }
    }
    private static Integer calloutCount = 0;

    @IsTest
    static void testPlatformCacheUnavailableGracefulFallback() {
        // No 'QuantumFair' Platform Cache partition exists in the test org,
        // so every Cache.Org call throws internally. Token acquisition must
        // still work end-to-end via the transaction-static fallback.
        Test.setMock(HttpCalloutMock.class, new MockCountingTokenExchange());
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key'
        );
        upsert s;
        IBMQuantumAuth.clearCache();

        Test.startTest();
        String first = IBMQuantumAuth.getAccessToken();
        String second = IBMQuantumAuth.getAccessToken();
        Test.stopTest();

        System.assertEquals(
            'counted-token',
            first,
            'Token exchange must succeed even without Platform Cache'
        );
        System.assertEquals(
            'counted-token',
            second,
            'Second call should hit the transaction-static cache'
        );
        System.assertEquals(
            1,
            calloutCount,
            'The static fast path must prevent a second exchange in-transaction'
        );
    }

    @IsTest
    static void testClearCacheWithoutPlatformCacheDoesNotThrow() {
        IBMQuantumAuth.cachedToken = 'some-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(10);

        // Must not throw even though the cache partition is unavailable
        IBMQuantumAuth.clearCache();

        System.assertEquals(null, IBMQuantumAuth.cachedToken);
        System.assertEquals(null, IBMQuantumAuth.tokenExpiry);
    }

    @IsTest
    static void testTestApiKeyTrue() {
        Test.setMock(HttpCalloutMock.class, new MockTokenExchange());
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key'
        );
        upsert s;
        IBMQuantumAuth.clearCache();

        Test.startTest();
        Boolean result = IBMQuantumAuth.testApiKey();
        Test.stopTest();

        System.assertEquals(
            true,
            result,
            'Should return true when API key is valid'
        );
    }
}
