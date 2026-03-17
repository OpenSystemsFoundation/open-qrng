# Multi-Backend Architecture & Dynamic Backend Discovery Plan

**Date:** 2026-03-17
**Status:** Planning
**Author:** Jeff + Claude

---

## 1. Problem Statement

QuantumFair is currently hardcoded to IBM Quantum. To become a truly provider-agnostic quantum randomness platform, we need:

1. **Dynamic backend discovery** — sync live backend info (qubits, error rates, coupling map, queue length) from IBM and display it to admins
2. **Multi-provider architecture** — support IBM, AWS Braket, Azure Quantum, IonQ, Quantinuum, and custom backends
3. **CRN auto-discovery** — eliminate manual CRN entry for IBM Cloud
4. **V2 primitives** — align with Qiskit Runtime SamplerV2 and latest OpenQASM 3.0
5. **Backend performance dashboard** — show T1/T2 times, gate errors, readout errors, and queue status

---

## 2. IBM Quick Wins (Implement Now)

### 2.1 Dynamic Backend Discovery from IBM

**Endpoints available:**
- `GET /v1/backends` — list all backends with name, status, qubits, queue_length, wait_time, processor_type
- `GET /v1/backends/{id}/configuration` — coupling map, basis gates, max_shots, n_qubits
- `GET /v1/backends/{id}/properties` — per-qubit T1, T2, readout_error; per-gate gate_error, gate_length
- `GET /v1/backends/{id}/status` — operational status, pending jobs

**Implementation:**
- Add `syncBackends()` method to `IBMQuantumService` that calls `/v1/backends` and upserts `QRNG_Backend_Config__mdt` records
- Add `getBackendProperties(backendName)` method that calls `/v1/backends/{id}/properties`
- Display backend health summary in the Setup tab (T1/T2 averages, median gate error, readout error, queue depth)
- Add "Refresh Backends" button to sync live data

### 2.2 CRN Auto-Discovery

**Endpoint:** IBM Cloud Resource Controller API
- `GET https://resource-controller.cloud.ibm.com/v2/resource_instances?resource_id=b6049020-80f4-11eb-a0f7-e35ec9b4054f`
- Uses the same IAM bearer token
- Returns list of Qiskit Runtime instances with their CRNs
- Auto-populate CRN in settings, or let user pick if multiple instances exist

**Implementation:**
- Add `IBM_Resource_Controller` to Remote Site Settings
- Add `discoverInstances()` method to `IBMQuantumAuth`
- Add "Auto-detect CRN" button in Setup tab
- If single instance → auto-fill; if multiple → show picker

### 2.3 V2 Primitives Alignment

**Current state:** Our REST API payload uses `program_id: 'sampler'` which is correct for V2 SamplerV2.

**Required updates:**
- Add `IBM-API-Version` header with latest date string (already done: `2025-11-01`)
- PUB format: `[[circuit_qasm, null, shots]]` — currently correct
- Add `params.version: 2` — currently included
- Verify response parsing matches V2 result structure (bitstrings/counts format)
- Add dynamical decoupling option support in job submission

### 2.4 Backend Performance Display

New LWC component `qrngBackendHealth` showing:
- Backend name, processor family, qubit count
- Average T1/T2 times across all qubits
- Median single-qubit gate error
- Median two-qubit gate error
- Median readout error
- Current queue depth and estimated wait time
- Last calibration timestamp

---

## 3. Multi-Provider Architecture (Phase 2)

### 3.1 Provider Abstraction Layer

Create an Apex interface hierarchy:

```
QuantumProvider (interface)
├── authenticate() → String (token)
├── submitJob(circuit, backend, shots) → String (jobId)
├── getJobStatus(jobId) → Map<String, Object>
├── getJobResults(jobId) → String (JSON)
├── listBackends() → List<Map<String, Object>>
├── getBackendProperties(name) → Map<String, Object>
└── getProviderName() → String

Implementations:
├── IBMQuantumProvider (current code, refactored)
├── AWSBraketProvider (future)
├── AzureQuantumProvider (future)
├── IonQProvider (future)
├── QuantinuumProvider (future)
└── CustomProvider (generic REST adapter)
```

