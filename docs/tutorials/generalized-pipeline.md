# The Generalized QRNG Pipeline

How to go from "I need a fair random outcome" to a certified result — the end-to-end formula that every domain tutorial in this repository follows.

## The Formula

```
Problem(N choices, K selections)
  → qubits = max(⌈log₂(N)⌉, default 8)
  → circuit(qubits, shots) + optional CHSH witness
  → raw bitstrings
  → von Neumann debias
  → validate (Frequency, Runs, Chi-Squared)
  → map to domain (modular reduction or Fisher-Yates)
  → certificate (hashes, tests, CHSH S-value, result)
```

Each step is explained below, with references to the Apex classes that implement it.

---

## Step 1 — Problem Definition and Parameter Mapping

The customer defines the decision space:

| Problem Shape                               | Example                             | Assignment Type |
| ------------------------------------------- | ----------------------------------- | --------------- |
| Assign N records to M assignees equally     | 50 leads → 5 reps                   | `Uniform`       |
| Assign N records to M assignees by capacity | 50 leads → 5 reps weighted by quota | `Weighted`      |
| Select K records from a pool of N           | 10 deals from 500 for audit         | `Subset`        |

**Qubit count.** QuantumFair defaults to **8 qubits** (configurable via `Quantum_Settings__c.Default_Qubits__c` or per-request). The assignment engine consumes `⌈log₂(M)⌉` debiased bits per assignment decision, where M is the number of assignees or the population size. Eight qubits at 1024 shots produces 8,192 raw bits — after von Neumann debiasing (~25% survival), roughly 2,048 clean bits, enough for hundreds of individual assignments from a single circuit execution.

> **Why not derive qubits from the problem size?** You could set qubits = `⌈log₂(N)⌉`, but in practice it is more efficient to run a fixed qubit count with many shots and draw from the resulting bit pool. A single 8-qubit, 1024-shot circuit produces enough randomness for most Salesforce use cases. The qubit count matters more for bits-per-shot throughput than for matching the problem domain.

**Shot count.** Default is **1024 shots** (configurable via `Quantum_Settings__c.Default_Shots__c`). More shots means more raw bits and stronger statistical validation. The tension: for a single random selection you technically only need one shot, but proving the source is random requires many samples.

**Recommended minimums:**

| Use Case                      | Minimum Shots | Rationale                                                  |
| ----------------------------- | ------------- | ---------------------------------------------------------- |
| Single assignment             | 1024          | Enough for statistical validation                          |
| Subset selection (K < 50)     | 1024          | Bit pool covers Fisher-Yates needs                         |
| Large-scale assignment (100+) | 4096          | Debiasing loss requires deeper pool                        |
| Bell-test certification       | 4096+         | CHSH needs statistical significance across 4 basis configs |

**Implementation:** `QuantumRandomAssignment.cls` (invocable action entry point) and `CircuitBuilder.cls` (circuit generation).

---

## Step 2 — Quantum Execution

QuantumFair generates ISA-compliant OpenQASM 3.0 directly in Apex — no Python, no Qiskit, no middleware. The Hadamard gate decomposes trivially into IBM's native gate set:

```
H = Rz(π/2) → SX → Rz(π/2)
```

### Standard QRNG Circuit

Each qubit is placed in superposition and measured. One shot produces N random bits.

```qasm
OPENQASM 3.0;
include "stdgates.inc";
bit[8] meas;
rz(pi/2) $0; sx $0; rz(pi/2) $0; meas[0] = measure $0;
rz(pi/2) $1; sx $1; rz(pi/2) $1; meas[1] = measure $1;
// ... repeat for each qubit
```

**Qubit selection.** `CircuitBuilder.selectBestQubits()` ranks available physical qubits by readout error (lower is better) using cached calibration data from `Quantum_Backend_Config__mdt`. This reduces hardware bias at the source before debiasing even begins.

### Bell-Test CHSH Witness Circuit

