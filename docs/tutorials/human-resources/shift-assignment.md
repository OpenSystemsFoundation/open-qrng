# Shift Assignment with Quantum Fairness

Fairly assign premium or undesirable shifts to employees using quantum-certified randomness.

## Business Problem

Shift assignment is a frequent source of employee grievance. Whether it's holiday shifts, overtime, or premium weekend slots, employees need to trust the assignment is fair. QuantumFair assigns shifts randomly and provides a certificate proving no favoritism.

## What You'll Build

A Screen Flow for shift managers to assign upcoming shifts to available employees.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

Add as an action on a Shift Schedule or custom object record page.

### Step 2: Input Screen

- **Record Picker:** Select the shift(s) to assign
- **Multi-select:** Available employees (or auto-populated from a queue/team)
- **Choice:** Assignment Type — `Uniform` (equal chance) or `Weighted` (factor in seniority/preferences)
- **Text:** Purpose (e.g., "Holiday Weekend Shift — Dec 25-26")

### Step 3: Get Available Employees

**Get Records** element:

- Object: **User** or custom Employee object
- Filters:
    - `Department` = shift department
    - `IsActive` = true
    - Not already assigned a shift in this period
    - Not on PTO
- Store → `varAvailableEmployees`

### Step 4: Call Quantum Random Assignment

**For assigning people to shifts (multiple shifts, multiple people):**

| Input           | Value                                               |
| --------------- | --------------------------------------------------- |
| Record IDs      | `{!varShiftIds}` (shifts are the "records")         |
| Assignee IDs    | `{!varEmployeeIds}` (employees are the "assignees") |
| Assignment Type | `Uniform`                                           |
| Purpose         | `{!varPurpose}`                                     |

**For selecting who gets the undesirable shift (single shift, select from pool):**

| Input           | Value                                  |
| --------------- | -------------------------------------- |
| Record IDs      | `{!varEmployeeIds}`                    |
| Assignment Type | `Subset`                               |
| Sample Size     | `{!varShiftCount}`                     |
| Purpose         | `Holiday Shift Selection — {!varDate}` |

### Step 5: Apply and Notify

On `QRNG_Complete__e`:

1. Update shift records with assigned employees
2. Send notifications: "You have been assigned to {Shift Name}. This assignment was made using quantum randomization. Certificate: {CertificateId}"
3. The certificate link allows employees to verify the assignment was fair

## Weighted by Inverse Seniority

For undesirable shifts, weight inversely by recent undesirable shift count:

| Employee | Undesirable Shifts (last 6 mo) | Weight                                |
| -------- | ------------------------------ | ------------------------------------- |
| E1       | 5                              | 10 (low weight = fewer assignments)   |
| E2       | 2                              | 30                                    |
| E3       | 0                              | 50 (high weight = due for assignment) |

This balances fairness over time while maintaining quantum certification for each batch.

## Employee Transparency

Share the Fairness Certificate link in the shift notification. Employees can:

1. View the certificate showing all validation tests passed
2. See that quantum hardware (not a manager) made the selection
3. Verify via the IBM Quantum Job ID if they wish

This transparency reduces grievances and builds trust in the process.

## Apex for Automated Weekly Scheduling

```java
// Apex: Weekly shift assignment
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = shiftIds;
input.assigneeIds = employeeIds;
input.assignmentType = 'Uniform';
input.purpose = 'Weekly Shift Assignment — Week of ' + Date.today().toStartOfWeek().format();

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
