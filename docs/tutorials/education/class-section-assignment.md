# Class Section Assignment with Quantum Fairness

Distribute students across class sections equitably using quantum-certified randomization.

## Business Problem

Assigning students to sections manually leads to imbalanced classes and parent complaints about favoritism. QuantumFair distributes students randomly across sections, producing a Fairness Certificate that schools can share with parents.

## What You'll Build

A Screen Flow for registrars to assign students to sections for a given course.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

Launch from a Course record page.

### Step 2: Input Screen

- **Record Picker:** Select the course
- **Display Text:** Show available sections and their capacities
- **Checkbox:** Use weighted distribution (based on remaining capacity per section)

### Step 3: Get Enrolled Students

**Get Records** element:

- Object: Student Enrollment (custom object or Contact with student record type)
- Filters: `Course__c` = selected course, `Section__c` is null
- Store → `varStudentCollection`

### Step 4: Get Sections as Assignees

**Get Records** element:

- Object: Section (custom object)
- Filters: `Course__c` = selected course, `Status__c` = `Open`
- Store → `varSectionCollection`

Use section IDs as the "Assignee IDs" in the quantum assignment.

### Step 5: Call Quantum Random Assignment

| Input           | Value                                              |
| --------------- | -------------------------------------------------- |
| Record IDs      | `{!varStudentIds}`                                 |
| Assignee IDs    | `{!varSectionIds}`                                 |
| Assignment Type | `Weighted` (by remaining capacity) or `Uniform`    |
| Weights         | Remaining capacity per section (if weighted)       |
| Purpose         | `Section Assignment: {!varCourseName} — Fall 2026` |

### Step 6: Apply Section Assignments

On `QRNG_Complete__e`:

1. Query `QRNG_Assignment__c` for the job
2. Update each student's `Section__c` field to the assigned section
3. Update section enrollment counts

### Step 7: Parent Communication

Share the Fairness Certificate reference in parent notifications:

> _"Your child has been assigned to Section {X} for {Course Name}. Sections were assigned using certified quantum randomization to ensure fair distribution. Certificate reference: {Certificate ID}."_

## Handling Constraints

For students with scheduling constraints (e.g., must be in morning sections):

1. Pre-filter: Remove constrained students from the pool
2. Assign constrained students to their required sections manually
3. Run quantum assignment on the remaining students
4. The certificate covers the randomized portion; document manual overrides separately

## Apex for Bulk Registration

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = studentIds;
input.assigneeIds = sectionIds;
input.assignmentType = 'Weighted';
input.weights = remainingCapacities;
input.purpose = 'Fall 2026 Section Assignment — CS 101';

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
