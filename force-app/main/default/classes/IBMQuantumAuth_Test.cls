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
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('not configured'),
                'Should indicate missing config'
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
        } catch (QRNGException e) {
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
}
