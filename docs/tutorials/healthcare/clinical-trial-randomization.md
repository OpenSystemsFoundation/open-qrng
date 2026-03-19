# Clinical Trial Randomization with Quantum Fairness

Randomize clinical trial participants into treatment and control groups using quantum-certified randomness, meeting regulatory requirements for unbiased allocation.

## Business Problem

Clinical trials require participants to be randomly assigned to treatment groups. Regulatory agencies (FDA, EMA) require documented proof that randomization was unbiased. Traditional PRNGs are deterministic — a sophisticated adversary could predict assignments. QuantumFair provides true quantum randomness with an immutable audit certificate.

## What You'll Build

A Screen Flow for clinical trial coordinators to:

1. Select enrolled participants
2. Define treatment groups and allocation ratios
3. Run quantum randomization
4. Generate a Fairness Certificate suitable for regulatory submission

## Prerequisites

- Custom object or record type for **Trial Participant** (or use Contact with a record type)
- Custom field: `Treatment_Group__c` (picklist: Control, Treatment A, Treatment B, etc.)
- Custom field: `Randomization_Certificate__c` (text, stores Certificate ID)
- Bell Test mode recommended for regulatory-grade evidence

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

1. **Setup > Flows > New Flow > Screen Flow**
2. This is launched by the trial coordinator from a custom button on the Trial record.

### Step 2: Input Screen

Add a **Screen** element:

- **Display Text:** "Select participants to randomize into treatment groups"
- **Record Collection Picker:** Select eligible participants (Status = Enrolled, Treatment_Group = null)
- **Number Input:** Number of treatment groups (e.g., 2 for control + treatment)
- **Text Input:** Group names (comma-separated: `Control,Treatment A`)
- **Text Input:** Allocation ratio (e.g., `50,50` for 1:1 or `33,33,34` for 1:1:1)

### Step 3: Get Participant IDs

**Get Records** element:

- Object: Trial Participant (or Contact with record type filter)
- Filter: `Trial__c` = selected trial, `Treatment_Group__c` is null, `Status__c` = `Enrolled`
- Store → `varParticipantCollection`

### Step 4: Build Group Assignee IDs

For group assignment, create placeholder "assignee" IDs representing each group. Use a formula or assignment:

- Group 1 ID → `"GROUP_CONTROL"`
- Group 2 ID → `"GROUP_TREATMENT_A"`

> **Note:** The Assignment Engine maps record IDs to assignee IDs. Post-assignment, translate the assignee ID back to the group name.

### Step 5: Call Quantum Random Assignment

| Input           | Value                                                         |
| --------------- | ------------------------------------------------------------- |
| Record IDs      | `{!varParticipantIds}`                                        |
| Assignee IDs    | `{!varGroupIds}`                                              |
| Assignment Type | `Weighted`                                                    |
| Weights         | `{!varAllocationRatio}` (e.g., `50,50`)                       |
| Purpose         | `Clinical Trial: {!varTrialName} — Participant Randomization` |
| Use Bell Test   | `true` **(strongly recommended)**                             |

### Step 6: Apply Group Assignments

On `QRNG_Complete__e`:

1. Query `QRNG_Assignment__c` for the completed job
2. Map each participant to their assigned group
3. Update `Treatment_Group__c` on each participant record
4. Store the Certificate ID in `Randomization_Certificate__c`

### Step 7: Confirmation Screen

Display:

- "Randomization submitted to IBM Quantum hardware"
- Job ID for tracking
- "You will receive a notification when assignment is complete"
- "A Fairness Certificate will be generated for regulatory filing"

## Why Bell Test Mode for Clinical Trials

Standard QRNG uses Hadamard gates for superposition — true quantum randomness. Bell Test mode goes further:

| Feature              | Standard QRNG         | Bell Test QRNG                 |
| -------------------- | --------------------- | ------------------------------ |
| Randomness source    | Quantum superposition | Quantum entanglement           |
| CHSH S-value         | N/A                   | S > 2.0 (proves non-classical) |
| Regulatory strength  | Strong                | Strongest possible             |
| Additional qubits    | No                    | Yes (entangled pairs)          |
| Certificate includes | Hash chain            | Hash chain + CHSH violation    |

The CHSH inequality (S ≤ 2 for classical systems) provides mathematical proof that the randomness could not have been predetermined by any classical mechanism. This is the gold standard for regulatory submissions.

## Regulatory Documentation

The Fairness Certificate contains everything needed for regulatory filing:

1. **Certificate ID** — unique immutable identifier
2. **IBM Quantum Job ID** — externally verifiable on IBM's platform
3. **Circuit QASM** — the exact quantum circuit that was run
4. **Raw Bitstring Hash** (SHA-256) — proves raw results weren't altered
5. **Debiased Bitstring Hash** — proves post-processing integrity
6. **Assignment Hash** — proves final group assignments match the bits
7. **CHSH S-value** — (Bell Test only) proves quantum origin
8. **Statistical Validation** — frequency, runs, and chi-squared test results
9. **Timestamp** — when the randomization occurred
10. **Backend** — which IBM Quantum processor was used

## Apex for Programmatic Trials

```java
// Apex: Clinical trial randomization with Bell test
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = participantIds;
input.assigneeIds = new List<String>{'CONTROL', 'TREATMENT_A', 'TREATMENT_B'};
input.assignmentType = 'Weighted';
input.weights = new List<Decimal>{33, 33, 34};  // 1:1:1 allocation
input.purpose = 'TRIAL-2026-042: Phase III Randomization Batch 3';
input.useBellTest = true;
input.numQubits = 20;  // More qubits = more random bits per shot

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```

## Stratified Randomization

For stratified designs (balance across strata like age, sex, site), run separate quantum assignments per stratum:

1. Group participants by stratum
2. For each stratum, call Quantum Random Assignment with the same allocation ratio
3. Each stratum gets its own Fairness Certificate

This ensures balance within each subgroup while maintaining quantum-certified randomness.
