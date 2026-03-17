# QuantumFair — Architecture

**Open-Source Quantum Random Number Generation for Salesforce**
Apache-2.0 | Free on AppExchange | Zero Infrastructure Cost

---

## Overview

QuantumFair is a managed Salesforce package that provides **certified quantum random number generation** (QRNG) for fair, auditable business process randomization. It uses real quantum hardware to generate true randomness — provable by the laws of physics — and creates immutable fairness certificates linked to every assignment.

**Core principle:** The app that uses quantum mechanics to prove your business decisions are fair.

### Constraints

| Constraint                  | Decision                                                                       |
| --------------------------- | ------------------------------------------------------------------------------ |
| No external servers         | Everything runs on Salesforce — Apex, LWC, Platform Events, Custom Objects     |
| Zero cost to maintain       | No Heroku, no AWS, no middleware. Apex calls IBM Quantum REST API directly     |
| BYOQ                        | Each org provides their own IBM Quantum API key via Named Credentials          |
| Open-source                 | Apache-2.0 license, full source on GitHub, free AppExchange listing            |
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
│  │  Quantum_Job__c  │  Fairness_Certificate__c  │  QRNG_Log__c │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │              Named Credential + External Credential           │  │
│  │              (IBM Quantum API Key — per-org, encrypted)       │  │
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

### Circuit Builder — `QRNGCircuitBuilder.cls`

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

For Bell-test certification (CHSH inequality violation proves quantum origin), the circuit creates entangled pairs and measures in complementary bases. The decomposition into native gates is still straightforward — `ecr` or `cz` gates for entanglement, `rz`/`sx` for basis rotations.

### Backend Configuration — `QRNGBackendConfig.cls`

Queries the IBM `/backends/{name}/configuration` endpoint to retrieve:

- Native gate set (validates our decomposition)
- Qubit coupling map (ensures we use connected physical qubits)
- Number of qubits available

Caches configuration in `QRNG_Backend_Config__c` (Protected Custom Metadata Type) to avoid repeated callouts. Refreshed on-demand or via scheduled job.

---

## Layer 2 — IBM Quantum Integration (Apex)

### Authentication Flow

```
┌──────────┐     ┌──────────────┐     ┌─────────────────────┐
│ Admin    │────▶│ Named        │────▶│ IBM IAM Token       │
│ Setup    │     │ Credential   │     │ Exchange            │
│ (one     │     │ (stores API  │     │ POST iam.cloud.ibm  │
│  time)   │     │  key encrypted│    │ .com/identity/token │
└──────────┘     └──────────────┘     └─────────────────────┘
                                              │
                                              ▼
                                      Bearer token cached
                                      in Org Cache (1hr TTL)
```

**`IBMQuantumAuth.cls`**

- Reads IBM API key from Named Credential (never touches raw key in Apex)
- Exchanges for IAM Bearer token via `POST https://iam.cloud.ibm.com/identity/token`
- Caches Bearer token in **Platform Cache (Org partition)** with 50-minute TTL (token valid 60 min)
- Automatically refreshes on expiry

**Named Credential setup** (packaged metadata):

```xml
<!-- ExternalCredential: IBM_Quantum -->
<!-- Named Credential: IBM_Quantum_Runtime -->
<!-- Endpoint: https://quantum.cloud.ibm.com -->
<!-- Auth: Custom header via External Credential -->
```

Post-install, the admin populates their IBM API key as an Authentication Parameter on the External Credential's Permission Set Mapping. The key is stored encrypted by Salesforce. Package Apex references the Named Credential by name.

### Job Submission — `IBMQuantumService.cls`

