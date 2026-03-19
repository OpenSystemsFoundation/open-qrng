# Interview Panel Selection with Quantum Fairness

Select unbiased interview panels from eligible reviewers using quantum-certified randomness.

## Business Problem

Interview panels should be diverse and unbiased. When hiring managers pick their own panelists, they may unconsciously select people who share their biases. QuantumFair selects panel members randomly from the eligible pool, with a Fairness Certificate proving the selection was impartial.

## What You'll Build

A Screen Flow that recruiters launch from a Job Requisition to select interview panelists.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

1. **Setup > Flows > New Flow > Screen Flow**
2. Add as an action on the Job Requisition (or Position) record page.

### Step 2: Input Screen

- **Display Text:** "Select quantum-random interview panel for: {!recordId.Name}"
- **Number Input:** Panel size (e.g., 3-5 panelists)
- **Multi-select:** Department filter (optional, to ensure cross-functional panels)
- **Checkbox:** Exclude hiring manager's direct reports

### Step 3: Get Eligible Panelists

**Get Records** element:

- Object: **User**
- Filters:
    - `IsActive` = true
    - `Department` in selected departments (if filtered)
    - `Id` != hiring manager ID
    - Optionally exclude anyone who has interviewed too many candidates this month
- Store → `varEligiblePanelists`

### Step 4: Call Quantum Random Assignment

| Input           | Value                                  |
| --------------- | -------------------------------------- |
| Record IDs      | `{!varEligiblePanelistIds}`            |
| Assignment Type | `Subset`                               |
| Sample Size     | `{!varPanelSize}`                      |
| Purpose         | `Interview Panel — Req: {!varReqName}` |

### Step 5: Confirmation Screen

- "Quantum panel selection submitted"
- "You'll be notified when the panel is selected"
- Show Job ID for tracking

### Step 6: Apply Panel Assignment

On `QRNG_Complete__e`:

1. Query `QRNG_Assignment__c` for selected panelists
2. Create Interview records linking each panelist to the requisition
3. Send calendar invites or notifications to selected panelists
4. Store Certificate ID on the requisition for HR audit

## DEI Compliance

The Fairness Certificate supports Diversity, Equity & Inclusion goals:

- Proves panel selection was not influenced by personal relationships
- Provides auditable evidence for EEOC or OFCCP inquiries
- Over time, quantum randomness ensures all eligible employees serve on panels equitably
- Run a report on `QRNG_Assignment__c` to verify distribution across demographics

## Constraints and Stratification

For panels requiring specific composition (e.g., at least 1 person from engineering, 1 from product):

1. Run separate Subset selections per required department
2. Each gets its own Fairness Certificate
3. Combine the results into the final panel

## Apex Alternative

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = eligiblePanelistIds;
input.assignmentType = 'Subset';
input.sampleSize = 4;
input.purpose = 'Interview Panel — REQ-2026-0157';

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
