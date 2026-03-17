# Patient-Provider Assignment with Quantum Fairness

Assign new patients to healthcare providers fairly, ensuring equitable panel distribution and certified proof of unbiased assignment.

## Business Problem

Healthcare organizations must distribute patients across providers without bias toward factors like insurance type, acuity, or demographics. Regulatory bodies and patients expect fair access to providers. QuantumFair gives you a Fairness Certificate proving each assignment batch was unbiased.

## What You'll Build

A Flow that triggers when a new patient (Contact or custom Patient object) is created and assigns them to an available provider using quantum randomization.

## Step-by-Step: Flow Builder

### Step 1: Create a Record-Triggered Flow

1. **Setup > Flows > New Flow > Record-Triggered Flow**
2. Object: **Contact** (or your patient object)
3. Trigger: **A record is created**
4. Entry conditions: `RecordType.DeveloperName` = `Patient` AND `Provider__c` is null
5. Optimize for: **Actions and Related Records**

### Step 2: Get Available Providers

Add a **Get Records** element:
- Object: **User** (or custom Provider object)
- Filters:
  - `IsActive` = true
  - `Profile.Name` = `Healthcare Provider` (or your provider profile)
  - `Accepting_New_Patients__c` = true
- Store all records → `varProviderCollection`

### Step 3: Call Quantum Random Assignment

Add an **Action** element:

| Input | Value |
|-------|-------|
| Record IDs | Collection containing `{!$Record.Id}` |
| Assignee IDs | `{!varProviderIds}` |
| Assignment Type | `Uniform` |
| Purpose | `New Patient Provider Assignment` |

> **Batch optimization:** For high-volume clinics, use a Scheduled Flow that batches new patients every hour instead of triggering per-record. This sends fewer quantum jobs and is more efficient.

### Step 4: Apply the Assignment

On `QRNG_Complete__e`:
1. Query `QRNG_Assignment__c` for the completed job
2. Update the patient's `Provider__c` lookup field
3. Create a Task for the assigned provider: "New patient assigned"

### Step 5: Document for Compliance

The Fairness Certificate is automatically linked to the Quantum Job. For healthcare compliance:
- Reference the Certificate ID in the patient's record
- Store the Certificate ID in a custom field `Assignment_Certificate__c` on the patient record
- The certificate proves the assignment was not influenced by insurance type, race, or other protected characteristics

## Weighted Assignment by Capacity

If providers have different panel capacities, use `Weighted` assignment:

| Provider | Panel Capacity | Weight |
|----------|---------------|--------|
| Dr. Smith | 500 remaining | 50 |
| Dr. Jones | 300 remaining | 30 |
| Dr. Patel | 200 remaining | 20 |

```
Assignment Type: Weighted
Weights: 50,30,20
```

This ensures providers with more capacity receive proportionally more patients while maintaining quantum-certified fairness.

## Compliance Considerations

- **HIPAA:** No patient data is sent to IBM Quantum. Only abstract qubit circuits (Hadamard + measurement) are submitted. The circuit contains zero PHI.
- **Audit trail:** Every assignment links to a Fairness Certificate with cryptographic hashes verifiable by compliance officers
- **Determinism:** The same quantum bits always produce the same assignment — an auditor can re-verify any historical assignment
- **Non-repudiation:** The IBM Quantum Job ID allows independent third-party verification

## Apex for Bulk Intake

For patient import batches (e.g., insurance enrollment periods):

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = patientIds;
input.assigneeIds = providerIds;
input.assignmentType = 'Weighted';
input.weights = panelCapacities;  // List<Decimal> remaining capacity per provider
input.purpose = 'Q1 Enrollment Patient Assignment';
input.useBellTest = true;         // Maximum auditability for healthcare

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
