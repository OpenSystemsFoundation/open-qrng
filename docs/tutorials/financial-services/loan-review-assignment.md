# Loan Review Assignment with Quantum Fairness

Assign loan applications to underwriters without bias, ensuring fair workload distribution and regulatory compliance.

## Business Problem

Fair lending regulations (ECOA, CRA) require that loan applications are processed without discriminatory bias. If a manager manually assigns applications to underwriters, patterns could emerge — intentional or not. QuantumFair distributes applications randomly and certifies the assignment.

## What You'll Build

A Record-Triggered Flow that automatically assigns new loan applications to available underwriters.

## Step-by-Step: Flow Builder

### Step 1: Create a Record-Triggered Flow

1. Object: **Opportunity** (or custom Loan Application object)
2. Trigger: **A record is created**
3. Entry conditions:
    - `RecordType.DeveloperName` = `Loan_Application`
    - `StageName` = `Submitted`
    - `Underwriter__c` is null

### Step 2: Get Available Underwriters

**Get Records** element:

- Object: **User**
- Filters:
    - `IsActive` = true
    - `UserRole.DeveloperName` contains `Underwriter`
    - `Out_of_Office__c` = false
- Store → `varUnderwriterCollection`

### Step 3: Batch for Efficiency

Rather than submitting one quantum job per application, use a **Scheduled Path** (e.g., every 30 minutes) to batch pending applications:

1. **Get Records:** Loan applications where `Underwriter__c` is null AND `CreatedDate` = TODAY
2. Collect all IDs into `varApplicationIds`
3. Call Quantum Random Assignment once for the batch

### Step 4: Call Quantum Random Assignment

| Input           | Value                                                |
| --------------- | ---------------------------------------------------- |
| Record IDs      | `{!varApplicationIds}`                               |
| Assignee IDs    | `{!varUnderwriterIds}`                               |
| Assignment Type | `Uniform`                                            |
| Purpose         | `Loan Application Assignment — {!$Flow.CurrentDate}` |

### Step 5: Apply Assignments

On `QRNG_Complete__e`:

1. Query `QRNG_Assignment__c` for the job
2. Update each application's `Underwriter__c` field
3. Send notification to each underwriter with their new applications

## Weighted by Capacity

If underwriters have different caseload limits:

| Underwriter | Current Load | Capacity | Available | Weight |
| ----------- | ------------ | -------- | --------- | ------ |
| U1          | 10           | 30       | 20        | 40     |
| U2          | 20           | 30       | 10        | 20     |
| U3          | 5            | 25       | 20        | 40     |

Use `Weighted` assignment with weights proportional to available capacity.

## Fair Lending Compliance

The Fairness Certificate documents that assignment was:

- **Random:** Quantum hardware, not deterministic algorithms
- **Unbiased:** No human decision-maker in the loop
- **Auditable:** Certificate links to IBM Quantum job
- **Tamper-proof:** SHA-256 hashes verified nightly

Store the Certificate ID on each loan application for examiner review.

## Apex Alternative

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = loanAppIds;
input.assigneeIds = underwriterIds;
input.assignmentType = 'Weighted';
input.weights = availableCapacities;
input.purpose = 'Daily Loan Assignment — ' + Date.today().format();

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