When Bell-test mode is enabled (`useBellTest = true`), the circuit changes fundamentally. Instead of independent qubits, it creates **entangled Bell pairs** and measures them in four complementary basis configurations:

```
Bell pair creation (per pair):
  Qubit A: Rz(π/2) → SX → Rz(π/2)          [Hadamard]
  Qubit B: (identity)
  Entangle: ECR $A, $B                       [native 2-qubit gate]

Basis rotation (CHSH protocol):
  Config 0: Alice 0°,  Bob 22.5°   → E(a,b)
  Config 1: Alice 0°,  Bob -22.5°  → E(a,b')
  Config 2: Alice 90°, Bob 22.5°   → E(a',b)
  Config 3: Alice 90°, Bob -22.5°  → E(a',b')
```

The four correlations combine into the CHSH S-parameter:

```
S = |E(a,b) + E(a,b') + E(a',b) - E(a',b')|

Classical limit:  S ≤ 2.0
Quantum maximum:  S ≤ 2√2 ≈ 2.828
```

**S > 2 is impossible classically.** A violation proves the randomness came from quantum mechanics, not from a pseudorandom generator or a deterministic process.

### Important: One Circuit, Not Two

In the current QuantumFair architecture, you run **either** a standard QRNG circuit **or** a Bell-test circuit per job — not both simultaneously. The Bell-test circuit produces both:

1. The CHSH attestation (device is genuinely quantum)
2. Usable random bits (from the measurement outcomes)

This is a design trade-off. The Bell-test circuit yields fewer usable random bits per shot (entangled pairs consume 2 qubits each, and the basis rotation structure constrains the output), but provides stronger certification.

### CHSH Cadence — A Design Decision

Running Bell tests on IBM hardware costs queue time and credits. Three strategies:

| Strategy                      | When to Use                              | Trade-off                          |
| ----------------------------- | ---------------------------------------- | ---------------------------------- |
| **Per-job** (current default) | High-stakes decisions, regulatory, legal | Maximum assurance, higher IBM cost |
| **Per-session / periodic**    | Routine assignments, high volume         | Good assurance, lower cost         |
| **On-demand**                 | Low-risk with occasional spot checks     | Minimal cost, weaker guarantee     |

A sensible production architecture for high-volume orgs would be: run CHSH once per backend per session, store the result as a **device attestation** record, and link it to all certificates generated during that window. If the S-value drops below 2.0, flag the backend as untrusted and halt certificate generation until it passes again. This is not yet implemented in QuantumFair but is a natural extension of the existing `Quantum_Backend_Config__mdt` pattern.

**Implementation:** `CircuitBuilder.cls` (circuit generation), `IBMQuantumService.cls` (job submission), `JobPoller.cls` (async polling via Queueable chain).

---

## Step 3 — Classical Post-Processing

The raw bitstring comes back from IBM with hardware bias — readout errors, gate noise, thermal relaxation. Post-processing removes this bias.

### Von Neumann Debiasing

QuantumFair uses **von Neumann extraction**, the simplest provably unbiased debiasing method:

```
Process raw bits in pairs:
  01 → output 0
  10 → output 1
  00 → discard
  11 → discard
```

**Why it works.** Even if a qubit is biased (P(0) = 0.6, P(1) = 0.4), the probability of `01` equals the probability of `10` (both are 0.6 × 0.4 = 0.24). By only keeping these pairs, the output is perfectly unbiased regardless of the input bias.

**Cost.** Roughly 75% of raw bits are discarded. For a circuit producing 8,192 raw bits (8 qubits × 1024 shots), expect ~2,048 debiased bits. This is why the shot count matters — you need enough raw material to survive debiasing and still cover your assignment needs.

> **Future improvement.** Toeplitz hashing is more efficient (higher bit yield for the same raw input) but requires a public random seed matrix. This is a potential enhancement for high-volume use cases where IBM minutes are constrained.

### Domain Mapping

