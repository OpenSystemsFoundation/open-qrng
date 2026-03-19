# Adding a New Quantum Provider

QuantumFair uses a pluggable provider architecture so you can connect to **any** quantum computing backend — IBM Quantum, IonQ, Quantinuum, AWS Braket, or your own hardware.

This guide walks you through adding a new provider from scratch.

## Architecture Overview

```
LWC Components (provider-agnostic)
        │
        ▼
QRNGSetupController ─── DTOs ──▶ Frontend
        │
        ▼
QuantumProviderFactory.getActiveProvider()
        │
        ▼
┌───────────────────────────────────────┐
│        QuantumProvider (interface)     │
├───────────────────────────────────────┤
│ IBMQuantumProvider  │ YourProvider    │
│ ├─ IBMQuantumAuth   │ ├─ YourAuth    │
│ └─ IBMQuantumService│ └─ YourService │
└───────────────────────────────────────┘
```

**Key principle:** All provider-specific code stays inside your provider class (and its supporting service/auth classes). The controller, job processor, poller, and sweeper are completely generic.

## Step-by-Step Guide

### 1. Create Your Auth Class

Handle authentication with your provider's API. Follow the pattern in `IBMQuantumAuth.cls`.

```apex
// force-app/main/default/classes/YourProviderAuth.cls
public with sharing class YourProviderAuth {
    @TestVisible
    private static String cachedToken;
    @TestVisible
    private static DateTime tokenExpiry;

    public static String getAccessToken() {
        if (cachedToken != null && tokenExpiry > DateTime.now()) {
            return cachedToken;
        }
        QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
        String apiKey = settings.IBM_API_Key__c; // Reuse or add a custom field

        // Call your provider's token endpoint
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.yourprovider.com/auth/token');
        req.setMethod('POST');
        req.setBody('{"api_key":"' + apiKey + '"}');
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res = new Http().send(req);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
        );

        cachedToken = (String) body.get('access_token');
        tokenExpiry = DateTime.now().addMinutes(50);
        return cachedToken;
    }

    public static Boolean testApiKey() {
        try {
            getAccessToken();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    public static void clearCache() {
        cachedToken = null;
        tokenExpiry = null;
    }
}
```

### 2. Create Your Service Class

Handle REST API calls to your provider. Follow the pattern in `IBMQuantumService.cls`.

```apex
// force-app/main/default/classes/YourProviderService.cls
public with sharing class YourProviderService {
    private static final String BASE_URL = 'https://api.yourprovider.com';

    public static String submitJob(
        String openqasm,
        String backend,
        Integer shots
    ) {
        String token = YourProviderAuth.getAccessToken();
        // Build your provider's job submission request
        // Return the external job ID
    }

    public static Map<String, Object> getJobStatus(String jobId) {
        String token = YourProviderAuth.getAccessToken();
        // Return a map with at least a 'status' key
        // Use your provider's status values — IBMResponseParser.normalizeStatus()
        // handles mapping to internal statuses (Completed, Failed, Running, Queued)
    }

    public static String getJobResults(String jobId) {
        String token = YourProviderAuth.getAccessToken();
        // Return the raw results JSON
        // Must conform to the format expected by QRNGResultParser:
        // {"results":[{"data":{"meas":{"samples":["0110","1001",...]}}}]}
    }

    public static String getBackends() {
        String token = YourProviderAuth.getAccessToken();
        // Return JSON with backend list
    }
}
```

### 3. Implement the QuantumProvider Interface

This is the main class that connects everything. Each method is documented in `QuantumProvider.cls`.

```apex
// force-app/main/default/classes/YourProvider.cls
public with sharing class YourProvider implements QuantumProvider {
    // ── Identity ──
    public String getProviderName() {
        return 'yourprovider';
    }

    // ── Authentication ──
    public String authenticate() {
        return YourProviderAuth.getAccessToken();
    }

    public Boolean testConnection() {
        return YourProviderAuth.testApiKey();
    }

    // ── Job lifecycle ──
    public String submitJob(String openqasm, String backend, Integer shots) {
        return YourProviderService.submitJob(openqasm, backend, shots);
    }

    public Id submitTrackedJob(
        String openqasm,
        String backend,
        Integer shots,
        String purpose,
        Boolean useBellTest,
        Integer numQubits
    ) {
        // 1. Call your API to submit the job
        String externalJobId = submitJob(openqasm, backend, shots);

        // 2. Create the Quantum_Job__c record
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = externalJobId,
            Provider__c = getProviderName(),
            Backend__c = backend,
            Status__c = 'Submitted',
            Circuit_QASM__c = openqasm,
            Shots__c = shots,
            Num_Qubits__c = numQubits,
            Purpose__c = purpose,
            Use_Bell_Test__c = useBellTest != null ? useBellTest : false,
            Job_Type__c = 'QRNG',
            Requested_By__c = UserInfo.getUserId(),
            Submitted_At__c = DateTime.now()
        );
        insert job;

        // 3. Start polling
        System.enqueueJob(new QRNGJobPoller(job.Id, externalJobId, 0));
        return job.Id;
    }

    public Map<String, Object> getJobStatus(String externalJobId) {
        return YourProviderService.getJobStatus(externalJobId);
    }

    public String getJobResults(String externalJobId) {
        return YourProviderService.getJobResults(externalJobId);
    }

    // ── Backend discovery ──
    public List<Map<String, Object>> listBackends() {
        // Parse your provider's backend list into a standard format:
        // Each map must have at least 'name' and 'status'
        // Optional: 'qubits', 'queueLength', 'isSimulator'
        return new List<Map<String, Object>>();
    }

    public Map<String, Object> getBackendProperties(String backendName) {
        return YourProviderService.getBackendProperties(backendName);
    }

    public String getLeastBusyBackend() {
        // Return null if your provider doesn't support queue inspection
        return null;
    }

    // ── Circuit building ──
    public String buildCircuit(
        Integer numQubits,
        String backendName,
        Boolean useBellTest
    ) {
        // For providers with all-to-all connectivity (IonQ), just use
        // QRNGCircuitBuilder.buildStandardCircuit(numQubits) directly.
        // For providers with limited connectivity, fetch topology and optimize.
        if (useBellTest) {
            return QRNGCircuitBuilder.buildBellTestCircuit(
                numQubits / 2,
                null,
                null
            );
        }
        return QRNGCircuitBuilder.buildStandardCircuit(numQubits);
    }

    // ── Verification ──
    public Id submitVerificationJob(String backendName, Integer shots) {
        // Submit a CHSH Bell test verification job using your provider's API.
        // The simplest approach: build a Bell state circuit, run it as a
        // standard sampler job, and let QRNGValidator.calculateCHSH() compute
        // the S-value from the bitstrings.
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(1, null, null);
        return submitTrackedJob(
            qasm,
            backendName,
            shots,
            'CHSH verification',
            true,
            2
        );
    }

    // ── Provider-specific configuration ──
    public List<Map<String, String>> discoverInstances() {
        // Return empty list if your provider doesn't have instance discovery
        return new List<Map<String, String>>();
    }
}
```

