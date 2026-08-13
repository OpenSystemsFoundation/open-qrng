# QuantumFair — Architecture

**Open-Source Quantum Random Number Generation for Salesforce**
Apache-2.0 | Open Source | Zero Infrastructure Cost

---

## Overview

QuantumFair is an open-source Salesforce app — distributed as an unmanaged package / source deploy — that provides **certified quantum random number generation** (QRNG) for fair, auditable business process randomization. It uses real quantum hardware to generate true randomness and creates immutable fairness certificates linked to every assignment.

**Core principle:** The app that uses quantum mechanics to prove your business decisions are fair.

### Constraints

| Constraint                  | Decision                                                                       |
| --------------------------- | ------------------------------------------------------------------------------ |
| No external servers         | Everything runs on Salesforce — Apex, LWC, Platform Events, Custom Objects     |
| Zero cost to maintain       | No Heroku, no AWS, no middleware. Apex calls IBM Quantum REST API directly     |
| BYOQ                        | Each org provides their own IBM Quantum API key via the in-app Setup tab       |
| Open-source                 | Apache-2.0 license, full source on GitHub; AppExchange listing planned         |
| Unmanaged distribution      | No namespace, no InstallHandler — scheduling is automated in-app               |
| No Python/Qiskit dependency | Apex generates ISA-compliant OpenQASM 3.0 directly (trivial for QRNG circuits) |

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SALESFORCE ORG                               │
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐ │
│  │   LWC UI    │───▶│  Apex Layer  │───▶│   IBM Quantum REST API │ │
│  │             │◀───│              │◀───│   (External Callout)   │ │
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

## Layer 1 — Quantum Circuit Generation (Apex)

### Why No Python Middleware Is Needed

IBM Quantum's REST API requires **ISA (Instruction Set Architecture) circuits** — circuits decomposed into the backend's native gate set. For most IBM backends (Heron r2, Eagle), the native gates are:

- `rz(θ)` — Z-rotation
- `sx` — √X gate
- `x` — Pauli-X gate
- `cz` / `ecr` — two-qubit entangling gate

A Hadamard gate decomposes trivially:

```
H = Rz(π/2) → SX → Rz(π/2)
```

For QRNG, every circuit is just **H + measure on N qubits**. This is simple enough to generate the ISA-compliant OpenQASM 3.0 string directly in Apex — no transpiler needed.

### Circuit Builder — `CircuitBuilder.cls`

```
Responsibility: Generate ISA-compliant OpenQASM 3.0 for QRNG circuits
Input:         Number of random bits needed, target backend name
Output:        OpenQASM 3.0 string ready for IBM Runtime Sampler
```

**Standard QRNG circuit** (N qubits, each in superposition):

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

Each shot produces N random bits. With 1024 shots on 8 qubits = 8,192 random bits per circuit execution.

**Bell-test QRNG circuit** (optional stronger certification):

For Bell-test certification (CHSH inequality violation as evidence consistent with quantum origin), the circuit creates entangled pairs and measures in complementary bases. The decomposition into native gates is still straightforward — `ecr` or `cz` gates for entanglement, `rz`/`sx` for basis rotations.

### Backend Registry — `Quantum_Provider__c` / `Quantum_Backend__c`

Provider and backend metadata live in custom objects, synced from the IBM `/backends` and configuration/properties endpoints:

- `Quantum_Provider__c` — provider registry row (API base URL, auth endpoint, provider class, active flag)
- `Quantum_Backend__c` — per-backend records (master-detail to provider): qubit count, processor family/revision, calibration data (median gate/readout error, T1/T2), queue length, max shots, simulator flag, and NIST 800-90B entropy-source documentation fields (noise source type, conditioning component, health-test status), plus quantum-verification fields (CHSH job, S-value, verified timestamp)

Backend selection at submission time resolves: request override → settings default → least-busy.

---

## Layer 2 — IBM Quantum Integration (Apex)

### Authentication Flow

```
┌──────────┐     ┌────────────────────┐     ┌─────────────────────┐
│ Admin    │────▶│ Protected Custom   │────▶│ IBM IAM Token       │
│ Setup    │     │ Setting            │     │ Exchange            │
│ tab      │     │ Quantum_Settings__c │    │ POST iam.cloud.ibm  │
│ (UI)     │     │ .IBM_API_Key__c    │     │ .com/identity/token │
└──────────┘     └────────────────────┘     └─────────────────────┘
                                                    │
                                                    ▼
                                     Bearer token cached in Platform
                                     Cache 'local.QuantumFair' (50-min
                                     TTL), transaction-static fallback
```

**`IBMQuantumAuth.cls`**

- Reads the IBM API key from the **Protected custom setting** `Quantum_Settings__c.IBM_API_Key__c` (see Security Architecture for the design tradeoff)
- Exchanges it for an IAM Bearer token via `POST https://iam.cloud.ibm.com/identity/token`
- Caches the Bearer token (never the key) in the **Platform Cache partition `local.QuantumFair`** with a 50-minute TTL (tokens are valid 60 minutes); if Platform Cache is unavailable (no capacity, partition undeployed, test context) it degrades gracefully to a transaction-scoped static
- Automatically refreshes on expiry

