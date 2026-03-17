# Permit Review Assignment with Quantum Fairness

Assign permit applications to reviewers fairly, preventing corruption and ensuring equal treatment.

## Business Problem

Government agencies processing building permits, business licenses, or environmental permits must assign reviewers without favoritism. Applicants and oversight bodies need assurance that reviewer assignment doesn't influence outcomes. QuantumFair provides quantum-certified random assignment.

## What You'll Build

A Record-Triggered Flow that assigns new permit applications to available reviewers.

## Step-by-Step: Flow Builder

### Step 1: Create a Record-Triggered Flow

1. Object: **Case** (or custom Permit Application object)
2. Trigger: **A record is created**
3. Entry conditions:
   - `RecordType.DeveloperName` = `Permit_Application`
   - `OwnerId` = unassigned queue

### Step 2: Get Available Reviewers

**Get Records** element:
- Object: **User**
- Filters:
  - `IsActive` = true
  - `UserRole.DeveloperName` = `Permit_Reviewer`
  - `Out_of_Office__c` = false
- Store → `varReviewerCollection`

### Step 3: Batch Pending Applications

Use a **Scheduled Path** (every 30 minutes or hourly) to batch new applications:
1. Get all permit applications with `OwnerId` = queue AND `CreatedDate` = TODAY
2. Collect into `varApplicationIds`

### Step 4: Call Quantum Random Assignment

| Input | Value |
|-------|-------|
| Record IDs | `{!varApplicationIds}` |
| Assignee IDs | `{!varReviewerIds}` |
| Assignment Type | `Uniform` |
| Purpose | `Permit Application Assignment — {!$Flow.CurrentDate}` |
| Use Bell Test | `true` (recommended for government transparency) |

### Step 5: Apply and Document

On `QRNG_Complete__e`:
1. Update each application's `OwnerId` to the assigned reviewer
2. Store Certificate ID on the application record
3. Log an activity: "Reviewer assigned via quantum randomization"

## Public Transparency

Government agencies can publish Fairness Certificate references in public records:
- Certificate ID proves the assignment was random
- IBM Quantum Job ID allows independent verification
- CHSH S-value (Bell Test) proves quantum origin
- No human decision-maker was involved in the assignment

## Conflict-of-Interest Prevention

Combine quantum assignment with conflict-of-interest checks:
1. Quantum Random Assignment selects a reviewer
2. A decision element checks for conflicts (reviewer knows applicant, etc.)
3. If conflicted, re-run quantum assignment excluding that reviewer
4. Both certificates are retained in the audit trail

## Apex Alternative

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = applicationIds;
input.assigneeIds = reviewerIds;
input.assignmentType = 'Uniform';
input.purpose = 'Daily Permit Assignment — ' + Date.today().format();
input.useBellTest = true;

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