### 4. Register Your Provider

Add a single line to `QuantumProviderFactory.cls`:

```apex
private static final Map<String, System.Type> PROVIDER_REGISTRY = new Map<String, System.Type>{
    'ibm' => IBMQuantumProvider.class,
    'yourprovider' => YourProvider.class    // ← Add this line
};
```

### 5. Create a QRNG_Provider\_\_c Record

Your provider needs a record in the `QRNG_Provider__c` custom object to appear in the UI. Create it via the setup controller or data loader:

| Field               | Value                                           |
| ------------------- | ----------------------------------------------- |
| Name                | Your Provider                                   |
| Provider_Key\_\_c   | `yourprovider` (must match `getProviderName()`) |
| Is_Active\_\_c      | `true`                                          |
| Provider_Class\_\_c | `YourProvider`                                  |
| Auth_Endpoint\_\_c  | `https://api.yourprovider.com/auth`             |
| API_Base_URL\_\_c   | `https://api.yourprovider.com`                  |
| Status\_\_c         | `Connected`                                     |

### 6. Write Tests (90%+ Coverage Required)

Create `YourProvider_Test.cls` with:

- Test all interface methods
- Mock HTTP callouts using `HttpCalloutMock`
- Test authentication (success + failure)
- Test job submission and status polling
- Test backend listing
- Test circuit building for your topology

Follow the pattern in `IBMQuantumProvider_Test.cls`.

### 7. Create `-meta.xml` Files

Every `.cls` file needs a matching `.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>66.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

## Result Format Contract

The most important integration point is the **results JSON format**. `QRNGResultParser` expects results from sampler jobs in this format:

```json
{
    "results": [
        {
            "data": {
                "meas": {
                    "samples": ["0110", "1001", "0x3c", "0xab"]
                }
            }
        }
    ]
}
```

- **Samples** can be binary strings (`"0110"`) or hex-encoded (`"0x3c"`)
- Each sample represents one measurement shot
- The parser handles both formats transparently

If your provider returns a different format, you have two options:

1. **Transform in your service class** — convert to the standard format before returning from `getJobResults()`
2. **Extend QRNGResultParser** — add a new parser method and route based on `Provider__c`

Option 1 is recommended for simplicity.

## Status Normalization

`IBMResponseParser.normalizeStatus()` maps provider-specific status strings to internal values:

| Internal Status | Maps From                           |
| --------------- | ----------------------------------- |
| `Completed`     | completed, result_ready, COMPLETED  |
| `Running`       | running, RUNNING                    |
| `Queued`        | queued, pending_in_queue, QUEUED    |
| `Failed`        | failed, cancelled, canceled, FAILED |
| `Submitted`     | (anything else)                     |

If your provider uses different status names, either:

- Map them in your `getJobStatus()` to one of the recognized values above
- Or extend `IBMResponseParser.normalizeStatus()` with your provider's status names

## File Checklist

For a complete provider implementation, you'll create these files:

```
force-app/main/default/classes/
├── YourProvider.cls              ← QuantumProvider implementation
├── YourProvider.cls-meta.xml
├── YourProviderAuth.cls          ← Authentication handler
├── YourProviderAuth.cls-meta.xml
├── YourProviderService.cls       ← REST API client
├── YourProviderService.cls-meta.xml
├── YourProvider_Test.cls         ← Tests (90%+ coverage)
└── YourProvider_Test.cls-meta.xml
```

Plus one line added to `QuantumProviderFactory.cls`.

## Questions?

Open an issue at the project repository or refer to `ARCHITECTURE.md` for the full system design.
