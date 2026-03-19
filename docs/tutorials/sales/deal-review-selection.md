# Deal Review Selection with Quantum Fairness

Randomly select deals for pipeline review without bias, ensuring every rep's pipeline gets equal scrutiny.

## Business Problem

Sales managers need to review deals for forecast accuracy, but cherry-picking which deals to review can introduce bias. QuantumFair's `Subset` assignment type selects a random sample from the pipeline, and the Fairness Certificate proves the selection was unbiased.

## What You'll Build

A Scheduled Flow that weekly:

1. Queries open opportunities above a threshold
2. Selects a random subset for review
3. Creates Tasks for the review assignments

## Step-by-Step: Flow Builder

### Step 1: Create a Schedule-Triggered Flow

1. **Setup > Flows > New Flow > Schedule-Triggered Flow**
2. Set frequency: **Weekly** (e.g., every Monday at 8:00 AM)

### Step 2: Get Eligible Deals

Add a **Get Records** element:

- Object: **Opportunity**
- Filters:
    - `StageName` not in (`Closed Won`, `Closed Lost`)
    - `Amount` greater than your threshold (e.g., $50,000)
    - `CloseDate` within next 90 days
- Store all records → `varDealCollection`

### Step 3: Extract Opportunity IDs

Loop or assign to build a text collection `varDealIds` with all eligible Opportunity IDs.

### Step 4: Call Quantum Random Assignment

Add an **Action** element:

| Input           | Value                                |
| --------------- | ------------------------------------ |
| Record IDs      | `{!varDealIds}`                      |
| Assignee IDs    | _(leave empty for subset selection)_ |
| Assignment Type | `Subset`                             |
| Sample Size     | `10` (or your desired review count)  |
| Purpose         | `Weekly Pipeline Review Selection`   |

The `Subset` type uses a Fisher-Yates shuffle to select `sampleSize` records from the pool. No assignee IDs are needed — you're selecting _which_ deals, not _who_ gets them.

### Step 5: Create Review Tasks

After `Quantum_Job_Complete__e` fires, a second Flow:

1. Queries `Quantum_Assignment__c` records for the completed job
2. For each selected Opportunity, creates a Task:
    - Subject: `Pipeline Review — Quantum Selected`
    - WhatId: the Opportunity
    - OwnerId: the Opportunity owner's manager (or a review queue)
    - Description: includes the Fairness Certificate ID

### Step 6: Notify the Team

Use a Flow **Send Email** or **Custom Notification** action to inform the sales team:

- "10 deals have been randomly selected for this week's pipeline review"
- Include a link to the Fairness Certificate

## Sample Size Guidance

| Pipeline Size | Recommended Sample | Confidence Level  |
| ------------- | ------------------ | ----------------- |
| 20-50 deals   | 5-10               | Spot check        |
| 50-200 deals  | 10-20              | Moderate coverage |
| 200+ deals    | 20-30              | Statistical rigor |

## Why Quantum Subset Selection Matters

Traditional `Math.random()` in Apex or `RAND()` in formulas:

- Uses a PRNG seeded from system clock — deterministic and predictable
- No audit trail — impossible to prove the selection wasn't manipulated
- No certificate — "trust me, it was random" isn't auditable

QuantumFair's subset selection:

- Uses quantum superposition (Hadamard gates → measurement) for true randomness
- Fisher-Yates shuffle ensures every possible subset is equally likely
- Fairness Certificate with SHA-256 hashes proves integrity
- IBM Job ID allows independent verification

## Apex for Larger Pipelines

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = oppIds;          // All eligible Opportunity IDs
input.assignmentType = 'Subset';
input.sampleSize = 20;
input.purpose = 'Q1 Pipeline Review — Week 12';

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```

## Next Steps

- Adjust the **sample size** dynamically based on pipeline growth using a formula or custom metadata
- Build a **Dashboard** on `Quantum_Assignment__c` to track which deals were selected over time and verify even coverage
- Enable **Bell Test** mode for quarter-end reviews to prove quantum origin via CHSH inequality violation
