# Citizen Panel Selection with Quantum Fairness

Choose representative citizen advisory panels from a volunteer pool using quantum-certified random selection.

## Business Problem

Citizen advisory panels, jury pools, and public comment reviewers must be selected without political bias. QuantumFair selects panel members randomly and produces a Fairness Certificate that can be published as public record.

## What You'll Build

A Screen Flow for government administrators to select citizen panel members from a volunteer registry.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

Launch from a Panel or Committee record page.

### Step 2: Input Screen

- **Display Text:** "Select members for: {!varPanelName}"
- **Number Input:** Number of seats
- **Number Input:** Number of alternates
- **Checkbox:** Use Bell Test (recommended for public transparency)

### Step 3: Get Eligible Citizens

**Get Records** element:

- Object: **Contact** (or custom Citizen Volunteer object)
- Filters:
    - `Volunteer_Status__c` = `Active`
    - `District__c` = panel's district (if applicable)
    - Not currently serving on another panel
- Store → `varCitizenCollection`

### Step 4: Select Panel Members

| Input           | Value                            |
| --------------- | -------------------------------- |
| Record IDs      | `{!varCitizenIds}`               |
| Assignment Type | `Subset`                         |
| Sample Size     | `{!varSeatCount}`                |
| Purpose         | `Citizen Panel: {!varPanelName}` |
| Use Bell Test   | `true`                           |

### Step 5: Select Alternates

Run a second Quantum Random Assignment on the remaining citizens:

| Input           | Value                         |
| --------------- | ----------------------------- |
| Record IDs      | `{!varRemainingCitizenIds}`   |
| Assignment Type | `Subset`                      |
| Sample Size     | `{!varAlternateCount}`        |
| Purpose         | `Alternates: {!varPanelName}` |

### Step 6: Publish Results

1. Update panel membership records
2. Notify selected citizens and alternates
3. Publish the Fairness Certificate IDs in the public meeting record
4. The certificates are independently verifiable by any citizen via the IBM Quantum Job ID

## Public Trust

Quantum-certified selection provides the strongest possible evidence of fairness:

- No algorithm can predict the outcome
- No human selected the members
- The certificate is publicly verifiable
- The CHSH S-value proves the randomness is genuinely quantum

## Apex Alternative

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = citizenIds;
input.assignmentType = 'Subset';
input.sampleSize = panelSeats;
input.purpose = 'Budget Review Panel — District 7';
input.useBellTest = true;

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
