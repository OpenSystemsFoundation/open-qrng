# Audit Case Selection with Quantum Fairness

Randomly select accounts or transactions for regulatory audit using quantum-certified randomness.

## Business Problem

Financial institutions must perform random audits for AML (Anti-Money Laundering), KYC (Know Your Customer), and SOX compliance. Regulators require proof that audit selections are unbiased. QuantumFair provides defensible random selection with an immutable certificate.

## What You'll Build

A Screen Flow for compliance officers to select accounts for audit from a filtered population.

## Step-by-Step: Flow Builder

### Step 1: Create a Screen Flow

1. **Setup > Flows > New Flow > Screen Flow**
2. Add to the Compliance app as a utility bar item or custom tab action.

### Step 2: Input Screen

- **Date Range:** Start and end date for the audit period
- **Account Type filter:** Picklist (All, Personal, Business, High-Value)
- **Sample Size:** Number input (how many accounts to audit)
- **Audit Type:** Picklist (AML, KYC, SOX, General)
- **Bell Test:** Checkbox (recommended for regulatory audits)

### Step 3: Get Eligible Accounts

**Get Records** element:
- Object: **Account**
- Filters based on screen inputs:
  - `Type` matches selected account type
  - `CreatedDate` or `LastActivityDate` within date range
  - Exclude already-audited accounts this period
- Store → `varAccountCollection`

### Step 4: Display Population Size

Add a **Screen** element showing:
- "Found {!varAccountCount} eligible accounts"
- "Selecting {!varSampleSize} for audit"
- Confirm button to proceed

### Step 5: Call Quantum Random Assignment

| Input | Value |
|-------|-------|
| Record IDs | `{!varAccountIds}` |
| Assignment Type | `Subset` |
| Sample Size | `{!varSampleSize}` |
| Purpose | `{!varAuditType} Audit Selection — {!varDateRange}` |
| Use Bell Test | `{!varUseBellTest}` |

### Step 6: Results Screen

After `QRNG_Complete__e`:
- Display the selected accounts in a table
- Show the Fairness Certificate ID
- Provide a "Download Certificate" link
- Create audit Case records for each selected account

## Regulatory Documentation

For regulatory submissions, the Fairness Certificate provides:

| Element | Regulatory Value |
|---------|-----------------|
| Certificate ID | Unique audit trail identifier |
| IBM Job ID | Third-party verifiable |
| CHSH S-value | Proves quantum origin (Bell Test) |
| Raw Bitstring Hash | Proves data integrity |
| Assignment Hash | Proves selection integrity |
| Statistical Tests | Proves randomness quality |
| Timestamp | Proves timing of selection |

## Multi-Stage Audit Selection

For tiered audit programs:

**Stage 1:** Select 100 accounts for document review (Subset, sample=100)
**Stage 2:** From flagged accounts, select 20 for deep investigation (Subset, sample=20)

Each stage gets its own Fairness Certificate. The audit trail shows a clear chain from population → initial sample → deep dive sample.

## Apex for Automated Quarterly Audits

```java
// Scheduled Apex: Quarterly AML audit selection
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = eligibleAccountIds;
input.assignmentType = 'Subset';
input.sampleSize = 100;
input.purpose = 'AML Quarterly Audit — Q1 2026';
input.useBellTest = true;

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
// Store jobId for tracking, create Cases on QRNG_Complete__e
```
