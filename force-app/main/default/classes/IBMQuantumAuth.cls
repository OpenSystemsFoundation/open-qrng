/**
 * Handles IBM Quantum authentication via IAM token exchange.
 * Reads API key from Quantum_Settings__c custom setting.
 *
 * Token caching (bearer token ONLY — the API key itself is never cached
 * or logged):
 *   1. Transaction-scoped static — intra-transaction fast path.
 *   2. Platform Cache (Org partition 'local.QuantumFair', 50-minute TTL)
 *      — survives across transactions so the raw key is not re-exchanged
 *      on every poll. If Platform Cache or the partition is unavailable
 *      (no capacity allocated, partition not deployed, test context),
 *      all cache operations degrade gracefully to the static-only path.
 *
 * Governor limits: 1 callout for token exchange
 */
public with sharing class IBMQuantumAuth {
    private static final String IAM_TOKEN_URL = 'https://iam.cloud.ibm.com/identity/token';
    private static final Integer TOKEN_TTL_MINUTES = 50;
    private static final String CACHE_PARTITION = 'local.QuantumFair';
    private static final String CACHE_KEY_TOKEN = 'ibmBearerToken';
    // Platform Cache TTL: 50 minutes (IAM tokens live 60; keep a margin)
    private static final Integer CACHE_TTL_SECONDS = 3000;

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

        // Cross-transaction fast path: Platform Cache (graceful fallback)
        String platformCachedToken = getTokenFromPlatformCache();
        if (String.isNotBlank(platformCachedToken)) {
            cachedToken = platformCachedToken;
            tokenExpiry = DateTime.now().addMinutes(TOKEN_TTL_MINUTES);
            return cachedToken;
        }

        String apiKey = getApiKey();
        if (String.isBlank(apiKey)) {
            throw new QuantumException(
                'IBM API Key not configured. Set it in the QuantumFair Setup tab.'
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
        Quantum_Settings__c settings = Quantum_Settings__c.getInstance();
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
            throw new QuantumException(
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

        // Best-effort cross-transaction cache (bearer token only)
        putTokenInPlatformCache(cachedToken);

        return cachedToken;
    }

    /**
     * Read the bearer token from Platform Cache. Returns null when the
     * partition/Platform Cache is unavailable — never throws.
     */
    private static String getTokenFromPlatformCache() {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(
                CACHE_PARTITION
            );
            Object value = partition.get(CACHE_KEY_TOKEN);
            return value instanceof String ? (String) value : null;
        } catch (Exception e) {
            // Partition not deployed / no capacity — fall back to statics
            return null;
        }
    }

    /**
     * Store the bearer token in Platform Cache with a 50-minute TTL.
     * Best effort — never throws. The API key is NEVER cached.
     */
    private static void putTokenInPlatformCache(String token) {
        if (String.isBlank(token)) {
            return;
        }
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(
                CACHE_PARTITION
            );
            partition.put(CACHE_KEY_TOKEN, token, CACHE_TTL_SECONDS);
        } catch (Exception e) {
            // Platform Cache unavailable — the static fast path still works
        }
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
            throw new QuantumException(
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
     * Clear the cached token (for testing or forced refresh).
     * Clears both the transaction-scoped static and the Platform Cache
     * entry (best effort).
     */
    public static void clearCache() {
        cachedToken = null;
        tokenExpiry = null;
        try {
            Cache.Org.getPartition(CACHE_PARTITION).remove(CACHE_KEY_TOKEN);
        } catch (Exception e) {
            // Platform Cache unavailable — nothing to clear
        }
    }
}