### 3.2 Provider Registry (Custom Metadata)

Enhance `QRNG_Backend_Config__mdt` or create new `QRNG_Provider__mdt`:

| Field | Type | Description |
|---|---|---|
| `Provider_Name__c` | Text | e.g., "ibm", "aws_braket", "azure", "ionq", "custom" |
| `Provider_Class__c` | Text | Apex class name implementing QuantumProvider |
| `Auth_Endpoint__c` | URL | Provider auth URL |
| `API_Base_URL__c` | URL | Provider API base URL |
| `Is_Active__c` | Checkbox | Whether this provider is enabled |

### 3.3 Circuit Portability

Different providers have different native gate sets:

| Provider | Native Gates | 2Q Gate |
|---|---|---|
| IBM (Heron r2) | rz, sx, x | ecr |
| IonQ | GPI, GPI2, MS | MS |
| Quantinuum | rz, ry | ZZPhase |
| Rigetti | rx, rz | CZ |
| Custom | configurable | configurable |

**Strategy:**
- Generate standard OpenQASM 3.0 (no ISA decomposition)
- Let each provider's transpiler handle decomposition
- For IBM: we do ISA decomposition in Apex (already implemented)
- For others: submit standard QASM and let their API handle it
- Store native gate set in `QRNG_Backend_Config__mdt.Native_Gates__c`

### 3.4 Credential Management

Each provider needs different credentials:

| Provider | Credential Type |
|---|---|
| IBM | API Key → IAM Token + Instance CRN |
| AWS Braket | Access Key + Secret Key + Region |
| Azure Quantum | Tenant ID + Client ID + Client Secret + Subscription |
| IonQ | API Key (direct bearer) |
| Quantinuum | Username + Password → Token |
| Custom | Configurable (API Key, OAuth, Basic Auth) |

**Storage:** Use `QRNG_Settings__c` with a `Provider_Credentials__c` Long Text Area field containing encrypted JSON per provider. Or use Named Credentials per provider (preferred for security).

### 3.5 Data Model Updates

| Change | From | To |
|---|---|---|
| `Quantum_Job__c.IBM_Job_ID__c` | IBM-specific | Rename to `External_Job_ID__c` |
| `Fairness_Certificate__c.IBM_Job_ID__c` | IBM-specific | Rename to `External_Job_ID__c` |
| New field | — | `Quantum_Job__c.Provider__c` (Text) |
| New field | — | `Quantum_Job__c.Provider_Metadata__c` (Long Text) |

---

## 4. Enhanced Backend Config Metadata

Update `QRNG_Backend_Config__mdt` with additional fields:

| Field | Type | Description |
|---|---|---|
| `Provider__c` | Text | Provider name (ibm, aws, azure, etc.) |
| `Status__c` | Text | online/offline/maintenance |
| `Processor_Family__c` | Text | e.g., "Heron", "Eagle", "Aria" |
| `Processor_Revision__c` | Text | e.g., "r2" |
| `Max_Shots__c` | Number | Maximum shots per job |
| `Queue_Length__c` | Number | Current pending jobs |
| `Avg_T1_us__c` | Number | Average T1 in microseconds |
| `Avg_T2_us__c` | Number | Average T2 in microseconds |
| `Median_1Q_Error__c` | Number | Median single-qubit gate error |
| `Median_2Q_Error__c` | Number | Median two-qubit gate error |
| `Median_Readout_Error__c` | Number | Median measurement error |
| `Last_Calibration__c` | DateTime | Last calibration timestamp |
| `Coupling_Map__c` | Long Text | Already exists |
| `Native_Gates__c` | Long Text | Already exists |

