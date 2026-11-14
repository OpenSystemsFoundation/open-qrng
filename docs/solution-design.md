# QuantumFair — Solution Design

**Quantum random number generation for Salesforce, with no middleware.**
Apache-2.0 · Open Systems Foundation Labs

This document is the technical source of truth for QuantumFair: what it is built from, how a request flows from Salesforce to IBM Quantum hardware and back, how randomness is turned into an auditable assignment, and what the security model is. For installation and day-to-day use, see the [Manual](manual.md).

---

## 1. Purpose and scope

QuantumFair is a Labs tech demo with two goals:

1. **Prove the integration pattern.** Salesforce can build quantum circuits in Apex and submit them straight to the IBM Quantum REST API — no Python, no Qiskit, no Heroku/AWS service in between.
2. **Show a business use case outside finance.** Certified random selection (lead routing, audit sampling, panel selection, trial randomization) with a tamper-evident audit trail.

### Design constraints

| Constraint                    | Decision                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------- |
| No external servers           | Everything runs on Salesforce — Apex, LWC, Platform Events, custom objects      |
| No middleware                 | Apex calls the IBM Quantum REST API directly over HTTPS                         |
| BYOQ (bring your own quantum) | Each org provides its own IBM Quantum API key and instance CRN in the Setup tab |
| No Python/Qiskit dependency   | Apex generates ISA-compliant OpenQASM 3.0 directly (QRNG circuits are shallow)  |
| Unmanaged distribution        | No namespace, no InstallHandler — background scheduling is automated in-app     |
| Open source                   | Apache-2.0, full source on GitHub                                               |

### What the certificate does and does not claim

- Every assignment is **replayable**: the same certified bit pool always produces the same assignment, and the canonical assignment hash is stored on the certificate.
- Every certificate is **tamper-evident**: SHA-256 hashes of raw bits, debiased bits and the assignment, chained to the previous certificate and re-verified nightly.
- The optional Bell test gives evidence **consistent with quantum origin** (CHSH violated by at least 2σ). It is **not** device-independent certified randomness: the org still trusts IBM to have run the circuit on the hardware it reports, and the usual Bell-test loopholes are open on a single superconducting chip.

### Cost model

IBM's Open Plan includes 10 minutes of QPU time per rolling window at no cost; pay-as-you-go is billed per second (USD 96/minute at the time of writing). A standard QRNG job uses a few seconds of QPU time. QuantumFair is not cost-competitive with a classical CSPRNG today — that is not its point.

---

## 2. System architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SALESFORCE ORG                               │
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐ │
│  │   LWC UI    │───▶│  Apex Layer  │───▶│   IBM Quantum REST API │ │
│  │  / Flow     │◀───│              │◀───│   (HTTPS callout)      │ │
│  └─────────────┘    └──────────────┘    └────────────────────────┘ │
│        ▲                   │                                        │
│        │            ┌──────▼──────┐                                 │
│        │            │  Platform   │                                 │
│        └────────────│   Events    │                                 │
│                     └─────────────┘                                 │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Custom Objects                             │  │
│  │  Quantum_Job__c │ Fairness_Certificate__c │ Quantum_Assignment__c │
│  │  Quantum_Provider__c │ Quantum_Backend__c │ Compliance_Event__c  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │   Protected Custom Setting (IBM API key) + Remote Site        │  │
│  │   Settings (IBM_IAM, IBM_Quantum_API, IBM_Resource_Controller)│  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Layer 1 — Circuit generation (Apex)

### Why no transpiler is needed

IBM Quantum only accepts **ISA circuits** — circuits already expressed in the backend's native gates on physical qubits. On IBM Heron processors the native set is:

- `rz(θ)` — Z rotation
- `sx` — √X
- `x` — Pauli-X
- `cz` — the two-qubit entangling gate

A Hadamard decomposes as `H = rz(π/2) · sx · rz(π/2)`. A QRNG circuit is just H + measure on N qubits, so `CircuitBuilder.cls` emits the OpenQASM 3.0 string directly.

### `CircuitBuilder.cls`

```
Responsibility: Generate ISA-compliant OpenQASM 3.0 for QRNG and CHSH circuits
Input:         Qubit count (or pair count), optional calibration data
Output:        OpenQASM 3.0 string ready for the IBM Sampler primitive
```

**Standard QRNG circuit** (N physical qubits, each in superposition):