**Callout authorization** — three packaged Remote Site Settings:

| Remote Site               | URL                                         |
| ------------------------- | ------------------------------------------- |
| `IBM_IAM`                 | `https://iam.cloud.ibm.com`                 |
| `IBM_Quantum_API`         | `https://quantum.cloud.ibm.com`             |
| `IBM_Resource_Controller` | `https://resource-controller.cloud.ibm.com` |

### Job Submission — `IBMQuantumService.cls`

```
Responsibility: Submit circuits, poll status, retrieve results
Protocol:       IBM Qiskit Runtime REST API v1
Base URL:       https://quantum.cloud.ibm.com/api
```

**Submit job:**

```
POST /v1/jobs
Headers:
  Authorization: Bearer {iam_token}
  Content-Type: application/json

Body:
{
  "program_id": "sampler",
  "backend": "ibm_kingston",
  "params": {
    "pubs": [
      ["{openqasm_string}", null, {shots}]
    ],
    "version": 2
  }
}
```

**Response:** `{ "id": "job_id", "backend": "ibm_kingston" }`

The job ID is stored in `Quantum_Job__c` and async polling begins.

### Async Submission & Polling

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

**`QuantumSubmissionQueueable.cls`** — performs callouts for exactly one pending job per execution (callouts strictly precede DML), updates it to `Submitted`, starts the poll chain, then enqueues itself for the remaining jobs. A submission failure marks that job `Failed`, publishes `Quantum_Job_Failed__e`, and the chain continues.

**`JobPoller.cls` (Queueable, Database.AllowsCallouts, `without sharing`)**

1. `GET /v1/jobs/{job_id}` — check `state.status`; stamp `Last_Polled_At__c`
2. If still in flight → schedule the next poll via `JobPollScheduler` (the Schedulable hop sidesteps Queueable chain-depth limits) with a stretching backoff: 1 minute for the first 5 polls, then 2, 3, 5, 7 minutes, capped at 10
3. If `Completed` → fetch results and delegate to `JobProcessor`
4. If IBM reports a terminal failure → update `Quantum_Job__c`, publish `Quantum_Job_Failed__e`

**Error handling (transient vs terminal):** timeouts, HTTP 429/5xx, IAM failures, and **unknown IBM statuses** are treated as transient — the error is appended to `Error_Message__c`, the status is left unchanged, and polling continues. A job is only terminally failed when (a) IBM reports a terminal state, (b) the 6-hour wall-clock budget from `Submitted_At__c` is exhausted (the failure message notes results may still be recoverable via Retrieve Results — the external job ID is preserved), or (c) 10 consecutive transient errors occur (safety valve).

**`JobSweeper.cls` (Schedulable safety net)** — auto-scheduled on the first successful settings save; each sweep:

- Skips jobs polled within the last 3 minutes (`Last_Polled_At__c`), so it never races an active poll chain
- Terminally fails `Pending` jobs older than 15 minutes (created but never submitted) and zombie jobs past the 6-hour budget — publishing `Quantum_Job_Failed__e` for every job it fails (publish results checked)
- Processes at most 3 completed jobs per sweep (bounds heap — full payloads can exceed 1 MB)
- Never flips a job to `Completed` before processing; a processing throw leaves the job retryable

**`JobProcessor.cls` is idempotent** — it re-checks the job status `FOR UPDATE` at the top of completion processing, so a poller/sweeper/manual-retrieval race double-processes as a no-op. All `EventBus.publish` results are checked everywhere; publish failures are recorded.

---

## Layer 3 — Randomness Processing & Certification (Apex)

### Result Parser — `ResultParser.cls`

IBM Sampler returns measurement results as bitstring samples:

```json
{
  "results": [{
    "data": {
      "meas": {
        "samples": ["0110", "1001", "1110", "0011", ...]
      }
    }
  }]
}
```

The parser:

1. Extracts raw bitstrings from the Sampler response
2. Applies **per-qubit von Neumann debiasing**: the interleaved pool is de-interleaved into per-qubit streams (stride N), and each stream is debiased against itself (pairs of bits: 01→0, 10→1, 00/11→discard). Debiasing across different qubits would pair bits with different biases and not debias at all.
3. For Bell-test jobs, `vonNeumannDebiasBellPairs` uses only the Alice-side qubits — the engineered correlated bits are excluded from the randomness pool
4. Stores raw + debiased bits in `Quantum_Job__c`

**Oversized configurations are rejected at submission**: any qubit×shot combination whose encoded raw bitstring would exceed the 131,072-character storage field is refused up front. Results are never truncated-and-hashed — a truncated pool would silently break third-party audit replay.

### Statistical Validation — `RandomnessValidator.cls`

Runs randomness checks before certifying, all gated at **alpha = 0.01**:

| Test                                | What It Checks                          | Pass Criteria                                            |
| ----------------------------------- | --------------------------------------- | -------------------------------------------------------- |
| **Frequency (monobit)**             | Proportion of 0s vs 1s                  | z ≤ 2.576 (two-sided alpha = 0.01)                       |
| **Runs test**                       | Length of consecutive identical bits    | z ≤ 2.576                                                |
| **Chi-squared on distribution**     | Uniformity of N-bit blocks              | Exact critical values (e.g. 30.578 at df = 15)           |
| **CHSH violation** (Bell-test mode) | S parameter from entangled measurements | (S − 2.0) > 2σ_S — significance margin, not a flat S > 2 |

The CHSH gate computes a standard error σ_S from the per-correlator sample counts; `sigmaS` and `margin` are stored in the validation results. Fewer than 4 correlator pairs throws rather than certifying. A flat `S > 2.0` gate would let classical data pass on noise alone — the 2σ margin makes the claim "consistent with quantum origin (CHSH violated at ≥2σ)", which is the language used throughout docs and UI.

If validation fails, the job is flagged and the certificate is not issued.

### Extended Validation & Revocation — `ValidationRunner.cls`

SP 800-90B extended health tests run **asynchronously after certification** — and can **revoke** it. The suite includes MCV min-entropy **with the SP 800-90B confidence bound**, repetition-count, adaptive-proportion, CUSUM, and longest-run tests. On failure:

- The certificate `Status__c` flips to **`Revoked`** (a dedicated picklist value)
- The failure is recorded on the job (`Error_Message__c`)
- A `Quantum_Job_Failed__e` event is published so subscribers learn certification was withdrawn

**Expected behavior for small pools:** because the min-entropy estimate uses the confidence bound, pools under roughly 2,500 bits fail the 0.9 min-entropy threshold even when perfectly balanced. This is by design — small samples cannot statistically support the claim.

### Fairness Certificate — `FairnessCertificateService.cls`

On successful validation, creates a `Fairness_Certificate__c` record:

| Field                                                                  | Type                | Description                                      |
| ---------------------------------------------------------------------- | ------------------- | ------------------------------------------------ |
| `Quantum_Job__c`                                                       | Master-Detail       | Link to the quantum job record                   |
| `External_Job_ID__c`                                                   | Text                | Provider's job ID (externally verifiable)        |
| `Backend__c`                                                           | Text                | QPU used (e.g., `ibm_kingston`)                  |
| `Circuit_QASM__c`                                                      | Long Text           | Exact OpenQASM submitted                         |
| `Raw_Bitstring_Hash__c`                                                | Text                | SHA-256 hash of raw measurement data             |
| `Debiased_Bitstring_Hash__c`                                           | Text                | SHA-256 hash of the debiased random pool         |
| `Assignment_Hash__c`                                                   | Text                | SHA-256 hash of the canonical assignment mapping |
| `Chain_Hash__c` / `Previous_Certificate_Hash__c` / `Chain_Position__c` | Text / Number       | Tamper-evident hash chain across certificates    |
| `Validation_Results__c`                                                | Long Text (JSON)    | Statistical test results (incl. sigmaS/margin)   |
| `CHSH_S_Value__c`                                                      | Number              | Bell-test S value (if applicable)                |
| `Backend_Verified__c` / `Backend_Verified_At__c`                       | Checkbox / DateTime | Backend quantum-verification status              |
| `Tampered__c` / `Last_Integrity_Check__c`                              | Checkbox / DateTime | Integrity verification outcome                   |
| `Created_By_User__c`                                                   | Lookup(User)        | Who requested the random assignment              |
| `Purpose__c`                                                           | Text                | What the randomness was used for                 |
| `Status__c`                                                            | Picklist            | Certified / Failed / Pending / **Revoked**       |

**Audit chain:** Certificate → links to → `Quantum_Job__c` (with external job ID) → links to → assigned records via `Quantum_Assignment__c`. Any auditor can verify: the circuit was run on IBM hardware (job ID verifiable via IBM API), the measurements are statistically random, and the assignment follows deterministically from the measurements (see Layer 4). `IntegrityVerificationJob` re-hashes certificates nightly and flags tampering.

---

## Layer 4 — Assignment Engine (Apex)

### Random Assignment — `QuantumAssignmentEngine.cls`

Converts quantum random bits into fair assignments. **All randomness consumption uses rejection sampling — there is no modulo bias anywhere**, and bit consumption is strictly sequential and documented in the class header so auditors can replay every draw.

**Rejection rule** (unbiased index in `[0, m)`):

1. Read the next `ceil(log2(m))` bits as an unsigned integer `v`
2. If `v >= m`, discard the block and read the next one (discarded blocks still advance the pool offset and are recorded in the audit trail)
3. Repeat until `v < m`

The pool is never wrapped or reused. If the pool is exhausted before a draw completes, the engine **throws** — it never falls back to biased or pseudo randomness.

**Uniform distribution** (e.g., lead assignment): one rejection-sampled draw in `[0, numAssignees)` per record, in input record order.