```
Responsibility: Submit circuits, poll status, retrieve results
Protocol:       IBM Qiskit Runtime REST API v1
Base URL:       https://quantum.cloud.ibm.com/api/v1
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

### Async Polling — Queueable Chain

```
┌───────────┐     ┌──────────────┐     ┌──────────────┐
│ Submit    │────▶│ Queueable    │────▶│ Queueable    │──▶ ...
│ Job       │     │ Poll #1      │     │ Poll #2      │
│ (Apex)    │     │ GET /jobs/id │     │ GET /jobs/id │
└───────────┘     └──────┬───────┘     └──────┬───────┘
                         │                     │
                    status:Queued          status:Running
                                               │
                                          status:Completed
                                               │
                                               ▼
                                     ┌─────────────────┐
                                     │ Platform Event   │
                                     │ QRNG_Complete__e │
                                     │ + Process Results│
                                     └─────────────────┘
```

**`QRNGJobPoller.cls` (implements Queueable, Database.AllowsCallouts)**

1. `GET /v1/jobs/{job_id}` — check `state.status`
2. If `Queued` or `Running` → re-enqueue self with delay (exponential backoff: 5s, 10s, 20s, 40s... capped at 60s)
3. If `Completed` → `GET /v1/jobs/{job_id}/results` → parse bitstrings → publish `QRNG_Complete__e`
4. If `Failed` → update `Quantum_Job__c` with error → publish `QRNG_Failed__e`
5. Send Custom Notification to requesting user on completion/failure

**Governor limit safety:**

- Each Queueable execution = 1 transaction with fresh limits
- No depth limit on chaining — can poll indefinitely
- Single callout per poll (well within 100 callout limit)
- Typical quantum job: 10s–120s queue + 2s–30s execution = 3–10 poll cycles

---

## Layer 3 — Randomness Processing & Certification (Apex)

### Result Parser — `QRNGResultParser.cls`

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
2. Concatenates into a single random bit pool
3. Applies **von Neumann debiasing** (pairs of bits: 01→0, 10→1, 00/11→discard) to correct for any hardware bias
4. Stores raw + debiased bits in `Quantum_Job__c`

### Statistical Validation — `QRNGValidator.cls`

Runs lightweight randomness checks before certifying:

| Test                                | What It Checks                          | Pass Criteria                   |
| ----------------------------------- | --------------------------------------- | ------------------------------- |
| **Frequency (monobit)**             | Proportion of 0s vs 1s                  | Within 2σ of 50%                |
| **Runs test**                       | Length of consecutive identical bits    | Consistent with random sequence |
| **Chi-squared on distribution**     | Uniformity of N-bit blocks              | p-value > 0.01                  |
| **CHSH violation** (Bell-test mode) | S parameter from entangled measurements | S > 2.0 (classical limit)       |

If validation fails, the job is flagged and the certificate is not issued. The user is notified to retry (likely hardware noise issue).

### Fairness Certificate — `FairnessCertificateService.cls`

On successful validation, creates a `Fairness_Certificate__c` record:

| Field                        | Type             | Description                                     |
| ---------------------------- | ---------------- | ----------------------------------------------- |
| `Certificate_ID__c`          | Auto-Number      | Unique public identifier                        |
| `Quantum_Job__c`             | Lookup           | Link to the IBM job record                      |
| `IBM_Job_ID__c`              | Text             | IBM's job ID (externally verifiable)            |
| `Backend__c`                 | Text             | QPU used (e.g., `ibm_kingston`)                 |
| `Circuit_QASM__c`            | Long Text        | Exact OpenQASM submitted                        |
| `Raw_Bitstring_Hash__c`      | Text             | SHA-256 hash of raw measurement data            |
| `Debiased_Bitstring_Hash__c` | Text             | SHA-256 hash of processed random values         |
| `Assignment_Hash__c`         | Text             | SHA-256 hash of the resulting assignment        |
| `Validation_Results__c`      | Long Text (JSON) | Statistical test results                        |
| `CHSH_S_Value__c`            | Number           | Bell-test S value (if applicable)               |
| `Created_By_User__c`         | Lookup(User)     | Who requested the random assignment             |
| `Purpose__c`                 | Text             | Description of what the randomness was used for |
| `Status__c`                  | Picklist         | Certified / Failed / Pending                    |

**Audit chain:** Certificate → links to → Quantum_Job**c (with IBM job ID) → links to → assigned records via `QRNG_Assignment**c` junction object. Any auditor can verify: circuit was run on IBM hardware (job ID verifiable via IBM API), measurements are statistically random, and the assignment follows deterministically from the measurements.

---

## Layer 4 — Assignment Engine (Apex)

### Random Assignment — `QuantumAssignmentEngine.cls`

Converts quantum random bits into fair assignments for common Salesforce use cases:

**Uniform distribution** (e.g., round-robin lead assignment):

```
Input:  50 leads, 5 reps, quantum random bits
Method: For each lead, consume ceil(log2(5)) random bits → mod 5 → assign to rep
Output: Assignment map with certificate link
```

**Weighted distribution** (e.g., leads weighted by rep capacity):

```
Input:  Items, assignees with weights, quantum random bits
Method: CDF-based selection using quantum random values
Output: Assignment respecting weight proportions
```

**Subset selection** (e.g., audit sampling):

```
Input:  Population of N records, sample size K, quantum random bits
Method: Fisher-Yates shuffle using quantum random bits → take first K
Output: Unbiased sample with certificate
```

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
- `purpose` — Description for the fairness certificate
- `useBellTest` — Whether to use stronger Bell-test certification

This makes QuantumFair usable from **Flow Builder** with zero code — admins can drop quantum random assignment into any automation.

---

## Layer 5 — LWC Components

All components are hand-rolled using the latest LWC features (Spring '26). No third-party dependencies. Everything renders natively in Lightning.

### Component Map

```
quantumfair/
├── quantumFairApp              ← Main app container (tab/utility bar)
├── qrngSetup                   ← Admin config: Named Credential status, backend picker
├── qrngRequestForm             ← Request a random assignment (Flow-embeddable)
├── qrngJobMonitor              ← Real-time job status via empApi (Platform Events)
├── qrngCircuitVisualizer       ← Canvas 2D rendering of the quantum circuit
├── qrngResultsVisualizer       ← Bitstring distribution chart (Canvas 2D bar chart)
├── qrngFairnessCertificate     ← Certificate viewer with validation details
├── qrngAssignmentTable         ← Results table with record links + certificate
├── qrngAuditTrail              ← Timeline of all QRNG jobs with certificates
└── qrngBellTestIndicator       ← CHSH violation gauge (proves quantum origin)
```

### `qrngCircuitVisualizer` — Hand-Rolled Circuit Diagram (Canvas 2D)

Renders a visual quantum circuit diagram directly in LWC using the Canvas 2D API. No external library.

```
Design:
  ┌───┐ ┌─┐
  ┤ H ├─┤M├──── bit[0]
  └───┘ └─┘
  ┌───┐ ┌─┐
  ┤ H ├─┤M├──── bit[1]
  └───┘ └─┘
  ┌───┐ ┌─┐
  ┤ H ├─┤M├──── bit[2]
  └───┘ └─┘
