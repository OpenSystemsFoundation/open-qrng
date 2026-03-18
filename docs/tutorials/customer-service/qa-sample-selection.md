# QA Sample Selection with Quantum Fairness

Select agent interactions for quality review using quantum-certified random sampling.

## Business Problem

Quality assurance teams must review a sample of agent interactions (calls, chats, emails) to assess performance. If QA analysts or managers choose which interactions to review, they may unconsciously bias toward certain agents or outcomes. QuantumFair selects interactions randomly.

## What You'll Build

A Scheduled Flow that weekly selects interactions for QA review.

## Step-by-Step: Flow Builder

### Step 1: Create a Schedule-Triggered Flow

- Frequency: **Weekly** (Monday at 7:00 AM)

### Step 2: Get Last Week's Interactions

**Get Records** element:
- Object: **Case** or **Task** (representing interactions)
- Filters:
  - `ClosedDate` = LAST_WEEK
  - `RecordType.DeveloperName` in (`Phone_Call`, `Chat`, `Email`)
- Store → `varInteractionCollection`

### Step 3: Call Quantum Random Assignment

| Input | Value |
|-------|-------|
| Record IDs | `{!varInteractionIds}` |
| Assignment Type | `Subset` |
| Sample Size | `20` (or per your QA protocol) |
| Purpose | `Weekly QA Review — Week of {!$Flow.CurrentDate}` |

### Step 4: Assign to QA Analysts

Run a second Quantum Random Assignment to distribute selected interactions among QA analysts:

| Input | Value |
|-------|-------|
| Record IDs | `{!varSelectedInteractionIds}` |
| Assignee IDs | `{!varQAAnalystIds}` |
| Assignment Type | `Uniform` |
| Purpose | `QA Analyst Assignment — {!$Flow.CurrentDate}` |

### Step 5: Create QA Tasks

On `QRNG_Complete__e`:
1. Create a QA Review task for each selected interaction
2. Assign to the quantum-selected QA analyst
3. Include Certificate IDs for both the selection and the analyst assignment

## Per-Agent Fair Sampling

To ensure each agent gets reviewed equally:
1. Group interactions by agent
2. Select 2-3 per agent using separate Subset calls
3. Each agent's sample gets its own Fairness Certificate
4. Agents can verify their reviews were randomly selected

## Apex for Large Contact Centers

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = interactionIds;
input.assignmentType = 'Subset';
input.sampleSize = 50;
input.purpose = 'Weekly QA Sample — ' + Date.today().toStartOfWeek().format();

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
