/**
 * Handles IBM Quantum authentication via IAM token exchange.
 * Reads API key from QRNG_Settings__c custom setting.
 * Caches bearer token in static variable with 50-minute TTL.
 *
 * Governor limits: 1 callout for token exchange
 */
public with sharing class IBMQuantumAuth {

    private static final String IAM_TOKEN_URL = 'https://iam.cloud.ibm.com/identity/token';
    private static final Integer TOKEN_TTL_MINUTES = 50;

    // Transaction-scoped cache
    @TestVisible
    private static String cachedToken;
    @TestVisible
    private static DateTime tokenExpiry;

    /**
     * Get a valid IAM bearer token, refreshing if expired or not cached.
     */
    public static String getAccessToken() {
        if (cachedToken != null && tokenExpiry != null && DateTime.now() < tokenExpiry) {
            return cachedToken;
        }

        String apiKey = getApiKey();
        if (String.isBlank(apiKey)) {
            throw new QRNGException('IBM API Key not configured. Please set it in QRNG Settings (Custom Setting).');
        }

        return exchangeForToken(apiKey);
    }

    /**
     * Test the API key by attempting token exchange
     */
    public static Boolean testApiKey() {
        try {
            String token = getAccessToken();
            return String.isNotBlank(token);
        } catch (Exception e) {
            return false;
        }
    }

    @TestVisible
    private static String getApiKey() {
        QRNG_Settings__c settings = QRNG_Settings__c.getInstance();
        return settings != null ? settings.IBM_API_Key__c : null;
    }

    private static String exchangeForToken(String apiKey) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(IAM_TOKEN_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=' + EncodingUtil.urlEncode(apiKey, 'UTF-8'));
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QRNGException('IBM IAM token exchange failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        cachedToken = (String) responseMap.get('access_token');
        tokenExpiry = DateTime.now().addMinutes(TOKEN_TTL_MINUTES);

        return cachedToken;
    }

    /**
     * Clear the cached token (for testing or forced refresh)
     */
    public static void clearCache() {
        cachedToken = null;
        tokenExpiry = null;
    }
}