```qasm
OPENQASM 3.0;
include "stdgates.inc";
bit[N] meas;
// For each physical qubit $i:
rz(pi/2) $i;
sx $i;
rz(pi/2) $i;
meas[i] = measure $i;
```

- `selectBestQubits()` ranks physical qubits by readout error when calibration data is available.
- 1–127 qubits are accepted; each shot yields N raw bits (8 qubits × 1024 shots = 8,192 raw bits).

**Bell-test (CHSH) circuit:**

- `selectBestPair()` / coupled-pair selection picks physically connected qubit pairs from the backend coupling map, scored by two-qubit gate and readout error.
- Each pair is entangled with an H on qubit A followed by a CNOT decomposed into native gates: `H(B) · cz(A,B) · H(B)`.
- Pairs are assigned round-robin to the four CHSH basis configurations. Measurement bases are applied as `Ry` rotations decomposed into `rz`/`sx`, with Alice ∈ {0, π/2} and Bob ∈ {π/4, −π/4} — the angles that give S = 2√2 for |Φ+⟩. Angles are emitted as decimal literals (IBM's QASM parser can mishandle symbolic expressions).

### Backend registry — `Quantum_Provider__c` / `Quantum_Backend__c`

Provider and backend metadata are synced from the IBM `/backends`, `/properties` and `/configuration` endpoints:

- `Quantum_Provider__c` — provider registry row (provider key, Apex class, API base URL, auth endpoint, active flag)
- `Quantum_Backend__c` — per-backend record (master-detail to provider): qubit count, processor family/revision, median gate/readout error, T1/T2, queue length, max shots, simulator flag, NIST SP 800-90B entropy-source documentation fields, and quantum-verification fields (CHSH job, S-value, verified timestamp)

Backend selection at submission: request override → settings default → least-busy (when `Use_Least_Busy__c` is on).

---

## 4. Layer 2 — IBM Quantum integration (Apex)

### Authentication

```
┌──────────┐     ┌────────────────────┐     ┌─────────────────────┐
│ Admin    │────▶│ Protected custom   │────▶│ IBM IAM token       │
│ Setup    │     │ setting            │     │ exchange            │
│ tab      │     │ Quantum_Settings__c│     │ POST iam.cloud.ibm  │
│ (UI)     │     │ .IBM_API_Key__c    │     │ .com/identity/token │
└──────────┘     └────────────────────┘     └─────────────────────┘
                                                    │
                                                    ▼
                                     Bearer token cached in Platform
                                     Cache 'local.QuantumFair' (50-min
                                     TTL), transaction-static fallback
```

**`IBMQuantumAuth.cls`**

- Reads the API key from the Protected custom setting `Quantum_Settings__c.IBM_API_Key__c`
- Exchanges it for an IAM bearer token (`POST https://iam.cloud.ibm.com/identity/token`)
- Caches the token (never the key) in the Platform Cache partition `local.QuantumFair` for 50 minutes (tokens live 60); without cache capacity it falls back to a transaction-scoped static
- `discoverInstances()` lists the account's Quantum instances via the IBM Resource Controller so the admin can auto-detect the instance CRN

**Callout authorization** — three Remote Site Settings ship with the app:

| Remote Site               | URL                                         |
| ------------------------- | ------------------------------------------- |
| `IBM_IAM`                 | `https://iam.cloud.ibm.com`                 |
| `IBM_Quantum_API`         | `https://quantum.cloud.ibm.com`             |
| `IBM_Resource_Controller` | `https://resource-controller.cloud.ibm.com` |

### REST client — `IBMQuantumService.cls`

```
Protocol:  IBM Quantum Platform (Qiskit Runtime) REST API v1
Base URL:  https://quantum.cloud.ibm.com/api
Headers:   Authorization: Bearer {token}
           Service-CRN: {instance CRN}
           IBM-API-Version: 2026-04-15
```

The API version is pinned. IBM lists supported versions at `GET /v1/versions` (no authentication); deprecated versions are sunset about a year after their successor, and a missing or unrecognized header silently falls back to an older version — so bump the constant in `IBMQuantumService` when IBM ships a new version. Open Plan instances live in `us-east` (`quantum.cloud.ibm.com`); instances in `eu-de` use `eu-de.quantum.cloud.ibm.com` and would need a second Remote Site Setting.

| Call                                    | Purpose                            |
| --------------------------------------- | ---------------------------------- |
| `POST /v1/jobs`                         | Submit a Sampler job               |
| `GET /v1/jobs/{id}`                     | Poll status                        |
| `GET /v1/jobs/{id}/results`             | Fetch measurement results          |
| `GET /v1/backends`                      | List backends (health, least-busy) |
| `GET /v1/backends/{name}/properties`    | Calibration data (qubit selection) |
| `GET /v1/backends/{name}/configuration` | Coupling map (Bell-pair selection) |

**Submit body (SamplerV2):**

```json
{
    "program_id": "sampler",
    "backend": "ibm_kingston",
    "params": {
        "pubs": [["{openqasm_string}", null, 1024]],
        "version": 2
    }
}
```

The returned job ID is stored on `Quantum_Job__c.External_Job_ID__c` and is the anchor for external verification.

### Async submission and polling

The pipeline is asynchronous end to end and bulk-safe from Flow:

```
Flow / LWC / Apex
    │  (no callouts in the invocable — trigger-safe)
    ▼
Quantum_Job__c rows inserted, Status__c = 'Pending'
(full request persisted as JSON in Assignment_Request__c)
    │
    ▼
QuantumSubmissionQueueable   — one job per execution, chains itself
    │  callouts (auth, backend resolve, submit) → THEN update to 'Submitted'
    ▼
JobPollScheduler → JobPoller — Schedulable/Queueable hop per poll
    │  1 min × 5 polls, then 2, 3, 5, 7 min, capped at 10 min
    │  wall-clock budget: 6 h from Submitted_At__c
    ▼
JobProcessor — parse, debias, validate, certify, assign, publish events
```

**`QuantumSubmissionQueueable`** performs callouts for exactly one pending job per execution (callouts strictly before DML), marks it `Submitted`, starts the poll chain, and re-enqueues itself for the remaining jobs. A submission failure marks that job `Failed`, publishes `Quantum_Job_Failed__e`, and the chain continues.

**`JobPoller`** (Queueable, `Database.AllowsCallouts`, documented `without sharing`):

1. `GET /v1/jobs/{id}` — read `state.status`, stamp `Last_Polled_At__c`
2. Still in flight → schedule the next poll via `JobPollScheduler` (the Schedulable hop sidesteps Queueable chain-depth limits)
3. Completed → fetch results and hand off to `JobProcessor`
4. Terminal failure → mark the job `Failed`, publish `Quantum_Job_Failed__e`

**Transient vs terminal errors.** Timeouts, HTTP 429/5xx, IAM failures and unknown IBM statuses are transient: the error is appended to `Error_Message__c` and polling continues. A job is terminally failed only when IBM reports a terminal state, the 6-hour budget is exhausted (the external job ID is preserved so results can be recovered with Retrieve Results), or 10 consecutive transient errors occur.

**`JobSweeper`** (Schedulable safety net, auto-scheduled on the first successful settings save):

- Skips jobs polled in the last 3 minutes, so it never races an active poll chain
- Fails `Pending` jobs older than 15 minutes and zombie jobs past the 6-hour budget, publishing `Quantum_Job_Failed__e` for each
- Processes at most 3 completed jobs per run (bounds heap — payloads can exceed 1 MB)
- Never marks a job `Completed` before processing; a processing error leaves it retryable

**`JobProcessor` is idempotent** — it re-reads the job `FOR UPDATE` before processing, so poller/sweeper/manual-retrieval races are no-ops. Every `EventBus.publish` result is checked.

---

## 5. Layer 3 — Randomness processing and certification

### Result parsing — `ResultParser.cls`

IBM Sampler returns one sample per shot, as binary or hex strings:

```json
{ "results": [{ "data": { "meas": { "samples": ["0xb6", "0x17", "..."] } } }] }
```

1. Samples are decoded (hex → zero-padded binary) into raw bitstrings.
2. **Per-qubit von Neumann debiasing**: the interleaved pool is split into per-qubit streams and each stream is debiased against itself (01→0, 10→1, 00/11→discard). Debiasing across qubits would pair bits with different biases and not debias at all.
3. Bell-test jobs use `vonNeumannDebiasBellPairs`, which takes only the Alice-side qubits — the engineered correlated bits never enter the randomness pool.
4. Raw and debiased bits are stored on `Quantum_Job__c`.

Oversized configurations (encoded raw results > 131,072 characters) are rejected at submission. Results are never truncated — a truncated pool would break audit replay.

### Statistical validation — `RandomnessValidator.cls`

All gates use **alpha = 0.01**:

| Test                            | Checks                            | Pass criterion                                 |
| ------------------------------- | --------------------------------- | ---------------------------------------------- |
| Frequency (monobit)             | Balance of 0s and 1s              | \|z\| ≤ 2.576                                  |
| Runs                            | Lengths of runs of identical bits | \|z\| ≤ 2.576                                  |
| Chi-squared                     | Uniformity of N-bit blocks        | Exact critical values (e.g. 30.578 at df = 15) |
| CHSH violation (Bell-test mode) | S from four correlators           | (S − 2.0) > 2σ_S                               |

The CHSH gate computes σ_S from per-correlator sample counts and stores `sigmaS` and `margin` with the results. Fewer than 4 correlator pairs throws. A flat `S > 2` gate would let classical data pass on noise; the 2σ margin is why the app says "consistent with quantum origin (CHSH violated at ≥2σ)".

If validation fails, no certificate is issued.

### Extended validation and revocation — `ValidationRunner.cls`

NIST SP 800-90B health tests run asynchronously **after** certification and can **revoke** it: MCV min-entropy with the SP 800-90B confidence bound, repetition count, adaptive proportion, CUSUM and longest run. On failure the certificate `Status__c` becomes `Revoked`, the failure is recorded on the job, and `Quantum_Job_Failed__e` is published.

Because min-entropy uses the confidence bound, pools under roughly 2,500 bits fail the 0.9 threshold even when perfectly balanced. This is intentional: small samples cannot support the claim.

### Fairness certificate — `FairnessCertificateService.cls`

| Field                                                                  | Description                                       |
| ---------------------------------------------------------------------- | ------------------------------------------------- |
| `Quantum_Job__c` (master-detail)                                       | Source job                                        |
| `External_Job_ID__c` / `Backend__c` / `Circuit_QASM__c`                | IBM job ID, QPU name, exact OpenQASM submitted    |
| `Raw_Bitstring_Hash__c`                                                | SHA-256 of raw measurement data                   |
| `Debiased_Bitstring_Hash__c`                                           | SHA-256 of the debiased pool                      |
| `Assignment_Hash__c`                                                   | SHA-256 of the canonical assignment serialization |
| `Chain_Hash__c` / `Previous_Certificate_Hash__c` / `Chain_Position__c` | Tamper-evident hash chain                         |
| `Validation_Results__c`                                                | Test results JSON (incl. `sigmaS`/`margin`)       |
| `CHSH_S_Value__c`                                                      | Bell-test S value                                 |
| `Backend_Verified__c` / `Backend_Verified_At__c`                       | Backend CHSH verification status                  |
| `Tampered__c` / `Last_Integrity_Check__c`                              | Nightly integrity outcome                         |
| `Verified_By__c` / `Verified_At__c`                                    | Last manual verification                          |
| `Created_By_User__c` / `Purpose__c`                                    | Requester and stated purpose                      |
| `Status__c`                                                            | Pending / Certified / Failed / Revoked            |

**Audit chain:** certificate → `Quantum_Job__c` (external job ID) → `Quantum_Assignment__c` records. An auditor can check that the job exists at IBM, that the bits pass the tests, and that the assignment follows deterministically from the bits. `IntegrityVerificationJob` re-hashes every certificate nightly and walks the chain.

---

## 6. Layer 4 — Assignment engine

### `QuantumAssignmentEngine.cls`

All randomness consumption uses **rejection sampling — never modulo**. Bit consumption is strictly sequential and documented in the class header so auditors can replay every draw.

**Rejection rule** (unbiased index in `[0, m)`):

1. Read the next `ceil(log2(m))` bits as an unsigned integer `v`
2. If `v >= m`, discard the block and read the next one (discarded blocks still advance the offset and are recorded)
3. Repeat until `v < m`

The pool is never wrapped or reused. If it runs out, the engine **throws** — there is no pseudo-random fallback.

| Mode     | Algorithm                                                                                                                                              |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Uniform  | One rejection-sampled draw in `[0, numAssignees)` per record, in input order                                                                           |
| Weighted | Weights scaled by 10⁶ to Longs; draw in `[0, scaledTotal)`; walk assignees in input order, first cumulative weight strictly greater than the draw wins |
| Subset   | Fisher–Yates with bit width recomputed per swap (`ceilLog2(i+1)`), positions n−1 down to 1, take the first K                                           |

**Canonical assignment hash:** SHA-256 over one line per assignment, `index:recordId:assigneeId` (assigneeId empty for Subset), sorted by `Assignment_Index__c`, joined with `\n`. `Random_Value__c` on each assignment stores the exact bits consumed for that draw, rejected blocks included.

### Invocable action — `QuantumRandomAssignment`

```apex
@InvocableMethod(label='Quantum Random Assignment'
                 description='Assigns records using quantum-certified randomness'
                 category='QuantumFair')
```

Flow inputs: `recordIds`, `assigneeIds`, `assignmentType` (Uniform / Weighted / Subset), `weights`, `sampleSize`, `purpose`, `useBellTest`, and optional `numQubits` (default 8) and `backend`. Shots come from the `Default_Shots__c` setting (default 1024). Outputs: `jobId`, `success`, `errorMessage`.

The invocable performs **no callouts**: it validates each request, bulk-inserts `Pending` jobs with the request serialized to `Assignment_Request__c`, and enqueues `QuantumSubmissionQueueable`. That makes it safe for 200 interviews per invocation and for record-triggered (after-save) flows. On completion `JobProcessor` deserializes the request, runs the engine, inserts `Quantum_Assignment__c` rows (all-or-nothing) and stamps the assignment hash on the certificate.

---

## 7. Layer 5 — Lightning Web Components

Hand-rolled, no third-party libraries; charts and circuit diagrams are Canvas 2D.

```
lwc/
├── quantumFairApp              ← App shell: Dashboard, Jobs, Setup, Operations, Compliance
├── qrngRequestForm             ← Request random numbers (purpose, backend, qubits, shots)
├── qrngJobMonitor              ← Real-time job progress via empApi
├── qrngJobDashboard            ← Filterable job table
├── qrngJobStatusPanel          ← Job type + status display
├── qrngQasmViewer              ← Canvas 2D OpenQASM circuit renderer
├── qrngCircuitVisualizer       ← Circuit diagram
├── qrngResultsVisualizer       ← Canvas 2D measurement charts
├── qrngValidationResults       ← Statistical + CHSH results
├── qrngBellTestIndicator       ← CHSH gauge
├── qrngChshVisualizer          ← CHSH correlator breakdown
├── qrngFairnessCertificate     ← Certificate view (@api recordId — works on record pages)
├── qrngAssignmentTable         ← Assignment results (DTO-based)
├── qrngSetup                   ← Setup orchestrator
├── qrngConnectionSetup         ← API key, instance CRN, connection test
├── qrngSettingsPanel           ← Default backend, shots, compliance email
├── qrngHealthMonitor           ← Backend health and CHSH verification
├── qrngBackgroundJobs          ← Sweeper / integrity job scheduling
├── qrngAuditTrail              ← Timeline of jobs and certificates
├── qrngComplianceExport        ← Framework evidence JSON export
├── qrngEventSubscription       ← Shared Platform Event subscription utility
└── qrngUtils                   ← Shared utilities (reduceErrors)
```

Conventions:

- Components consume typed DTOs from `SetupController`; raw SObjects never cross to the client
- Every wire renders a visible error state
- empApi channels are namespace-free (`/event/Quantum_Job_Complete__e`)
- Canvas renderers respect `devicePixelRatio`
- Modals use dialog semantics (role, focus management, Escape)
- `data-testid` attributes form the selector contract with the Playwright suite

---

## 8. Data model

```
┌───────────────────────────┐      ┌────────────────────────────────┐
│      Quantum_Job__c       │      │    Fairness_Certificate__c     │
├───────────────────────────┤      ├────────────────────────────────┤
│ External_Job_ID__c        │◀─MD──│ Quantum_Job__c                 │
│ Provider__c / Backend__c  │      │ External_Job_ID__c             │
│ Status__c (Pending/       │      │ Backend__c / Circuit_QASM__c   │
│  Submitted/Queued/Running │      │ Raw_Bitstring_Hash__c          │
│  /Completed/Failed)       │      │ Debiased_Bitstring_Hash__c     │
│ Job_Type__c/Program_Id__c │      │ Assignment_Hash__c             │
│ Circuit_QASM__c           │      │ Chain_Hash__c / Chain_Position │
│ Shots__c / Num_Qubits__c  │      │ Previous_Certificate(_Hash)__c │
│ Use_Bell_Test__c          │      │ Validation_Results__c          │
│ Assignment_Type__c        │      │ CHSH_S_Value__c                │
│ Assignment_Request__c     │      │ Backend_Verified(_At)__c       │
│ Raw_Results__c            │      │ Tampered__c                    │
│ Debiased_Results__c       │      │ Last_Integrity_Check__c        │
│ Validation_Results__c     │      │ Verified_By__c / Verified_At__c│
│ Result_Fingerprint__c     │      │ Purpose__c / Created_By_User__c│
│ Submitted_At__c           │      │ Status__c (Pending/Certified/  │
│ Completed_At__c           │      │  Failed/Revoked)               │
│ Last_Polled_At__c         │      └────────────────────────────────┘
│ Poll_Count__c             │
│ Requested_By__c           │      ┌────────────────────────────────┐
│ Error_Message__c          │      │     Quantum_Assignment__c      │
│ Execution_Time_ms__c      │◀─MD──├────────────────────────────────┤
│ Queue_Time_ms__c          │      │ Quantum_Job__c (master-detail) │
│ QPU_Time_seconds__c       │      │ Certificate__c (lookup)        │
│ Purpose__c                │      │ Assigned_Record_ID__c          │
└───────────────────────────┘      │ Assigned_To_ID__c              │
                                   │ Assignment_Index__c            │
┌───────────────────────────┐      │ Random_Value__c (bits consumed)│
│    Quantum_Provider__c    │      └────────────────────────────────┘
├───────────────────────────┤
│ Provider_Key__c           │      ┌────────────────────────────────┐
│ Provider_Class__c         │      │      Compliance_Event__c       │
│ API_Base_URL__c           │      ├────────────────────────────────┤
│ Auth_Endpoint__c          │      │ Event_Type__c                  │
│ Is_Active__c / Status__c  │      │ Actor__c / Severity__c         │
│ Last_Synced__c            │      │ Detail__c / Detail_Hash__c     │
└─────────────┬─────────────┘      │ Related_Job__c                 │
              │ MD                 │ Related_Certificate__c         │
              ▼                    └────────────────────────────────┘
┌───────────────────────────┐
│     Quantum_Backend__c    │      ┌────────────────────────────────┐
├───────────────────────────┤      │ Quantum_Settings__c (Protected │
│ Backend_Key__c            │      │ hierarchy custom setting)      │
│ Num_Qubits__c/Max_Shots__c│      ├────────────────────────────────┤
│ Processor_Family/Revision │      │ IBM_API_Key__c                 │
│ Median gate/readout error │      │ Instance_CRN__c                │
│ Avg_T1_us__c/Avg_T2_us__c │      │ Default_Backend__c             │
│ Queue_Length__c/Status__c │      │ Default_Shots__c               │
│ Noise_Source_Type__c      │      │ Use_Bell_Test__c               │
│ Conditioning_Component__c │      │ Use_Least_Busy__c              │
│ Health_Test_* fields      │      │ Poll_Interval_Minutes__c       │
│ CHSH_* / Quantum_Verified │      │ Integrity_Check_Hour__c        │
└───────────────────────────┘      │ Compliance_Email__c            │
                                   └────────────────────────────────┘
```

Also: `Compliance_Control__mdt` (24 seed records mapping controls to ISO 27001, SOC 2, NIST SP 800-90B, GDPR and eIDAS) and the Platform Events `Quantum_Job_Complete__e` / `Quantum_Job_Failed__e`.

---

## 9. Security architecture

### API key storage — design and tradeoff

The IBM API key is stored in a **Protected hierarchy custom setting** (`Quantum_Settings__c.IBM_API_Key__c`), entered in the Setup tab. Named/External Credentials cannot be pre-wired with a per-org secret in an unmanaged package without manual setup, so the app uses the custom setting instead.

The key is plaintext at rest in the org. Mitigations:

- The setting is Protected — hidden from ordinary users
- The key is never returned to the client (`SetupController.getSettings` exposes only `hasApiKey`)
- The key is never logged (settings-change events record field names, never values)
- The key is only sent to IBM IAM over TLS
- Only the short-lived bearer token is cached

Orgs that require encryption at rest can add Shield Platform Encryption or move the key into their own Named Credential.

### Authorization

- Custom permission **`QuantumFair_Administer`** (granted only by the `QuantumFair_Admin` permission set) gates every privileged `@AuraEnabled` method via `FeatureManagement.checkPermission()` — saving settings, scheduling jobs, backend verification, evidence export. The System Administrator profile alone is denied.
- All three permission sets grant `SetupController` access and read on both Platform Events.
- Settings changes are logged to `Compliance_Event__c` as `SETTINGS_CHANGED`.

| Permission set        | Persona          | Access                                                             |
| --------------------- | ---------------- | ------------------------------------------------------------------ |
| `QuantumFair_Admin`   | Administrator    | Everything, including `QuantumFair_Administer`                     |
| `QuantumFair_User`    | Business user    | Request assignments; view jobs, certificates, results              |
| `QuantumFair_Auditor` | External auditor | Read-only; raw and debiased bitstrings withheld by FLS server-side |

### Data security

- **OWD Private**: `Quantum_Job__c`, `Quantum_Provider__c`, `Compliance_Event__c`; `Fairness_Certificate__c`, `Quantum_Assignment__c`, `Quantum_Backend__c` are Controlled by Parent
- `with sharing` everywhere except the documented `without sharing` async workers that maintain the app's own job records
- CRUD/FLS enforced server-side with `WITH USER_MODE` and `Security.stripInaccessible`
- No Salesforce data leaves the org — only circuit definitions go to IBM

### Integrity verification

The certificate carries three SHA-256 hashes (raw, debiased, assignment) plus the chain hash. An auditor can recompute the assignment hash by replaying the documented rejection-sampling rules, and check the raw data against IBM using the job ID. `IntegrityVerificationJob` re-hashes nightly and sets `Tampered__c` on any mismatch.

---

## 10. End-to-end sequence

```
User / Flow               Apex                     IBM Quantum
    │                      │                          │
    ├──Request────────────▶│ (invocable: no callouts) │
    │                      ├──Insert Quantum_Job__c   │
    │                      │  Status='Pending'         │
    │◀── "Queued" ─────────├──Enqueue submission       │
    │                      │                          │
    │  Submission Queueable├──Build OpenQASM          │
    │  (one job per exec)  ├──POST /v1/jobs──────────▶│
    │                      │◀─── { id } ──────────────│
    │                      ├──Status='Submitted'       │
    │                      │                          │
    │  Poll (backoff,      ├──GET /v1/jobs/{id}──────▶│
    │  6 h budget)         │◀─── Queued / Running ────│
    │                      │                          │
    │                      ├──GET /v1/jobs/{id}──────▶│
    │                      │◀─── Completed ───────────│
    │                      ├──GET /v1/jobs/{id}/results▶│
    │                      │◀─── samples ─────────────│
    │   JobProcessor       ├──Debias, validate        │
    │   (idempotent)       ├──Certificate + chain     │
    │                      ├──Assignment engine       │
    │                      ├──Publish Quantum_Job_Complete__e
    │                      ├──Enqueue ValidationRunner (can revoke)
    │◀── Platform Event ───│                          │
```

---

## 11. Governor limit budget

| Operation                    | Limit           | Usage                                                                 |
| ---------------------------- | --------------- | --------------------------------------------------------------------- |
| Callouts per transaction     | 100             | Submission: ≤5; poller: 2; sweeper: ~14 worst case                    |
| Callout timeout              | 120 s           | IBM typically responds in <5 s; submit timeout 60 s                   |
| Heap (async)                 | 12 MB           | Sweeper bounded to 3 completions per run                              |
| Queueable chain depth        | n/a             | Poll chain hops through Schedulable                                   |
| Scheduled jobs per org       | 100             | One CronTrigger per in-flight poll; failures fall back to the sweeper |
| Platform Events published/tx | 250             | One per completion/failure                                            |
| SOQL queries per tx          | 100             | ~5 per poll cycle                                                     |
| DML rows per tx              | 10,000          | Certificate + assignments well within                                 |
| Platform Cache               | partition-based | `local.QuantumFair`; bearer token ≈ 2 KB                              |

---

## 12. Extensibility

### Platform Events

`Quantum_Job_Complete__e`: `Job_Id__c`, `Certificate_Id__c`, `Num_Random_Bits__c`, `Status__c`.
`Quantum_Job_Failed__e`: `Job_Id__c`, `Error_Message__c` — also published when extended validation revokes a certificate.

Any Flow, trigger or CometD client can subscribe. The usual pattern is a Platform Event–triggered flow that reads `Quantum_Assignment__c` rows for the job and updates the source records (see the [Manual](manual.md#7-running-assignments-from-flow)).

### `QuantumConsumer` interface

```apex
public interface QuantumConsumer {
    void onRandomnessReady(Id certificateId, List<String> randomBits);
    void onRandomnessFailed(Id jobId, String errorMessage);
}
```

A contract for custom randomness consumers. Automatic dispatch is not wired; today custom code subscribes to the Platform Events.

### Adding a quantum provider

Provider-specific code lives behind the `QuantumProvider` interface; the controller, submission queueable, poller, sweeper and processor are generic.

```
LWC ──DTOs── SetupController
                  │
     QuantumProviderFactory.getActiveProvider()
                  │
        QuantumProvider (interface)
        ├── IBMQuantumProvider ── IBMQuantumAuth / IBMQuantumService
        └── YourProvider       ── YourAuth / YourService
```

1. Implement `QuantumProvider`: `getProviderName`, `authenticate`, `testConnection`, `submitJob(openqasm, backend, shots)`, `getJobStatus`, `getJobResults`, `listBackends`, `getBackendProperties`, `getLeastBusyBackend`, `submitVerificationJob`, `discoverInstances`.
2. Register it in `QuantumProviderFactory.PROVIDER_REGISTRY` (`'yourprovider' => YourProvider.class`).
3. Create a `Quantum_Provider__c` record with `Provider_Key__c` matching `getProviderName()`, `Provider_Class__c`, endpoints and `Is_Active__c = true`.
4. Add a Remote Site Setting for the provider's hosts.
5. **Result contract:** `getJobResults()` must return `{"results":[{"data":{"meas":{"samples":[...]}}}]}` with binary (`"0110"`) or hex (`"0x3c"`) samples — transform in your service class if the provider differs.
6. **Status contract:** map provider states to `Completed`, `Running`, `Queued`, `Failed` (anything else is treated as `Submitted`); see `IBMResponseParser.normalizeStatus()`.
7. Native gates differ per vendor — extend `CircuitBuilder` if your hardware does not accept `rz`/`sx`/`x`/`cz`.
8. Tests with `HttpCalloutMock`, 90%+ coverage (follow `IBMQuantumProvider_Test`).

### Possible extensions

- **Device attestation cadence:** run CHSH once per backend per window and link certificates to that attestation instead of per job.
- **Randomness expansion:** seed a CSPRNG from a certified quantum pool for high-volume use; the certificate would record the expansion method.

---

## 13. Distribution

- **Unmanaged package / source deploy**, no namespace; the app page is `/lightning/n/QuantumFair`.
- No InstallHandler (unsupported for unmanaged packages). Instead, saving a working API key schedules `JobSweeper` and `IntegrityVerificationJob`; saving a compliance email schedules `ComplianceDigestJob` (daily 06:00), and clearing it unschedules it.
- **Editions:** Enterprise, Unlimited, Developer. **Requires:** an IBM Quantum account (Open Plan works for evaluation).

---

## 14. Package contents

```
force-app/main/default/
├── classes/                    — Apex (tests alongside sources, 30 test classes)
│   ├── CircuitBuilder              OpenQASM 3.0 generation (ISA)
│   ├── IBMQuantumAuth              IAM token exchange + Platform Cache
│   ├── IBMQuantumService           REST client
│   ├── IBMQuantumProvider          QuantumProvider for IBM
│   ├── IBMResponseParser           IBM response parsing / status normalization
│   ├── QuantumSubmissionQueueable  Async chained submission
│   ├── JobPoller / JobPollScheduler Poll chain with backoff
│   ├── JobProcessor                Idempotent completion processing
│   ├── JobSweeper                  Scheduled safety net
│   ├── ResultParser                Sample decoding + per-qubit von Neumann
│   ├── RandomnessValidator         Statistical tests + CHSH margin
│   ├── ValidationRunner            Async SP 800-90B suite (can revoke)
│   ├── QuantumAssignmentEngine     Rejection-sampled assignment
│   ├── QuantumRandomAssignment     Flow invocable (bulk-safe)
│   ├── FairnessCertificateService  Certificates + hash chain
│   ├── IntegrityVerificationJob    Nightly re-hash
│   ├── Compliance*                 Event logging, digest, summary, evidence export, controls
│   ├── SetupController             Single LWC controller (permission-gated)
│   └── QuantumProvider / QuantumProviderFactory / QuantumConsumer / QuantumException
├── lwc/                        — 22 components
├── objects/                    — custom objects, settings, metadata type, platform events
├── customMetadata/             — 24 Compliance_Control records
├── customPermissions/          — QuantumFair_Administer
├── remoteSiteSettings/         — IBM_IAM, IBM_Quantum_API, IBM_Resource_Controller
├── cachePartitions/            — QuantumFair
├── permissionsets/             — QuantumFair_Admin / _User / _Auditor
├── applications/, tabs/, flexipages/, layouts/, notificationtypes/
└── flows/                      — 5 flow templates (lead, case, opportunity, account, generic)
```