---

## 5. Implementation Phases

### Phase 1: IBM Quick Wins (Now)
- [x] Add `Service-CRN` and `IBM-API-Version` headers to all API calls
- [x] Add `Instance_CRN__c` field and Setup UI
- [ ] CRN auto-discovery via IBM Cloud Resource Controller API
- [ ] Dynamic backend list sync from `/v1/backends`
- [ ] Backend properties fetch (T1, T2, errors) from `/v1/backends/{id}/properties`
- [ ] Backend health summary LWC component
- [ ] "Refresh Backends" button in Setup
- [ ] Verify V2 primitive payload format is correct

### Phase 2: Abstraction Layer (Next Sprint)
- [ ] Create `QuantumProvider` Apex interface
- [ ] Refactor `IBMQuantumService` → `IBMQuantumProvider` implementing interface
- [ ] Refactor `IBMQuantumAuth` → provider-specific auth
- [ ] Create `QuantumProviderFactory` for provider selection
- [ ] Update `QRNG_Backend_Config__mdt` with new fields
- [ ] Provider selector in Setup UI

### Phase 3: Additional Providers (Future)
- [ ] IonQ provider (simplest — direct API key auth)
- [ ] AWS Braket provider
- [ ] Azure Quantum provider
- [ ] Quantinuum provider
- [ ] Custom/generic REST provider

### Phase 4: Advanced Features
- [ ] Auto-select best backend based on job requirements (qubits, error threshold, queue time)
- [ ] Cross-provider job routing
- [ ] Provider cost comparison
- [ ] Backend historical performance tracking

---

## 6. OpenQASM & Qiskit 2.3 Alignment

### Current State
- We generate ISA-compliant OpenQASM 3.0 in Apex (`QRNGCircuitBuilder`)
- Native gates: `rz(θ)`, `sx`, `x`, `ecr` (IBM Heron r2 specific)
- H decomposition: `rz(π/2) → sx → rz(π/2)`

### Updates Needed
- Verify QASM output matches what IBM expects for V2 SamplerV2
- Consider adding `include "stdgates.inc"` header for standard QASM
- Support fractional gates if backend supports them
- Circuit builder should query backend config for native gate set rather than hardcoding
- Add Bell test circuit validation against backend coupling map

### Qiskit 2.3 Key Changes to Track
- V1 primitives fully removed — V2 only
- `backend.run()` removed — SamplerV2 required
- `c_if` removed — use `if_test()` context manager
- `ibm_quantum` channel sunset — use `ibm_quantum_platform`
- Gate `duration`/`unit` fields removed — query `Target` for durations
- Prefer Gate-based objects over QuantumCircuit-based for compiler performance

---

## 7. Remote Site Settings Needed

| URL | Provider | Purpose |
|---|---|---|
| `https://quantum.cloud.ibm.com` | IBM | Runtime API (exists) |
| `https://iam.cloud.ibm.com` | IBM | IAM auth (exists) |
| `https://resource-controller.cloud.ibm.com` | IBM | CRN auto-discovery (new) |
| `https://api.ionq.co` | IonQ | Future |
| `https://api.quantinuum.com` | Quantinuum | Future |
| `https://braket.*.amazonaws.com` | AWS | Future |

---

## 8. Risk & Considerations

- **IBM minutes budget:** 200 min total across all packages. Backend property fetches don't consume execution minutes (metadata only).
- **Governor limits:** Backend sync could hit callout limits if many backends. Batch with care.
- **Custom Metadata deployment:** `QRNG_Backend_Config__mdt` is Protected — updates require package version or deploy. Consider using Custom Settings for dynamic data instead.
- **Security:** Never store credentials in Custom Metadata (readable). Use Custom Settings (Hierarchy) or Named Credentials.
- **Field renames** (`IBM_Job_ID__c` → `External_Job_ID__c`): Breaking change for managed package. Needs migration strategy.