After debiasing, the clean bitstring is mapped to the problem domain. The method depends on the assignment type:

**Uniform assignment** — For each record, consume `⌈log₂(M)⌉` bits (where M = number of assignees), convert to an integer, and apply `mod M`.

```
Example: 50 leads → 5 reps
Bits per assignment: ⌈log₂(5)⌉ = 3
Bitstring fragment: 011 → 3 → 3 mod 5 = rep #3
```

**Weighted assignment** — Consume 10 bits per selection (1024-value resolution), build a cumulative distribution function (CDF) from the weights, and map the random value to the corresponding assignee.

```
Example: Reps with weights [40%, 35%, 25%]
CDF: [0.40, 0.75, 1.00]
Random 10-bit value: 0110010011 → 403/1024 ≈ 0.394 → rep #0 (≤ 0.40)
```

**Subset selection** — Fisher-Yates shuffle using `⌈log₂(N)⌉` quantum random bits per swap, then take the first K records.

```
Example: Select 10 deals from 500
Bits per swap: ⌈log₂(500)⌉ = 9
Shuffle entire list using quantum random indices
Take first 10 → unbiased sample
```

> **A note on modular bias.** The current uniform assignment uses `mod M`, which introduces slight bias when the bit range (2^n) is not evenly divisible by M. For "pick 1 from 500" with 9 bits (range 0–511), values 500–511 map unevenly. In practice, this bias is negligible for Salesforce use cases (< 2.4% for the worst case), but proper rejection sampling — discard values ≥ M and draw again — would eliminate it entirely. The Fairness Certificate documents the mapping method used so auditors can assess this.

**Implementation:** `ResultParser.cls` (debiasing), `QuantumAssignmentEngine.cls` (domain mapping).

---

## Step 4 — Statistical Validation

Before certifying, QuantumFair validates that the source was actually random. Tests run against the **full debiased bitstring**, not just the bits consumed for the assignment. This proves the overall source was behaving randomly, even though you may have only used a fraction of the output.

### Critical Tests (Block Certification)

These run synchronously during result processing. If any fail, the certificate is denied.

| Test                    | What It Checks                  | Pass Criteria                    | Reference                  |
| ----------------------- | ------------------------------- | -------------------------------- | -------------------------- |
| **Frequency (monobit)** | Proportion of 0s vs 1s          | Z-score ≤ 2.0 (within 2σ of 50%) | NIST SP 800-22 §2.1        |
| **Runs test**           | Consecutive identical bits      | Z-score ≤ 2.0                    | NIST SP 800-22 §2.3        |
| **Chi-squared**         | Uniformity of 4-bit blocks      | χ² ≤ 45.0                        | Standard goodness-of-fit   |
| **CHSH violation**      | Quantum origin (Bell-test only) | S > 2.0                          | Clauser-Horne-Shimony-Holt |

### Extended Tests (Async, Non-Blocking)

These run via `ValidationRunner` (Queueable) after certification. They provide deeper assurance but do not block the assignment flow.

| Test                        | What It Checks                             |
| --------------------------- | ------------------------------------------ |
| **Approximate Entropy**     | Low entropy indicates predictable patterns |
| **Serial Test**             | Uniformity of overlapping m-bit patterns   |
| **Cumulative Sums (CUSUM)** | Drift or trends in the bitstring           |
| **Longest Run of Ones**     | Block-wise run length distribution         |

**Why two tiers?** The critical tests catch obvious hardware failures (stuck qubits, systematic bias) quickly. The extended tests catch subtler issues (correlations, drift) but take longer to compute and are not needed to block the user's workflow.

**Implementation:** `RandomnessValidator.cls` (all tests), `ValidationRunner.cls` (async extended tests).

---

## Step 5 — Certificate Generation

On successful validation, QuantumFair creates a `Fairness_Certificate__c` record that packages everything an auditor needs:

### Certificate Contents

