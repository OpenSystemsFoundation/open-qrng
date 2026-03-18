# Territory Rebalancing with Quantum Fairness

Randomly reassign accounts during territory changes so every rep receives a provably fair distribution.

## Business Problem

Territory realignments are high-stakes events. Reps worry about losing valuable accounts or getting stuck with low-potential ones. QuantumFair provides a certified random assignment that proves no manager picked favorites.

## What You'll Build

A Screen Flow that an admin launches manually during territory changes to:
1. Select accounts from a territory
2. Select the new territory reps
3. Run quantum random assignment with optional weighting
4. Produce a Fairness Certificate for the rebalance event

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

1. **Setup > Flows > New Flow > Screen Flow**
2. This Flow will be launched manually by admins during territory changes.

### Step 2: Build the Input Screen

Add a **Screen** element with:
- **Multi-select picklist** or **Record Collection Picker** for accounts
  - Filter to the territory being rebalanced (e.g., by `Territory2Id` or a custom field)
- **Multi-select picklist** for target reps (users assigned to new territories)
- **Choice**: Assignment Type — `Uniform` or `Weighted`
- **Optional text area**: Weights (comma-separated, e.g., `40,35,25` for weighted)
- **Text input**: Purpose / reason for rebalance

### Step 3: Collect Account IDs

Use a **Get Records** element filtered by the selected territory, or pass the screen selections into a text collection variable `varAccountIds`.

### Step 4: Call Quantum Random Assignment

Add an **Action** element:

| Input | Value |
|-------|-------|
| Record IDs | `{!varAccountIds}` |
| Assignee IDs | `{!varRepIds}` |
| Assignment Type | `Uniform` or `Weighted` (from screen) |
| Weights | `{!varWeights}` (if weighted) |
| Purpose | `Territory Rebalance: {!varPurpose}` |
| Use Bell Test | `true` (recommended for high-stakes rebalances) |

### Step 5: Confirmation Screen

Display a confirmation screen showing:
- Job ID: `{!varJobId}`
- Message: "Quantum assignment submitted. You will receive a notification when complete."
- Link to the Quantum Job record

### Step 6: Apply Assignments (Event-Triggered Flow)

Create a **Platform Event-Triggered Flow** on `QRNG_Complete__e`:
1. Query `QRNG_Assignment__c` where `Quantum_Job__c` = event's `Job_Id__c`
2. For each assignment, update the Account's `OwnerId` to the assigned rep
3. Optionally log a Task on each Account noting the rebalance

## Weighted Distribution

If territories have different capacities, use `Weighted` assignment:

| Rep | Weight | Expected Share (100 accounts) |
|-----|--------|-------------------------------|
| Rep A (senior, large territory) | 40 | ~40 accounts |
| Rep B (mid territory) | 35 | ~35 accounts |
| Rep C (small territory) | 25 | ~25 accounts |

Weights are proportional — they don't need to sum to 100.

## Bell Test for High Stakes

Enable Bell Test mode (`Use Bell Test = true`) for territory rebalances. This:
- Generates entangled qubit pairs measured in different bases
- Computes the CHSH S-value (must exceed 2.0 to prove quantum origin)
- Provides the strongest possible proof that the randomness wasn't predetermined

The Fairness Certificate will include the CHSH S-value, visible in the `qrngBellTestIndicator` gauge component.

## Apex Alternative

For programmatic territory rebalances (e.g., triggered by a territory plan activation):

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = accountIds;
input.assigneeIds = repIds;
input.assignmentType = 'Weighted';
input.weights = new List<Decimal>{40, 35, 25};
input.purpose = 'Q2 Territory Rebalance';
input.useBellTest = true;

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```

## Audit Trail

Share the Fairness Certificate link with affected reps to demonstrate:
- The exact quantum circuit that was run
- Statistical validation results (frequency, runs, chi-squared tests all passed)
- The deterministic mapping from quantum bits to account assignments
- The IBM Quantum job ID for independent verification