**Weighted distribution**: exact integer arithmetic — each weight is scaled by 10⁶ and rounded to a Long; a value is drawn in `[0, scaledTotal)` with the rejection rule, then assignees are walked in input order and the first whose cumulative scaled weight exceeds the value (strict `<`) wins.

**Subset selection** (e.g., audit sampling): Fisher–Yates shuffle with the bit width recomputed per swap (`ceilLog2(i+1)`), consuming draws for positions n−1 down to 1, then take the first K.

**Canonical assignment hash:** after assignments are inserted, the certificate's `Assignment_Hash__c` is set to the SHA-256 of the canonical serialization — one line per assignment formatted `index:recordId:assigneeId` (assigneeId empty for Subset selections), sorted by `Assignment_Index__c`, joined with `\n`. `Random_Value__c` on each assignment stores the exact bits consumed for the deciding draw (rejected blocks included), enabling per-selection third-party verification.

### Invocable Action — `QuantumRandomAssignment` (Flow-compatible)

```apex
@InvocableMethod(label='Quantum Random Assignment'
                 description='Assigns records using quantum-certified randomness'
                 category='QuantumFair')
```

Inputs exposed to Flow Builder:

- `recordIds` — List of record IDs to assign
- `assigneeIds` — List of User/Queue IDs to assign to
- `assignmentType` — Uniform / Weighted / Subset
- `weights` — Optional weight values for weighted mode
- `sampleSize` — Sample size for Subset mode
- `purpose` — Description for the fairness certificate
- `useBellTest` — Whether to use stronger Bell-test certification
- `numQubits` / `backend` — Optional circuit overrides

**Bulk-safe and trigger-safe:** the invocable performs no callouts. It validates each request, bulk-inserts `Quantum_Job__c` rows (`Status__c = 'Pending'`, full request persisted as JSON in `Assignment_Request__c`), and enqueues `QuantumSubmissionQueueable`, which performs the callouts one job per execution. This makes the action safe for up to 200 Flow interviews per invocation and for `RecordAfterSave` record-triggered flows. On completion, `JobProcessor` deserializes the persisted request, dispatches to the assignment engine by type, inserts `Quantum_Assignment__c` records (all-or-nothing), and stamps the assignment hash on the certificate.

---

## Layer 5 — LWC Components

