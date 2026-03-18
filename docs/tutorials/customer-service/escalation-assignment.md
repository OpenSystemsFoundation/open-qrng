# Escalation Assignment with Quantum Fairness

Assign escalated cases to senior agents fairly using quantum-certified randomization.

## Business Problem

Escalated cases are high-visibility and high-stress. Senior agents may feel the assignment is unfair — some getting more escalations than others, or always getting the hardest accounts. QuantumFair distributes escalations randomly with a certificate proving equitable distribution.

## What You'll Build

A Record-Triggered Flow that assigns escalated cases to available senior agents.

## Step-by-Step: Flow Builder

### Step 1: Create a Record-Triggered Flow

1. Object: **Case**
2. Trigger: **A record is updated**
3. Entry conditions:
   - `Priority` changed to `Critical` or `Urgent`
   - `Escalated__c` = true
   - `Escalation_Owner__c` is null

### Step 2: Get Senior Agents

**Get Records** element:
- Object: **User**
- Filters:
  - `IsActive` = true
  - `UserRole.DeveloperName` = `Senior_Support_Agent`
  - `Available_for_Escalations__c` = true
- Store → `varSeniorAgentCollection`

### Step 3: Batch Escalations

Use a **Scheduled Path** (every 15 minutes) to batch escalations:
1. Get escalated cases without an escalation owner from the last 15 minutes
2. Batch into a single quantum request

### Step 4: Call Quantum Random Assignment

| Input | Value |
|-------|-------|
| Record IDs | `{!varEscalatedCaseIds}` |
| Assignee IDs | `{!varSeniorAgentIds}` |
| Assignment Type | `Uniform` |
| Purpose | `Escalation Assignment — {!$Flow.CurrentDateTime}` |

### Step 5: Apply Assignment

On `QRNG_Complete__e`:
1. Update each case's `Escalation_Owner__c`
2. Send high-priority notification to the assigned agent
3. Log the Certificate ID on the case

## Weighted by Current Load

Use `Weighted` assignment inversely proportional to current escalation count:

| Agent | Active Escalations | Weight |
|-------|--------------------|--------|
| Agent A | 5 | 10 |
| Agent B | 2 | 25 |
| Agent C | 0 | 40 |

Agents with fewer active escalations get higher probability of assignment.

## Apex for Real-Time Escalation

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = escalatedCaseIds;
input.assigneeIds = seniorAgentIds;
input.assignmentType = 'Weighted';
input.weights = inverseLoadWeights;
input.purpose = 'Escalation Routing — ' + Datetime.now().format();

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
