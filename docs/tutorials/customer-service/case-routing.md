# Case Routing with Quantum Fairness

Route support cases to agents with certified fairness, ensuring equitable workload distribution.

## Business Problem

Case routing algorithms in Salesforce (Omni-Channel, assignment rules) use deterministic logic. Agents may perceive bias — some getting harder cases, others getting more volume. QuantumFair adds quantum-certified random routing as either a standalone solution or a supplement to skill-based routing.

## What You'll Build

A Record-Triggered Flow that routes new cases to available agents using quantum randomization.

## Step-by-Step: Flow Builder

### Step 1: Create a Record-Triggered Flow

1. Object: **Case**
2. Trigger: **A record is created**
3. Entry conditions:
    - `OwnerId` = support queue
    - `Priority` is not null

### Step 2: Get Available Agents

**Get Records** element:

- Object: **User**
- Filters:
    - `IsActive` = true
    - `UserRole.DeveloperName` contains `Support_Agent`
    - `Available_for_Cases__c` = true (custom field for availability)
- Store → `varAgentCollection`

### Step 3: Batch for Efficiency

Use a **Scheduled Path** (every 15 minutes) instead of per-record triggering:

1. Get all cases in the queue from the last 15 minutes
2. Batch into a single quantum assignment request

### Step 4: Call Quantum Random Assignment

| Input           | Value                                           |
| --------------- | ----------------------------------------------- |
| Record IDs      | `{!varCaseIds}`                                 |
| Assignee IDs    | `{!varAgentIds}`                                |
| Assignment Type | `Uniform`                                       |
| Purpose         | `Case Routing Batch — {!$Flow.CurrentDateTime}` |

### Step 5: Apply Routing

On `QRNG_Complete__e`:

1. Update each case's `OwnerId` to the assigned agent
2. Send notification to each agent

## Weighted by Skill Level

For tiered support, use `Weighted` assignment based on agent capacity or skill:

| Agent   | Tier    | Weight                      |
| ------- | ------- | --------------------------- |
| Agent A | Senior  | 30 (handles complex cases)  |
| Agent B | Mid     | 40 (primary routing target) |
| Agent C | Junior  | 20 (lighter load)           |
| Agent D | Trainee | 10 (shadowing)              |

## Combining with Skill-Based Routing

Use quantum assignment as a fairness layer on top of skill-based routing:

1. **First:** Filter agents by required skills (language, product expertise)
2. **Then:** Quantum random assignment among qualified agents
3. This ensures skill matching while eliminating bias within the qualified pool

## Agent Trust and Transparency

Share the Fairness Certificate with agents:

- "Your case assignments are quantum-random. View the certificate: {Link}"
- Reduces "why did I get this case?" complaints
- Provides data for workforce management discussions

## Apex for High-Volume Contact Centers

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = caseIds;
input.assigneeIds = agentIds;
input.assignmentType = 'Weighted';
input.weights = agentCapacities;
input.purpose = 'Support Case Routing — ' + Datetime.now().format();

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
