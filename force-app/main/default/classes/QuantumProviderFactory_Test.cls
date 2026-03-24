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
        } catch (QuantumException e) {
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
        } catch (QuantumException e) {
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
        } catch (QuantumException e) {
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

    @IsTest
    static void testGetActiveProviderDefault() {
        // No Quantum_Provider__c records — should default to IBM
        QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
        System.assertNotEquals(null, provider);
        System.assertEquals('ibm', provider.getProviderName());
    }

    @IsTest
    static void testGetActiveProviderFromRecord() {
        Quantum_Provider__c p = new Quantum_Provider__c(
            Name = 'IBM Quantum',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert p;

        QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
        System.assertEquals('ibm', provider.getProviderName());
    }

    @IsTest
    static void testIsSupported() {
        System.assertEquals(true, QuantumProviderFactory.isSupported('ibm'));
        System.assertEquals(true, QuantumProviderFactory.isSupported('IBM'));
        System.assertEquals(
            false,
            QuantumProviderFactory.isSupported('nonexistent')
        );
        System.assertEquals(false, QuantumProviderFactory.isSupported(null));
        System.assertEquals(false, QuantumProviderFactory.isSupported(''));
    }

    @IsTest
    static void testGetProviderWithWhitespace() {
        QuantumProvider provider = QuantumProviderFactory.getProvider(
            '  ibm  '
        );
        System.assertEquals('ibm', provider.getProviderName());
    }
}