| Field                       | What It Stores                                                 |
| --------------------------- | -------------------------------------------------------------- |
| **Circuit QASM**            | Exact OpenQASM 3.0 submitted to IBM                            |
| **IBM Job ID**              | Externally verifiable on IBM Quantum Platform                  |
| **Backend**                 | Which QPU ran the circuit (e.g., `ibm_kingston`)               |
| **Raw Bitstring Hash**      | SHA-256 of the raw measurement data                            |
| **Debiased Bitstring Hash** | SHA-256 of the post-processed random values                    |
| **Assignment Hash**         | SHA-256 of the final assignment mapping                        |
| **Validation Results**      | JSON with all statistical test results                         |
| **CHSH S-Value**            | Bell-test S parameter (if applicable)                          |
| **Purpose**                 | Human-readable description of what the randomness was used for |
| **Status**                  | Certified / Failed                                             |

### The Audit Chain

```
Fairness_Certificate__c
  ├── Quantum_Job__c (lookup)
  │     ├── IBM Job ID → verifiable via IBM Quantum API
  │     ├── Raw_Results__c → SHA-256 must match Raw_Bitstring_Hash__c
  │     └── Debiased_Results__c → SHA-256 must match Debiased_Bitstring_Hash__c
  │
  └── Quantum_Assignment__c (1:N)
        ├── Assigned_Record_ID__c → which record was assigned
        ├── Assigned_To_ID__c → who it was assigned to
        ├── Assignment_Index__c → position in the random sequence
        └── Random_Value__c → the quantum random bits that determined this assignment
```

**Integrity verification.** The `FairnessCertificateService.verifyCertificate()` method re-fetches the raw data from `Quantum_Job__c`, recomputes all three SHA-256 hashes, and compares them against the stored values. If any hash mismatches (indicating tampering), the certificate is flagged `Tampered__c = true`.

**Determinism guarantee.** Given the same debiased bitstring and the same assignment parameters, the assignment engine will always produce the same result. This means an auditor can independently replay the assignment from the certificate data and verify the outcome.

**Implementation:** `FairnessCertificateService.cls`.

---

## Putting It All Together

