# Training Slot Allocation with Quantum Fairness

Allocate limited training seats without favoritism using quantum-certified random selection.

## Business Problem

When a popular training program has more applicants than seats, selection must be fair. Manual selection by managers invites accusations of favoritism. QuantumFair selects participants randomly and certifies the selection.

## What You'll Build

A Screen Flow for L&D administrators to select training participants from an applicant pool.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

Launch from a Training Program record page.

### Step 2: Input Screen

- **Display Text:** "Select participants for: {!varTrainingName}"
- **Display Text:** "Available seats: {!varSeatCount}"
- **Display Text:** "Total applicants: {!varApplicantCount}"
- **Checkbox:** Use waitlist (select additional alternates)

### Step 3: Get Applicants

**Get Records** element:

- Object: Training Application (custom object or Campaign Member)
- Filters: `Training_Program__c` = current program, `Status__c` = `Applied`
- Store → `varApplicantCollection`

### Step 4: Call Quantum Random Assignment

| Input           | Value                                    |
| --------------- | ---------------------------------------- |
| Record IDs      | `{!varApplicantIds}`                     |
| Assignment Type | `Subset`                                 |
| Sample Size     | `{!varSeatCount}`                        |
| Purpose         | `Training Selection: {!varTrainingName}` |

### Step 5: Optional Waitlist

If the waitlist checkbox is selected, run a second Quantum Random Assignment on the remaining applicants:

- Record IDs: applicants NOT in the first selection
- Sample Size: 5 (or desired waitlist length)
- Purpose: `Waitlist: {!varTrainingName}`

Each selection gets its own Fairness Certificate.

### Step 6: Notify Participants

On `Quantum_Job_Complete__e`:

1. Update selected applicants: `Status__c` = `Selected`
2. Update waitlisted applicants: `Status__c` = `Waitlisted`
3. Update remaining: `Status__c` = `Not Selected`
4. Email all applicants with their status and the Fairness Certificate link

## Communication Template

> _"Thank you for applying to {Training Name}. We received {X} applications for {Y} seats. To ensure fairness, participants were selected using quantum random number generation from IBM Quantum hardware. Your selection status: {Status}. You can verify the fairness of this selection at: {Certificate Link}."_

## Apex Alternative

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = applicantIds;
input.assignmentType = 'Subset';
input.sampleSize = availableSeats;
input.purpose = 'Leadership Training 2026 — Cohort Selection';

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