```

**Implementation approach:**

- `<canvas>` element in the LWC template
- `renderedCallback()` draws the circuit using `ctx.fillRect()`, `ctx.strokeRect()`, `ctx.fillText()`, `ctx.beginPath()`/`ctx.lineTo()`
- Dynamically scales to the number of qubits in the circuit
- Animates during job execution: qubits pulse, measurement gates flash
- Works under LWS (Canvas 2D basic operations are not distorted)

### `qrngResultsVisualizer` — Measurement Distribution Chart (Canvas 2D)

Hand-rolled bar chart showing the distribution of measurement outcomes:

- X-axis: bitstring values (e.g., `000`, `001`, ..., `111`)
- Y-axis: count/frequency
- Ideal uniform distribution shown as a dashed overlay line
- Color-coded bars: green = within expected variance, amber = marginal, red = outlier
- Tooltip on hover showing exact count and percentage
- Responsive resize via `ResizeObserver`

For large qubit counts (>6 bits = 64+ bars), switches to a **histogram binning** view or top-N display.

### `qrngJobMonitor` — Real-Time Status via Platform Events

```javascript
// Subscribe to Platform Events via empApi
import { subscribe, unsubscribe } from 'lightning/empApi';

// Channel: /event/QRNG_Complete__e
// On receive: update job status, trigger results fetch, animate UI
```

**States rendered:**

1. **Submitted** — circuit diagram shown, pulsing animation
2. **Queued** — position in IBM queue (from job metadata), estimated wait
3. **Running** — execution progress indicator
4. **Completed** — results visualization fades in, certificate generated
5. **Failed** — error details with retry action

No polling from the client. The Queueable chain publishes Platform Events; empApi delivers them to the LWC in real time.

### `qrngFairnessCertificate` — Certificate Viewer

A visually distinct, "document-style" LWC component that renders the Fairness Certificate:

- Certificate ID and QR-code-style visual hash (generated from SHA-256 via Canvas 2D pixel art)
- IBM Job ID (clickable link to IBM Quantum dashboard if user has access)
- Backend name and circuit parameters
- Statistical validation results with pass/fail badges
- CHSH S-value gauge (for Bell-test certificates): S > 2.0 = quantum certified
- Linked assignment records (clickable navigation)
- "Verify" button: re-hashes the stored data and confirms integrity

### `qrngBellTestIndicator` — CHSH Gauge (CSS-only)

A pure CSS gauge component (no Canvas, no JS animation library):

```
CSS approach:
- Circular gauge via conic-gradient()
- Needle rotation via CSS custom property --chsh-value
- Classical limit (S=2) marked with a red line
- Quantum region (S>2) shaded in gradient
- Value set via CSS custom property from JS:
  this.template.querySelector('.gauge')
      .style.setProperty('--chsh-value', sValue);
