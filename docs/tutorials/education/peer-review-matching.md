# Peer Review Matching with Quantum Fairness

Randomly pair students for peer review using quantum-certified randomization.

## Business Problem

Peer review assignments should be random to prevent cliques, ensure diverse feedback, and avoid the perception that instructors paired students based on ability or favoritism. QuantumFair assigns reviewers randomly and certifies the matching.

## What You'll Build

A Screen Flow for instructors to randomly assign peer reviewers for an assignment.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

Launch from an Assignment or Course record page.

### Step 2: Get Students

**Get Records** element:
- Object: Student Enrollment or Contact
- Filters: Enrolled in the course, status = Active
- Store → `varStudentCollection`

### Step 3: Call Quantum Random Assignment

For peer review, each student is both a "record" (submission to review) and an "assignee" (reviewer). Use `Uniform` assignment with the same list for both:

| Input | Value |
|-------|-------|
| Record IDs | `{!varStudentIds}` (submissions) |
| Assignee IDs | `{!varStudentIds}` (reviewers) |
| Assignment Type | `Uniform` |
| Purpose | `Peer Review: {!varAssignmentName}` |

> **Note:** The assignment engine may assign a student to review their own work. Add a post-processing step to detect and swap self-assignments.

### Step 4: Handle Self-Assignments

On `QRNG_Complete__e`:
1. Query `QRNG_Assignment__c` records
2. Check for cases where `Assigned_Record_ID__c` = `Assigned_To_ID__c`
3. Swap with an adjacent assignment (document the swap as a manual override)

### Step 5: Create Review Assignments

For each `QRNG_Assignment__c` record:
1. Create a Peer Review record: `Reviewer__c` = assigned user, `Submission__c` = assigned record
2. Notify reviewers with their assignment

## Multiple Reviewers per Submission

If each submission needs 3 reviewers, run the assignment 3 times with different random seeds (each run is a separate quantum job with its own Fairness Certificate).

Alternatively, set up the record IDs as 3 copies of each student ID, so the pool is 3x the class size.

## Apex for Complex Matching

```java
// Assign 2 reviewers per student
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = duplicatedStudentIds;  // Each student ID appears twice
input.assigneeIds = studentIds;
input.assignmentType = 'Uniform';
input.purpose = 'Peer Review — Midterm Essay';

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
// Post-process to remove self-assignments and duplicates
```
