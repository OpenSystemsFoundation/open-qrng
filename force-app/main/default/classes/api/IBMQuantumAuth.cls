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
        if (
            cachedToken != null &&
            tokenExpiry != null &&
            DateTime.now() < tokenExpiry
        ) {
            return cachedToken;
        }

        String apiKey = getApiKey();
        if (String.isBlank(apiKey)) {
            throw new QRNGException(
                'IBM API Key not configured. Please set it in QRNG Settings (Custom Setting).'
            );
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
        req.setBody(
            'grant_type=urn:ibm:params:oauth:grant-type:apikey&apikey=' +
            EncodingUtil.urlEncode(apiKey, 'UTF-8')
        );
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QRNGException(
                'IBM IAM token exchange failed: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        cachedToken = (String) responseMap.get('access_token');
        tokenExpiry = DateTime.now().addMinutes(TOKEN_TTL_MINUTES);

        return cachedToken;
    }

    /**
     * Discover IBM Quantum service instances and their CRNs.
     * Uses IBM Cloud Resource Controller API.
     * resource_id for Qiskit Runtime: b6049020-80f4-11eb-a0f7-e35ec9b4054f
     *
     * Governor limits: 1 callout
     */
    public static List<Map<String, String>> discoverInstances() {
        String token = getAccessToken();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://resource-controller.cloud.ibm.com/v2/resource_instances' +
            '?resource_id=b6049020-80f4-11eb-a0f7-e35ec9b4054f'
        );
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QRNGException(
                'Failed to discover IBM Quantum instances: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        List<Object> resources = (List<Object>) responseMap.get('resources');
        List<Map<String, String>> instances = new List<Map<String, String>>();

        if (resources != null) {
            for (Object resource : resources) {
                Map<String, Object> r = (Map<String, Object>) resource;
                Map<String, String> instance = new Map<String, String>();
                instance.put('name', (String) r.get('name'));
                instance.put('crn', (String) r.get('crn'));
                instance.put('state', (String) r.get('state'));
                instances.add(instance);
            }
        }

        return instances;
    }

    /**
     * Clear the cached token (for testing or forced refresh)
     */
    public static void clearCache() {
        cachedToken = null;
        tokenExpiry = null;
    }
}