```

Lightweight, accessible, works perfectly under LWS shadow DOM with CSS custom properties crossing the boundary.

### `qrngSetup` — Admin Configuration Panel

- **Connection status**: Tests Named Credential by calling IBM `/backends` endpoint
- **Backend picker**: Lists available QPUs from the customer's IBM account, shows status (online/maintenance), qubit count, queue depth
- **Default settings**: Default shots per circuit, preferred backend, Bell-test on/off
- **Usage dashboard**: Number of QRNG jobs run, certificates issued, IBM minutes consumed (from job metadata)

---

## Data Model

```
┌─────────────────────┐     ┌──────────────────────────┐
│   Quantum_Job__c    │     │ Fairness_Certificate__c  │
├─────────────────────┤     ├──────────────────────────┤
│ IBM_Job_ID__c       │◀────│ Quantum_Job__c (Lookup)  │
│ Backend__c          │     │ Certificate_ID__c        │
│ Status__c           │     │ IBM_Job_ID__c            │
│ Circuit_QASM__c     │     │ Raw_Bitstring_Hash__c    │
│ Shots__c            │     │ Debiased_Hash__c         │
│ Num_Qubits__c       │     │ Assignment_Hash__c       │
│ Raw_Results__c      │     │ Validation_Results__c    │
│ Debiased_Results__c │     │ CHSH_S_Value__c          │
│ Submitted_At__c     │     │ Purpose__c               │
│ Completed_At__c     │     │ Status__c                │
│ Requested_By__c     │     │ Created_By_User__c       │
│ Error_Message__c    │     └──────────────────────────┘
│ Execution_Time_ms__c│
│ Queue_Time_ms__c    │
└─────────────────────┘
         │
         │ 1:N
         ▼
