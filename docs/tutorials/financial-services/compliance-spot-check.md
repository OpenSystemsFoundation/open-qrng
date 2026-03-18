# Compliance Spot-Check with Quantum Fairness

Sample transactions for compliance review using quantum-certified random selection.

## Business Problem

Compliance teams must spot-check transactions for suspicious activity, policy violations, or reporting accuracy. Manual selection introduces bias. QuantumFair's subset selection provides a defensible random sample with certification.

## What You'll Build

A Scheduled Flow that daily selects transactions for compliance review.

## Step-by-Step: Flow Builder

### Step 1: Create a Schedule-Triggered Flow

- Frequency: **Daily** at 7:00 AM

### Step 2: Get Yesterday's Transactions

**Get Records** element:
- Object: Your transaction object (or Opportunity with transaction record type)
- Filters:
  - `Transaction_Date__c` = YESTERDAY
  - `Amount__c` > $0
  - `Review_Status__c` is null
- Store → `varTransactionCollection`

### Step 3: Determine Sample Size

Use a **Formula** or **Decision** element:
- If transaction count < 100: sample = 10
- If transaction count 100-500: sample = 25
- If transaction count > 500: sample = 50

### Step 4: Call Quantum Random Assignment

| Input | Value |
|-------|-------|
| Record IDs | `{!varTransactionIds}` |
| Assignment Type | `Subset` |
| Sample Size | `{!varSampleSize}` |
| Purpose | `Daily Compliance Spot-Check — {!$Flow.CurrentDate}` |

### Step 5: Route Selected Transactions

On `QRNG_Complete__e`:
1. Update selected transactions: `Review_Status__c` = `Pending Review`
2. Assign to compliance analysts (optionally via a second Quantum Random Assignment with `Uniform` type)
3. Create Tasks for each analyst

## Escalation Sampling

For flagged transactions, run a second quantum selection to determine which get escalated to senior compliance:

1. Get transactions with `Review_Status__c` = `Flagged`
2. Subset selection with smaller sample size
3. Separate Fairness Certificate for the escalation selection

## Apex for High-Volume Processing

```java
// Daily compliance spot-check
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = transactionIds;
input.assignmentType = 'Subset';
input.sampleSize = dynamicSampleSize;
input.purpose = 'AML Daily Spot-Check — ' + Date.today().format();

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