All components are hand-rolled using the latest LWC features (Spring '26). No third-party dependencies. Everything renders natively in Lightning.

### Component Map

```
lwc/
├── quantumFairApp              ← Main app shell (5-tab layout)
├── qrngSetup                   ← Admin setup orchestrator
├── qrngConnectionSetup         ← API key entry + auto-connection test
├── qrngSettingsPanel           ← Backend, shots, compliance email config
├── qrngHealthMonitor           ← Backend health with fidelity scoring
├── qrngBackgroundJobs          ← Scheduler management (self-loads its own state)
├── qrngJobDashboard            ← Filterable job table with real-time updates
├── qrngJobMonitor              ← Real-time job status via empApi
├── qrngJobStatusPanel          ← Job type + status display
├── qrngQasmViewer              ← Canvas 2D OpenQASM circuit renderer
├── qrngCircuitVisualizer       ← Legacy circuit diagram
├── qrngResultsVisualizer       ← Canvas 2D measurement charts
├── qrngValidationResults       ← Statistical + CHSH results (job-type aware)
├── qrngRequestForm             ← Assignment request form
├── qrngFairnessCertificate     ← Certificate document view (@api recordId — works on record pages)
├── qrngAssignmentTable         ← Results table (DTO-based, jobId targetConfig)
├── qrngAuditTrail              ← Timeline of all QRNG jobs with certificates
├── qrngBellTestIndicator       ← CHSH gauge (CSS conic-gradient)
├── qrngChshVisualizer          ← CHSH correlator breakdown chart
├── qrngComplianceExport        ← Framework evidence JSON download
├── qrngEventSubscription       ← Shared Platform Event subscription utility
└── qrngUtils                   ← Shared utilities (reduceErrors)
```

Frontend conventions worth noting:

- **DTO contract:** components consume typed DTOs from `SetupController`; raw SObjects are never returned to the client (server-side FLS via `stripInaccessible`/`WITH USER_MODE`)
- **Wire error handling:** every wire renders a visible error state — errors are never silently swallowed
- **empApi channels are namespace-free** (`/event/Quantum_Job_Complete__e`)
- **Canvas renderers handle devicePixelRatio** (crisp on HiDPI displays)
- **Accessibility:** modals use proper dialog semantics (role, focus management, Escape)
- **`data-testid` attributes** (60+ across templates) form the selector contract shared with the Playwright E2E suite

---

## Data Model

```
┌───────────────────────────┐      ┌────────────────────────────────┐
│      Quantum_Job__c       │      │    Fairness_Certificate__c     │
├───────────────────────────┤      ├────────────────────────────────┤
│ External_Job_ID__c        │◀─MD──│ Quantum_Job__c                 │
│ Provider__c / Backend__c  │      │ External_Job_ID__c             │
│ Status__c (Pending/       │      │ Backend__c / Circuit_QASM__c   │
│  Submitted/Queued/Running │      │ Raw_Bitstring_Hash__c          │
│  /Completed/Failed)       │      │ Debiased_Bitstring_Hash__c     │
│ Job_Type__c / Program_Id__c│     │ Assignment_Hash__c             │
│ Circuit_QASM__c           │      │ Chain_Hash__c / Chain_Position │
│ Shots__c / Num_Qubits__c  │      │ Previous_Certificate(_Hash)__c │
│ Use_Bell_Test__c          │      │ Validation_Results__c          │
│ Assignment_Type__c        │      │ CHSH_S_Value__c                │
│ Assignment_Request__c(JSON)│     │ Backend_Verified(_At)__c       │
│ Raw_Results__c            │      │ Tampered__c                    │
│ Debiased_Results__c       │      │ Last_Integrity_Check__c        │
│ Validation_Results__c     │      │ Verified_By__c / Verified_At__c│
│ Result_Fingerprint__c     │      │ Purpose__c / Created_By_User__c│
│ Submitted_At__c           │      │ Status__c (Certified/Failed/   │
│ Completed_At__c           │      │  Pending/Revoked)              │
│ Last_Polled_At__c         │      └────────────────────────────────┘
│ Poll_Count__c             │
│ Requested_By__c           │      ┌────────────────────────────────┐
│ Error_Message__c          │      │     Quantum_Assignment__c      │
│ Execution_Time_ms__c      │◀─MD──├────────────────────────────────┤
│ Queue_Time_ms__c          │      │ Quantum_Job__c (Master-Detail) │
│ QPU_Time_seconds__c       │      │ Certificate__c (Lookup)        │
│ Purpose__c                │      │ Assigned_Record_ID__c          │
└───────────────────────────┘      │ Assigned_To_ID__c              │
                                   │ Assignment_Index__c            │
┌───────────────────────────┐      │ Random_Value__c (bits consumed)│
│    Quantum_Provider__c    │      └────────────────────────────────┘
├───────────────────────────┤
│ Provider_Key__c           │      ┌────────────────────────────────┐
│ Provider_Class__c         │      │      Compliance_Event__c       │
│ API_Base_URL__c           │      ├────────────────────────────────┤
│ Auth_Endpoint__c          │      │ Event_Type__c (e.g.            │
│ Is_Active__c / Status__c  │      │  SETTINGS_CHANGED)             │
└─────────────┬─────────────┘      │ Actor__c / Severity__c         │
              │ MD                 │ Detail__c / Detail_Hash__c     │
              ▼                    │ Related_Job__c                 │
┌───────────────────────────┐      │ Related_Certificate__c         │
│     Quantum_Backend__c    │      └────────────────────────────────┘
├───────────────────────────┤
│ Backend_Key__c            │      ┌────────────────────────────────┐
│ Num_Qubits__c/Max_Shots__c│      │  Quantum_Settings__c (Protected │
│ Processor_Family/Revision │      │  Hierarchy Custom Setting)     │
│ Median gate/readout error │      ├────────────────────────────────┤
│ Avg_T1_us__c/Avg_T2_us__c │      │ IBM_API_Key__c / Instance_CRN  │
│ Queue_Length__c/Status__c │      │ Default_Backend__c/Default_Shots│
│ Noise_Source_Type__c      │      │ Use_Bell_Test__c/Use_Least_Busy│
│ Conditioning_Component__c │      │ Poll_Interval_Minutes__c       │
│ Health_Test_* fields      │      │ Integrity_Check_Hour__c        │
│ CHSH_* verification fields│      │ Compliance_Email__c            │
└───────────────────────────┘      └────────────────────────────────┘
```

Plus `Compliance_Control__mdt` (24 seed records mapping controls to ISO 27001 / SOC 2 / NIST 800-90B / GDPR / eIDAS) and the Platform Events `Quantum_Job_Complete__e` / `Quantum_Job_Failed__e`.

---

## Security Architecture

### API Key Storage — the Real Design and Its Tradeoff

The IBM API key is stored in a **Protected hierarchy custom setting field** (`Quantum_Settings__c.IBM_API_Key__c`), entered by the admin via the Setup tab UI. This is a deliberate choice for an unmanaged, zero-infrastructure distribution — Named/External Credentials cannot be pre-wired with a per-org secret in an unmanaged package without significant manual setup, and earlier versions of this document described a Named Credential design that was never built.

**Tradeoff, stated honestly:** the key is plaintext at rest in the org. Mitigations:

- The custom setting is **Protected** — invisible to ordinary users and the Setup UI of non-admins
- The key is **never returned to the client**: `SetupController.getSettings` exposes only a boolean `hasApiKey`
- The key is **never logged** (settings-change compliance events record which fields changed, never values)
- The key is only ever transmitted to IBM IAM over TLS during token exchange
- The IAM **bearer token** (not the key) is cached in the Platform Cache partition `local.QuantumFair` (50-minute TTL) with graceful fallback to a transaction-scoped static

Callouts are authorized by three Remote Site Settings (`IBM_IAM`, `IBM_Quantum_API`, `IBM_Resource_Controller`). Orgs requiring encrypted-at-rest secrets can layer Shield Platform Encryption or migrate the key to their own Named Credential.

### Authorization

- The custom permission **`QuantumFair_Administer`** — granted only in the `QuantumFair_Admin` permission set — gates every privileged `@AuraEnabled` method via `FeatureManagement.checkPermission()`: `saveSettings`, starting/stopping scheduled jobs, backend quantum verification, and compliance evidence export. The System Administrator profile alone is **denied**; admins must hold the permission set.
- All three permission sets grant `SetupController` class access and read on both Platform Events (required for any of the UI to function).
- Settings changes are logged to `Compliance_Event__c` as `SETTINGS_CHANGED` events (field names only, never the key value).

### Data Security

- **OWD = Private** on all custom objects — `Quantum_Job__c`, `Quantum_Provider__c`, `Compliance_Event__c` are Private; `Fairness_Certificate__c`, `Quantum_Assignment__c`, `Quantum_Backend__c` are master-detail children (Controlled by Parent, inheriting Private)
- `with sharing` on service classes; the poller/scheduler are deliberately documented `without sharing` (system maintenance of package-owned job records only)
- **CRUD/FLS enforced server-side**: controller reads use `WITH USER_MODE` or pass rows through `Security.stripInaccessible(AccessType.READABLE)` before building DTOs — Auditors never receive `Raw_Results__c`/`Debiased_Results__c` even though the DTO shape is shared
- Regular users receive read-only DTOs; no raw SObjects cross the Apex/LWC boundary
- No Salesforce data ever leaves the org (only circuit definitions go to IBM — no customer data in circuits)

### Integrity Verification

The certificate stores three SHA-256 hashes plus a chain:

1. **Raw bitstring hash** — hash of the exact measurement output from IBM
2. **Debiased hash** — hash of the post-processed random pool
3. **Assignment hash** — hash of the canonical assignment serialization (`index:recordId:assigneeId` lines sorted by index, joined `\n`)

An auditor can re-derive hash #3 from the certified pool by replaying the documented rejection-sampling rules, and verify hash #1 against IBM's job records (accessible via IBM API with the job ID). `IntegrityVerificationJob` re-hashes nightly and walks the certificate chain to its actual predecessor, setting `Tampered__c` on mismatch.

---

## Async Flow — End to End

```
User / Flow               Apex                     IBM Quantum
    │                      │                          │
    ├──Request────────────▶│ (invocable: no callouts) │
    │                      ├──Insert Quantum_Job__c   │
    │                      │  Status='Pending'         │
    │                      │  Assignment_Request__c=JSON│
    │◀── "Queued for       ├──Enqueue                  │
    │    submission" ──────│  QuantumSubmissionQueueable│
    │                      │                          │
    │  Submission Queueable│                          │
    │  (one job per exec)  ├──Build OpenQASM──┐       │
    │                      │◀─────────────────┘       │
    │                      ├──POST /v1/jobs──────────▶│
    │                      │◀─── { job_id } ──────────│
    │                      ├──Status='Submitted'       │
    │                      ├──Start poll chain, chain  │
    │                      │  to next pending job      │
    │                      │                          │
    │  Poll #1..5 (1 min)  ├──GET /v1/jobs/id────────▶│
    │  then 2,3,5,7 min    │◀─── status: Queued ──────│
    │  capped 10 min,      ├──Schedule next poll       │
    │  budget 6h           │  (transient errors retry) │
    │                      │                          │
    │  Poll #N             ├──GET /v1/jobs/id────────▶│
    │                      │◀─── status: Completed ───│
    │                      ├──GET /v1/jobs/id/results─▶│
    │                      │◀─── { bitstrings } ──────│
    │   JobProcessor       ├──FOR UPDATE idempotency   │
    │   (idempotent)       │  re-check                 │
    │                      ├──Parse + per-qubit debias │
    │                      ├──Validate (alpha=0.01,    │
    │                      │  CHSH 2σ margin)          │
    │                      ├──Create Certificate       │
    │                      ├──Assignment engine        │
    │                      │  (rejection sampling)     │
    │                      ├──Insert Quantum_Assignment__c
    │                      ├──Stamp Assignment_Hash__c │
    │                      ├──Publish Quantum_Job_Complete__e
    │                      │  (SaveResult checked)     │
    │                      ├──Enqueue ValidationRunner │
    │                      │  (SP 800-90B; can REVOKE) │
    │◀── Platform Event ───│                          │
    │    (empApi in LWC)   │                          │
```

---

## Package Structure

```
force-app/main/default/
├── classes/                         — flat directory, tests alongside sources
│   ├── CircuitBuilder.cls               — OpenQASM 3.0 generation (ISA-compliant)
│   ├── IBMQuantumAuth.cls               — IAM token exchange + Platform Cache
│   ├── IBMQuantumService.cls            — REST API client (submit, poll, results, backends)
│   ├── IBMQuantumProvider.cls           — QuantumProvider implementation for IBM
│   ├── IBMResponseParser.cls            — IBM response shape parsing
│   ├── QuantumSubmissionQueueable.cls   — async, chained job submission (callout-safe)
│   ├── JobPoller.cls                    — Queueable poll chain (backoff, transient retry)
│   ├── JobPollScheduler.cls             — Schedulable hop between polls
│   ├── JobProcessor.cls                 — idempotent completion processing
│   ├── JobSweeper.cls                   — scheduled safety net for stuck jobs
│   ├── ResultParser.cls                 — bitstring extraction + per-qubit von Neumann
│   ├── RandomnessValidator.cls          — statistical tests (alpha=0.01) + CHSH margin
│   ├── ValidationRunner.cls             — async SP 800-90B suite (can revoke)
│   ├── QuantumAssignmentEngine.cls      — rejection-sampled assignment algorithms
│   ├── QuantumRandomAssignment.cls      — @InvocableMethod for Flow (bulk-safe)
│   ├── FairnessCertificateService.cls   — certificate creation + hash chaining
│   ├── IntegrityVerificationJob.cls     — nightly certificate re-hash verification
│   ├── ComplianceEventLogger.cls        — audit event creation + hashing
│   ├── ComplianceDigestJob.cls          — daily hash digest email (06:00)
│   ├── ComplianceSummaryJob.cls         — aggregate compliance summary
│   ├── ComplianceEvidenceExporter.cls   — framework evidence JSON export
│   ├── ComplianceControlService.cls     — control-to-framework mapping queries
│   ├── SetupController.cls              — single LWC controller (permission-gated)
│   ├── QuantumProvider.cls              — provider interface
│   ├── QuantumProviderFactory.cls       — provider factory
│   ├── QuantumConsumer.cls              — extension interface (see Extensibility)
│   ├── QuantumException.cls             — package exception type
│   └── *_Test.cls / *Test.cls           — 30 test classes, ~480 test methods
│
├── lwc/                             — 22 components (see Layer 5)
├── objects/                         — Quantum_Job__c, Fairness_Certificate__c,
│                                      Quantum_Assignment__c, Quantum_Provider__c,
│                                      Quantum_Backend__c, Compliance_Event__c,
│                                      Quantum_Settings__c, Compliance_Control__mdt,
│                                      Quantum_Job_Complete__e, Quantum_Job_Failed__e
├── customMetadata/                  — 24 Compliance_Control seed records
├── customPermissions/               — QuantumFair_Administer
├── remoteSiteSettings/              — IBM_IAM, IBM_Quantum_API, IBM_Resource_Controller
├── cachePartitions/                 — QuantumFair (IAM bearer token cache)
├── permissionsets/                  — QuantumFair_Admin, QuantumFair_User, QuantumFair_Auditor
├── applications/ + tabs/            — QuantumFair app + object tabs
├── flexipages/                      — app page, utility bar, record pages
├── notificationtypes/               — Quantum_Job_Notification
├── layouts/                         — page layouts for all custom objects
└── flows/                           — sample flows (lead round robin, case routing,
                                       opportunity review, account rebalance, generic)
```

---

## Circuit Types

### 1. Standard QRNG (Default)

**Purpose:** Fast generation of quantum random bits
**Circuit:** Hadamard on each qubit → measure
**Qubits:** 8–127 (configurable, more qubits = more bits per shot)
**Shots:** 1024–8192 (configurable; oversized qubit×shot combinations are rejected at submission)
**Output:** `qubits × shots` random bits
**Certification level:** Standard (statistical validation only)

```
ISA decomposition (per qubit):
  rz(π/2) → sx → rz(π/2) → measure
```

### 2. Bell-Test QRNG (Strong Certification)

**Purpose:** Randomness with evidence consistent with quantum origin via CHSH inequality violation
**Circuit:** Bell pairs (H + ECR) → complementary basis measurement
**Qubits:** Pairs (2N qubits for N Bell pairs)
**Shots:** 4096+ (needed for CHSH statistical significance)
**Output:** Fewer random bits (only Alice-side qubits feed the pool; correlated bits are excluded), but with a physics-backed significance test
**Certification level:** Bell-certified — requires (S − 2.0) > 2σ_S, i.e. the classical bound violated by at least two standard errors

```
ISA decomposition (per Bell pair):
  Qubit A: rz(π/2) → sx → rz(π/2)          [Hadamard]
  Qubit B: (identity)
  Entangle: ecr $A, $B                       [native 2Q gate]
  Basis choice: rz rotation on each
  Measure both
```

The CHSH S-value is computed from correlations across four measurement basis combinations. S > 2 with statistical significance is impossible to explain classically under the test's assumptions — the certificate records the S-value, its standard error, and the margin.

### 3. Randomness Expansion (Future)

For orgs needing high-volume randomness without burning IBM minutes on every request: use a single quantum seed (from circuit type 1 or 2) to initialize a CSPRNG (ChaCha20 or similar) in Apex. The quantum seed is certified; derived values are cryptographically random. Certificate notes the expansion method.

---

## Governor Limit Budget

| Operation                    | Limit           | Usage                                                                          |
| ---------------------------- | --------------- | ------------------------------------------------------------------------------ |
| Callouts per transaction     | 100             | Submission queueable: ≤5; poller: 2; sweeper: ~14 worst case                   |
| Callout timeout              | 120s            | IBM API responds in <5s typically                                              |
| Heap size (async)            | 12 MB           | Sweeper bounded to 3 completions/sweep (payloads can exceed 1 MB)              |
| Queueable chain depth        | n/a             | Poll chain hops through Schedulable (no depth limit applies)                   |
| Scheduled jobs per org       | 100             | One CronTrigger per in-flight poll; schedule failures fall back to the sweeper |
| Platform Events published/tx | 250             | 1 per job completion/failure (SaveResults checked)                             |
| SOQL queries per tx          | 100             | ~5 per poll cycle                                                              |
| DML rows per tx              | 10,000          | Certificate + assignments well within                                          |
| Platform Cache               | partition-based | `local.QuantumFair` partition; bearer token ≈ 2 KB                             |

---

## Extensibility Points

### Apex Interface — `QuantumConsumer`

```apex
public interface QuantumConsumer {
    void onRandomnessReady(Id certificateId, List<String> randomBits);
    void onRandomnessFailed(Id jobId, String errorMessage);
}
```

Since QuantumFair deploys as source, developers can implement this interface for custom randomness use cases beyond the built-in assignment types. Note: automatic dispatch to registered consumers is not yet wired — today the interface is a contract for custom code that subscribes to the Platform Events below.

### Platform Events — `Quantum_Job_Complete__e` / `Quantum_Job_Failed__e`

Any org automation (Flow, Apex trigger, external system via CometD) can listen for these events. `Quantum_Job_Complete__e` fields:

- `Job_Id__c` — `Quantum_Job__c` record ID
- `Certificate_Id__c` — `Fairness_Certificate__c` record ID
- `Num_Random_Bits__c` — Number of debiased random bits available

`Quantum_Job_Failed__e` carries `Job_Id__c` and `Error_Message__c` — and is also published when SP 800-90B extended validation revokes a certificate.

### Flow Builder Integration

The `QuantumRandomAssignment` invocable action can be used in:

- Record-Triggered Flows (e.g., auto-assign new leads) — including bulk inserts, since submission is async
- Screen Flows (e.g., admin-initiated audit sampling)
- Scheduled Flows (e.g., weekly fair rotation)
- Platform Event–Triggered Flows (chained from `Quantum_Job_Complete__e`)

---

## Testing on IBM Quantum

**Development backend:** `ibm_kingston` (Heron r2, 156 qubits, available on Open Plan)

**Estimated IBM minutes for development:**

| Phase                              | Minutes     | Notes                                          |
| ---------------------------------- | ----------- | ---------------------------------------------- |
| Circuit validation (standard QRNG) | ~2 min      | Simple H+measure circuits                      |
| Circuit validation (Bell-test)     | ~3 min      | Entangled pair circuits                        |
| Statistical validation tuning      | ~5 min      | Calibrate pass/fail thresholds                 |
| End-to-end integration tests       | ~5 min      | Full Salesforce → IBM → results flow           |
| **Total development**              | **~15 min** | QRNG circuits are trivial for quantum hardware |

---

## Deployment

### Distribution — Unmanaged / Open Source

QuantumFair ships as an **unmanaged package / source deploy** under Apache-2.0. There is no namespace (the former `OpenSF` namespace was removed) and no InstallHandler (unsupported for unmanaged packages) — background-job scheduling is automated in-app:

- Saving a working API key auto-schedules `JobSweeper` and `IntegrityVerificationJob`
- Saving a compliance email auto-schedules `ComplianceDigestJob` (daily 06:00 org time); clearing it unschedules the digest

An AppExchange listing is planned. **Editions:** Enterprise, Unlimited, Developer. **Requirements:** IBM Quantum account (free Open Plan is sufficient).

### Post-Install Setup (Admin)

1. Deploy the source (`sf project deploy start`) or install the unmanaged package
2. Assign the `QuantumFair_Admin` permission set to the admin user (required — privileged actions check the `QuantumFair_Administer` custom permission, which only this permission set grants)
3. Navigate to the QuantumFair Setup tab (`/lightning/n/QuantumFair`)
4. Enter the IBM Quantum API key and save (sweeper + integrity job schedule automatically)
5. Optionally set a compliance email (daily digest schedules automatically)
6. Test the connection from the Setup tab
7. Assign `QuantumFair_User` / `QuantumFair_Auditor` to other users

### For Developers / Contributors

```bash
git clone https://github.com/OpenSystemsFoundation/open-qrng.git
cd open-qrng
sf org create scratch -f config/project-scratch-def.json -a qrng-dev
sf project deploy start
sf org assign permset -n QuantumFair_Admin
sf org open
```

---

## License

Apache-2.0 — See [LICENSE](LICENSE)