┌─────────────────────────┐
│  QRNG_Assignment__c     │
├─────────────────────────┤
│ Quantum_Job__c (Lookup) │
│ Certificate__c (Lookup) │
│ Assigned_Record_ID__c   │  ← Polymorphic: any SObject
│ Assigned_To_ID__c       │  ← User or Queue
│ Assignment_Index__c     │  ← Position in random sequence
│ Random_Value__c         │  ← The quantum random bits used
└─────────────────────────┘

┌─────────────────────────┐
│ QRNG_Backend_Config__mdt│  ← Protected Custom Metadata
├─────────────────────────┤
│ Backend_Name__c         │
│ Native_Gates__c         │
│ Coupling_Map__c         │
│ Num_Qubits__c           │
│ Last_Refreshed__c       │
└─────────────────────────┘
```

---

## Security Architecture

### API Key Protection

```
Layer 1: External Credential (encrypted at rest by Salesforce)
   └─▶ Permission Set Mapping (only assigned users/profiles can access)
       └─▶ Named Credential (Apex references by name, never sees raw key)
           └─▶ IAM Bearer Token (cached in Platform Cache, 50min TTL)
               └─▶ IBM API calls use Bearer token only
```

- Raw IBM API key is **never** in Apex code, custom settings, or logs
- Bearer token in Platform Cache is org-scoped and ephemeral
- Named Credential is package-protected metadata — subscriber admins control access via Permission Sets

### Data Security

- `Quantum_Job__c` and `Fairness_Certificate__c` have **OWD = Private** with sharing rules
- `with sharing` enforced on all service classes
- Raw quantum measurement data stored as hashes on certificates — full data on job records (restricted access)
- No Salesforce data ever leaves the org (only circuit definitions go to IBM — no customer data in circuits)

### Integrity Verification

The certificate stores three SHA-256 hashes:

1. **Raw bitstring hash** — hash of the exact measurement output from IBM
2. **Debiased hash** — hash of the post-processed random values
3. **Assignment hash** — hash of the final assignment mapping

An auditor can re-derive hash #3 from hash #2 by replaying the deterministic assignment algorithm, and verify hash #1 against IBM's job records (accessible via IBM API with the job ID).

---

## Async Flow — End to End

```
User clicks               Apex                    IBM Quantum
"Generate"            (synchronous)                 (async)
    │                      │                          │
    ├──Request────────────▶│                          │
    │                      ├──Build OpenQASM──┐       │
    │                      │◀─────────────────┘       │
    │                      ├──Create Quantum_Job__c   │
    │                      ├──POST /v1/jobs──────────▶│
    │                      │◀─── { job_id } ──────────│
    │                      ├──Enqueue Poller           │
    │◀── "Submitted" ──────│                          │
    │                      │                          │
    │    Queueable #1      │                          │
    │                      ├──GET /v1/jobs/id────────▶│
    │                      │◀─── status: Queued ──────│
    │                      ├──Re-enqueue (backoff)     │
    │                      │                          │
    │    Queueable #N      │                          │
    │                      ├──GET /v1/jobs/id────────▶│
    │                      │◀─── status: Completed ───│
    │                      ├──GET /v1/jobs/id/results─▶│
    │                      │◀─── { bitstrings } ──────│
    │                      ├──Parse + Debias           │
    │                      ├──Validate (stats tests)   │
    │                      ├──Create Certificate__c    │
    │                      ├──Run Assignment Engine     │
    │                      ├──Create Assignment__c recs │
    │                      ├──Publish QRNG_Complete__e  │
    │                      ├──Send Custom Notification  │
    │                      │                          │
    │◀── Platform Event ───│                          │
    │    (empApi in LWC)   │                          │
    │                      │                          │
    ├──Fetch results───────▶│                          │
    │◀── Certificate +     │                          │
    │    Assignments        │                          │
