# Scholarship Selection with Quantum Fairness

Select scholarship recipients from a qualified applicant pool using quantum-certified random selection.

## Business Problem

When more qualified applicants exist than available scholarships, selection must be demonstrably fair. QuantumFair selects recipients randomly from the qualified pool and produces a Fairness Certificate proving no human bias influenced the selection.

## What You'll Build

A Screen Flow for scholarship administrators to select recipients from eligible applicants.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

Launch from a Scholarship Program record page.

### Step 2: Input Screen

- **Display Text:** "{!varScholarshipName} — {!varAvailableAwards} awards available"
- **Display Text:** "{!varEligibleCount} eligible applicants"
- **Checkbox:** Enable Bell Test (recommended for high-value scholarships)
- Confirm button

### Step 3: Get Eligible Applicants

**Get Records** element:

- Object: Scholarship Application (custom object)
- Filters:
    - `Scholarship_Program__c` = current program
    - `Eligibility_Status__c` = `Qualified`
    - `Award_Status__c` = `Pending`
- Store → `varApplicantCollection`

### Step 4: Call Quantum Random Assignment

| Input           | Value                                                 |
| --------------- | ----------------------------------------------------- |
| Record IDs      | `{!varApplicantIds}`                                  |
| Assignment Type | `Subset`                                              |
| Sample Size     | `{!varAvailableAwards}`                               |
| Purpose         | `Scholarship Selection: {!varScholarshipName} — 2026` |
| Use Bell Test   | `{!varUseBellTest}`                                   |

### Step 5: Award and Notify

On `QRNG_Complete__e`:

1. Update selected applicants: `Award_Status__c` = `Selected`
2. Update non-selected: `Award_Status__c` = `Not Selected`
3. Email all applicants with the result and Fairness Certificate link

## Tiered Scholarships

For scholarships with different award levels (Gold, Silver, Bronze):

**Round 1:** Select Gold recipients from full pool (Subset, sample=Gold count)
**Round 2:** Select Silver recipients from remaining pool (Subset, sample=Silver count)
**Round 3:** Select Bronze recipients from remaining pool (Subset, sample=Bronze count)

Each round gets its own Fairness Certificate, creating a clear audit trail.

## Donor and Board Assurance

The Fairness Certificate reassures donors and board members:

- Quantum randomness eliminates nepotism concerns
- Every selection is independently verifiable via IBM Quantum
- The SHA-256 hash chain proves the selection wasn't altered after the fact
- Statistical validation tests confirm the randomness quality

## Apex Alternative

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = qualifiedApplicantIds;
input.assignmentType = 'Subset';
input.sampleSize = availableAwards;
input.purpose = 'Merit Scholarship 2026 — Final Selection';
input.useBellTest = true;

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
