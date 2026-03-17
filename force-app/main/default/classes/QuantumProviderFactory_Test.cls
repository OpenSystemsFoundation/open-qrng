@IsTest
private class QuantumProviderFactory_Test {
    @IsTest
    static void testGetIBMProvider() {
        QuantumProvider provider = QuantumProviderFactory.getProvider('ibm');
        System.assertNotEquals(null, provider, 'Should return IBM provider');
        System.assertEquals(
            'ibm',
            provider.getProviderName(),
            'Provider name should be ibm'
        );
    }

    @IsTest
    static void testGetProviderCaseInsensitive() {
        QuantumProvider provider = QuantumProviderFactory.getProvider('IBM');
        System.assertNotEquals(
            null,
            provider,
            'Should handle uppercase provider name'
        );
        System.assertEquals('ibm', provider.getProviderName());
    }

    @IsTest
    static void testGetProviderBlankThrows() {
        try {
            QuantumProviderFactory.getProvider('');
            System.assert(false, 'Should have thrown exception');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('blank'),
                'Error should mention blank: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testGetProviderNullThrows() {
        try {
            QuantumProviderFactory.getProvider(null);
            System.assert(false, 'Should have thrown exception');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('blank'),
                'Error should mention blank'
            );
        }
    }

    @IsTest
    static void testGetProviderUnsupportedThrows() {
        try {
            QuantumProviderFactory.getProvider('nonexistent');
            System.assert(false, 'Should have thrown exception');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('Unsupported'),
                'Error should mention unsupported: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testGetSupportedProviders() {
        Set<String> providers = QuantumProviderFactory.getSupportedProviders();
        System.assert(providers.contains('ibm'), 'Should contain ibm provider');
    }
}