```

---

## Package Structure

```
force-app/main/default/
├── classes/
│   ├── QRNGCircuitBuilder.cls          — OpenQASM 3.0 generation (ISA-compliant)
│   ├── QRNGCircuitBuilder_Test.cls
│   ├── IBMQuantumAuth.cls              — IAM token exchange + caching
│   ├── IBMQuantumAuth_Test.cls
│   ├── IBMQuantumService.cls           — REST API client (submit, poll, results)
│   ├── IBMQuantumService_Test.cls
│   ├── QRNGJobPoller.cls               — Queueable chain for async polling
│   ├── QRNGJobPoller_Test.cls
│   ├── QRNGResultParser.cls            — Bitstring extraction + von Neumann debiasing
│   ├── QRNGResultParser_Test.cls
│   ├── QRNGValidator.cls               — Statistical randomness tests
│   ├── QRNGValidator_Test.cls
│   ├── FairnessCertificateService.cls  — Certificate creation + hashing
│   ├── FairnessCertificateService_Test.cls
│   ├── QuantumAssignmentEngine.cls     — Random assignment algorithms
│   ├── QuantumAssignmentEngine_Test.cls
│   ├── QuantumRandomAssignment.cls     — @InvocableMethod for Flow Builder
│   ├── QuantumRandomAssignment_Test.cls
│   ├── QRNGSetupController.cls         — LWC controller for admin setup
│   └── QRNGSetupController_Test.cls
│
├── lwc/
│   ├── quantumFairApp/                 — Main app shell
│   ├── qrngSetup/                      — Admin config panel
│   ├── qrngRequestForm/               — Assignment request form
│   ├── qrngJobMonitor/                — Real-time job status (empApi)
│   ├── qrngCircuitVisualizer/         — Canvas 2D circuit diagram
│   ├── qrngResultsVisualizer/         — Canvas 2D measurement charts
│   ├── qrngFairnessCertificate/       — Certificate document view
│   ├── qrngAssignmentTable/           — Results table
│   ├── qrngAuditTrail/               — Historical job/certificate timeline
│   └── qrngBellTestIndicator/        — CSS gauge for CHSH value
│
├── objects/
│   ├── Quantum_Job__c/
│   ├── Fairness_Certificate__c/
│   ├── QRNG_Assignment__c/
│   └── QRNG_Backend_Config__mdt/
│
├── platformEventChannelMembers/
│   ├── QRNG_Complete__e/
│   └── QRNG_Failed__e/
│
├── customNotificationTypes/
│   └── QRNG_Job_Notification.notiftype
│
├── namedCredentials/
│   ├── IBM_Quantum_Runtime.namedCredential-meta.xml
│   └── IBM_Quantum.externalCredential-meta.xml
│
├── permissionsets/
│   ├── QuantumFair_Admin.permissionset
│   └── QuantumFair_User.permissionset
│
├── tabs/
│   └── QuantumFair.tab
│
├── flexipages/
│   └── QuantumFair_App_Page.flexipage
│
└── flows/
    └── Quantum_Random_Lead_Assignment.flow  — Sample flow using the invocable action
```

---

## Circuit Types

### 1. Standard QRNG (Default)

**Purpose:** Fast generation of quantum random bits
**Circuit:** Hadamard on each qubit → measure
**Qubits:** 8–127 (configurable, more qubits = more bits per shot)
**Shots:** 1024–8192 (configurable)
**Output:** `qubits × shots` random bits
**Certification level:** Standard (statistical validation only)

```
ISA decomposition (per qubit):
  rz(π/2) → sx → rz(π/2) → measure
```

### 2. Bell-Test QRNG (Strong Certification)

**Purpose:** Provably quantum randomness via CHSH inequality violation
**Circuit:** Bell pairs (H + CNOT) → random basis measurement
**Qubits:** Pairs (2N qubits for N Bell pairs)
**Shots:** 4096+ (need statistical significance for CHSH)
**Output:** Fewer random bits, but with physics-backed proof of quantum origin
**Certification level:** Bell-certified (CHSH S > 2.0)

```
ISA decomposition (per Bell pair):
  Qubit A: rz(π/2) → sx → rz(π/2)          [Hadamard]
  Qubit B: (identity)
  Entangle: ecr $A, $B                       [native 2Q gate]
  Basis choice: random rz rotation on each
  Measure both
