/**
 * Factory for creating QuantumProvider instances by provider name.
 * Centralizes provider resolution so callers don't need to know
 * concrete implementation classes.
 *
 * Usage:
 *   QuantumProvider provider = QuantumProviderFactory.getProvider('ibm');
 *   QuantumProvider active   = QuantumProviderFactory.getActiveProvider();
 *
 * To add a new provider:
 *   1. Create a class implementing QuantumProvider (see PROVIDERS.md)
 *   2. Add an entry to PROVIDER_REGISTRY below
 *
 * Governor limits: 0 callouts, 0-1 SOQL (getActiveProvider reads settings)
 */
public with sharing class QuantumProviderFactory {
    @TestVisible
    private static final Map<String, System.Type> PROVIDER_REGISTRY = new Map<String, System.Type>{
        'ibm' => IBMQuantumProvider.class
    };

    /**
     * Get a QuantumProvider instance for the given provider name.
     * @param providerName  Case-insensitive provider key (e.g. 'ibm')
     * @return QuantumProvider implementation
     * @throws QRNGException if the provider name is not recognized
     */
    public static QuantumProvider getProvider(String providerName) {
        if (String.isBlank(providerName)) {
            throw new QRNGException('Provider name cannot be blank');
        }

        String key = providerName.toLowerCase().trim();
        System.Type providerType = PROVIDER_REGISTRY.get(key);

        if (providerType == null) {
            throw new QRNGException(
                'Unsupported quantum provider: ' +
                    providerName +
                    '. Supported providers: ' +
                    String.join(
                        new List<String>(PROVIDER_REGISTRY.keySet()),
                        ', '
                    )
            );
        }

        return (QuantumProvider) providerType.newInstance();
    }

    /**
     * Get the active QuantumProvider based on the org's QRNG_Provider__c records.
     * Falls back to IBM if no active provider is configured.
     * @return QuantumProvider for the first active provider
     */
    public static QuantumProvider getActiveProvider() {
        List<QRNG_Provider__c> activeProviders = [
            SELECT Provider_Key__c
            FROM QRNG_Provider__c
            WHERE Is_Active__c = TRUE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        if (!activeProviders.isEmpty()) {
            String key = activeProviders[0].Provider_Key__c;
            if (PROVIDER_REGISTRY.containsKey(key)) {
                return getProvider(key);
            }
        }

        // Default to IBM
        return getProvider('ibm');
    }

    /**
     * List all registered provider names.
     * @return Set of supported provider keys
     */
    public static Set<String> getSupportedProviders() {
        return PROVIDER_REGISTRY.keySet();
    }

    /**
     * Check whether a provider key is registered.
     */
    public static Boolean isSupported(String providerName) {
        if (String.isBlank(providerName)) {
            return false;
        }
        return PROVIDER_REGISTRY.containsKey(providerName.toLowerCase().trim());
    }
}
