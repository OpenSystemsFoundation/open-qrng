/**
 * Inserts or updates the IBM Quantum API key in QRNG_Settings__c.
 * Used by CI to inject the secret before running integration tests.
 *
 * The API key is passed via environment variable IBM_QUANTUM_API_KEY
 * and injected into this script by the CI workflow before execution.
 *
 * Usage in CI:
 *   sed "s|__IBM_API_KEY__|${IBM_QUANTUM_API_KEY}|" scripts/apex/setup-api-key.apex | sf apex run --file /dev/stdin --target-org ci-test
 */

String apiKey = '__IBM_API_KEY__';
System.assert(
    apiKey != '__IBM_API' + '_KEY__',
    'API key placeholder was not replaced — check CI script'
);

QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
if (settings.Id == null) {
    settings = new QRNG_Settings__c(
        SetupOwnerId = UserInfo.getOrganizationId()
    );
}
settings.IBM_API_Key__c = apiKey;
settings.Default_Backend__c = 'ibm_kingston';
settings.Default_Shots__c = 1024;
settings.Use_Bell_Test__c = false;
upsert settings;

System.debug('✓ QRNG_Settings__c configured with IBM API key');