```

The CHSH S-value is computed from correlations across four measurement basis combinations. S > 2 is impossible classically — it proves the randomness came from quantum mechanics.

### 3. Randomness Expansion (Future)

For orgs needing high-volume randomness without burning IBM minutes on every request: use a single quantum seed (from circuit type 1 or 2) to initialize a CSPRNG (ChaCha20 or similar) in Apex. The quantum seed is certified; derived values are cryptographically random. Certificate notes the expansion method.

---

## Governor Limit Budget

| Operation                    | Limit           | Usage                                      |
| ---------------------------- | --------------- | ------------------------------------------ |
| Callouts per transaction     | 100             | 2 per poll cycle (auth check + status)     |
| Callout timeout              | 120s            | IBM API responds in <5s typically          |
| Heap size (async)            | 12 MB           | Results for 8192 shots × 127 qubits ≈ 1 MB |
| Queueable chain depth        | Unlimited       | ~3–10 polls per job                        |
| Platform Events published/tx | 250             | 1 per job completion                       |
| SOQL queries per tx          | 100             | ~5 per poll cycle                          |
| DML rows per tx              | 10,000          | Certificate + assignments well within      |
| Platform Cache (Org)         | 10 MB (default) | Bearer token ≈ 2 KB                        |

---

## Extensibility Points

### Apex Interface — `QRNGConsumer`

```apex
public interface QRNGConsumer {
    void onRandomnessReady(Id certificateId, List<String> randomBits);
    void onRandomnessFailed(Id jobId, String errorMessage);
}
```

Developers in the subscriber org can implement this interface and register their class in a Custom Metadata record. The assignment engine calls all registered consumers when randomness is ready — enabling custom use cases beyond the built-in assignment types.

### Platform Event — `QRNG_Complete__e`

Any subscriber-org automation (Flow, Apex trigger, external system via CometD) can listen for this event and react to completed QRNG jobs. Fields:

- `Job_Id__c` — Quantum_Job\_\_c record ID
- `Certificate_Id__c` — Fairness_Certificate\_\_c record ID
- `Num_Random_Bits__c` — Number of debiased random bits available
- `Status__c` — Certified / Failed

### Flow Builder Integration

The `QuantumRandomAssignment` invocable action can be used in:

- Record-Triggered Flows (e.g., auto-assign new leads)
- Screen Flows (e.g., admin-initiated audit sampling)
- Scheduled Flows (e.g., weekly fair rotation)
- Platform Event-Triggered Flows (chained from QRNG_Complete\_\_e)

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

The remaining budget (185 min) is available for the QuantumPareto optimizer (C₁) or future features.

---

## Deployment

### AppExchange Listing

- **Price:** Free
- **License:** Apache-2.0 (source on GitHub)
- **Category:** Utilities / Data Quality
- **Editions:** Enterprise, Unlimited, Developer
- **Requirements:** IBM Quantum account (free Open Plan is sufficient)

### Post-Install Setup (Admin)

1. Assign `QuantumFair_Admin` permission set to admin user
2. Navigate to QuantumFair Setup tab
3. Enter IBM Quantum API key into the External Credential (guided wizard in LWC)
4. Select preferred backend (wizard shows available QPUs)
5. Run test circuit (1 qubit, 100 shots) to verify connectivity
6. Assign `QuantumFair_User` permission set to users who can request random assignments

### For Developers / Contributors

```bash
git clone https://github.com/{org}/open-qrng.git
cd open-qrng
sf org create scratch -f config/project-scratch-def.json -a qrng-dev
sf project deploy start
sf org assign permset -n QuantumFair_Admin
sf org open
```

---

## License

Apache-2.0 — See [LICENSE](LICENSE)
