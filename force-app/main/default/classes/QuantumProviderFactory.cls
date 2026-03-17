/**
 * Factory for creating QuantumProvider instances by provider name.
 * Centralizes provider resolution so callers don't need to know
 * concrete implementation classes.
 *
 * Usage:
 *   QuantumProvider provider = QuantumProviderFactory.getProvider('ibm');
 *
 * Supported providers:
 *   - 'ibm' : IBM Quantum (via IBMQuantumService)
 *
 * Governor limits: 0 callouts, 0 SOQL, 0 DML (pure factory method)
 */
public with sharing class QuantumProviderFactory {
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
                'Unsupported quantum provider: ' + providerName +
                '. Supported providers: ' + String.join(new List<String>(PROVIDER_REGISTRY.keySet()), ', ')
            );
        }

        return (QuantumProvider) providerType.newInstance();
    }

    /**
     * List all registered provider names.
     * @return Set of supported provider keys
     */
    public static Set<String> getSupportedProviders() {
        return PROVIDER_REGISTRY.keySet();
    }
}