Here is the complete pipeline as executed by QuantumFair:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. PROBLEM DEFINITION                                       │
│    "Assign 50 leads to 5 reps fairly"                       │
│    → assignmentType: Uniform                                │
│    → bits per decision: ⌈log₂(5)⌉ = 3                      │
│    → total bits needed: 50 × 3 = 150 (after debiasing)     │
│    → raw bits needed: ~600 (4× for von Neumann loss)        │
│    → circuit: 8 qubits × 1024 shots = 8,192 raw bits ✓     │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. QUANTUM EXECUTION                                        │
│    CircuitBuilder → ISA-compliant OpenQASM 3.0          │
│    IBMQuantumService → POST /v1/jobs (Sampler primitive)    │
│    JobPoller → async polling (5s, 10s, 20s... backoff)  │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. POST-PROCESSING                                          │
│    ResultParser → extract bitstrings from IBM response  │
│    Von Neumann debiasing → ~2,048 clean bits from 8,192    │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. VALIDATION                                               │
│    RandomnessValidator → frequency, runs, chi-squared tests       │
│    All pass? → proceed                                      │
│    Any fail? → mark job Failed, deny certificate, notify    │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. CERTIFICATION                                            │
│    FairnessCertificateService → create certificate          │
│    SHA-256 hashes of raw bits, debiased bits, assignments   │
│    Store validation results as JSON                         │
│    Status: "Certified"                                      │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. ASSIGNMENT                                               │
│    QuantumAssignmentEngine → consume bits, map to domain    │
│    Create Quantum_Assignment__c records linking:               │
│      record → assignee → certificate → random bits used    │
└──────────────────────┬──────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. DELIVERY                                                 │
│    Publish Quantum_Job_Complete__e Platform Event                  │
│    LWC receives via empApi → update UI in real time         │
│    Custom Notification → alert requesting user              │
└─────────────────────────────────────────────────────────────┘
```

---

## Adapting the Formula to Your Domain

Every tutorial in this repository follows the same formula. The only things that change are:

| What Changes        | Example (Sales)       | Example (Healthcare)     | Example (Government)           |
| ------------------- | --------------------- | ------------------------ | ------------------------------ |
| **Record IDs**      | Opportunity IDs       | Patient IDs              | Permit Application IDs         |
| **Assignee IDs**    | Sales Rep User IDs    | Provider User IDs        | Inspector User IDs             |
| **Assignment Type** | Uniform               | Weighted (by panel size) | Subset (for random inspection) |
| **Purpose**         | "Q1 Lead Round-Robin" | "New Patient Assignment" | "Monthly Site Inspections"     |
| **Trigger**         | Record-Triggered Flow | Screen Flow              | Scheduled Flow                 |

The quantum pipeline, debiasing, validation, and certification are identical regardless of domain. You collect IDs, call the invocable action, and get back a certified fair result.

### Quick-Start Template (Flow Builder)

1. **Get Records** — query the records you want to assign or sample
2. **Extract IDs** — build a text collection of record IDs (and assignee IDs if applicable)
3. **Quantum Random Assignment** (Action) — pass the IDs, choose assignment type, set purpose
4. **Wait for Platform Event** — `Quantum_Job_Complete__e` fires when the job finishes
5. **Get Assignments** — query `Quantum_Assignment__c` where `Quantum_Job__c` = the completed job
6. **Act on Results** — update records, create tasks, send notifications

### Quick-Start Template (Apex)

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = myRecordIds;       // List<Id> — what to assign
input.assigneeIds = myAssigneeIds;   // List<Id> — who to assign to
input.assignmentType = 'Uniform';    // Uniform | Weighted | Subset
input.purpose = 'Descriptive label for the certificate';
// Optional:
// input.sampleSize = 10;            // For Subset type
// input.weights = '40,35,25';       // For Weighted type
// input.useBellTest = true;         // For CHSH certification
// input.numQubits = 8;              // Default: 8
// input.shots = 1024;               // Default: 1024

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});

// Results are async — listen for Quantum_Job_Complete__e or query Quantum_Job__c
Id jobId = results[0].jobId;
```

---

## Open Design Questions

These are areas where the pipeline could evolve:

### 1. Rejection Sampling vs. Modular Reduction

The current `Uniform` assignment uses `mod M` to map bits to assignees. When 2^n is not evenly divisible by M, this introduces slight bias (values at the top of the range wrap around unevenly). For "pick 1 of 500" with 9 bits (range 0–511), the 12 values 500–511 double-map to assignees 0–11. True rejection sampling — discard and redraw — eliminates this entirely but consumes more bits. For most Salesforce use cases the bias is negligible, but for regulated environments (clinical trials, financial audits) rejection sampling would be the correct choice.

### 2. CHSH Device Attestation Records

Running a Bell test per-job is the most conservative approach but expensive at scale. A `Quantum_Device_Attestation__c` object that stores periodic CHSH results per backend, with certificates linking to the nearest passing attestation, would reduce IBM cost while maintaining trust. If the S-value drops below 2.0, halt all certificate generation for that backend until it passes again.

### 3. Toeplitz Hashing for Higher Bit Yield

Von Neumann extraction is simple and provably unbiased but discards ~75% of raw bits. Toeplitz hashing (a universal hash function using a public random matrix) can extract more bits from the same raw input while maintaining information-theoretic security. This matters for high-volume orgs approaching IBM minute limits.

### 4. Minimum Shot Enforcement

The statistical tests (especially chi-squared on 4-bit blocks) need sufficient samples to be meaningful. NIST SP 800-22 recommends sequences of at least 1,000 bits for basic tests. QuantumFair should consider enforcing a minimum shot count (e.g., 256 shots × 8 qubits = 2,048 raw bits → ~512 debiased bits) to ensure validation results are statistically significant.
