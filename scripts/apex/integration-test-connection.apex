/**
 * Integration test: verifies real IBM Quantum API connectivity.
 * Run via: sf apex run --file scripts/apex/integration-test-connection.apex --target-org <alias>
 *
 * Prerequisites:
 *   - QRNG_Settings__c must have a valid IBM_API_Key__c
 *   - Remote Site Settings for IBM IAM and Quantum API must be active
 *
 * This script is READ-ONLY: it authenticates and lists backends.
 * It does NOT submit jobs or consume quantum minutes.
 */

// Step 1: Verify settings exist
QRNG_Settings__c settings = QRNG_Settings__c.getInstance();
System.assert(settings != null, 'QRNG_Settings__c not found — run setup-api-key.apex first');
System.assert(
    String.isNotBlank(settings.IBM_API_Key__c),
    'IBM_API_Key__c is blank — API key was not injected into the scratch org'
);
System.debug('✓ QRNG_Settings__c has an API key configured');

// Step 2: Test IAM token exchange (real callout)
Boolean connected = IBMQuantumAuth.testApiKey();
System.assert(connected, 'IBMQuantumAuth.testApiKey() returned false — IAM token exchange failed');
System.debug('✓ IAM token exchange succeeded');

// Step 3: List backends (real callout — read-only, zero quantum minutes)
String backendsJson = IBMQuantumService.getBackends();
System.assert(String.isNotBlank(backendsJson), 'getBackends() returned empty response');
System.debug('✓ IBM Quantum backends response received');

// Step 4: Parse and validate response structure
Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(backendsJson);
Boolean hasDevices = response.containsKey('devices') || response.containsKey('backends');
System.assert(hasDevices, 'Response missing "devices" or "backends" key: ' + backendsJson.left(500));
System.debug('✓ Backend list parsed successfully');

// Summary
List<Object> devices = response.containsKey('devices')
    ? (List<Object>) response.get('devices')
    : (List<Object>) response.get('backends');
System.debug('✓ Integration test PASSED — ' + devices.size() + ' backend(s) available');
