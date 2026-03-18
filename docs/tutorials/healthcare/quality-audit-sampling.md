# Healthcare Quality Audit Sampling with Quantum Fairness

Select patient records for compliance and quality audits using quantum-certified random sampling.

## Business Problem

Healthcare organizations must regularly audit patient records for billing accuracy, treatment protocol adherence, and regulatory compliance (CMS, Joint Commission). If auditors select records manually, they may unconsciously bias toward easy or problematic cases. QuantumFair's `Subset` assignment provides certified random sampling.

## What You'll Build

A Scheduled Flow that monthly selects a random sample of patient encounters for quality review.

## Step-by-Step: Flow Builder

### Step 1: Create a Schedule-Triggered Flow

1. **Setup > Flows > New Flow > Schedule-Triggered Flow**
2. Frequency: **Monthly** (e.g., 1st of each month at 6:00 AM)

### Step 2: Get Eligible Records

Add a **Get Records** element:

- Object: **Case** (or your Encounter/Visit object)
- Filters:
    - `CreatedDate` = LAST_MONTH
    - `RecordType.DeveloperName` = `Patient_Encounter`
    - `Status` = `Closed`
- Store all records → `varEncounterCollection`

### Step 3: Call Quantum Random Assignment

| Input           | Value                                              |
| --------------- | -------------------------------------------------- |
| Record IDs      | `{!varEncounterIds}`                               |
| Assignment Type | `Subset`                                           |
| Sample Size     | `25` (or per your audit protocol)                  |
| Purpose         | `Monthly Quality Audit — {!$Flow.CurrentDateTime}` |

### Step 4: Create Audit Tasks

On `QRNG_Complete__e`:

1. Query `QRNG_Assignment__c` for selected records
2. Create a Task for each:
    - Subject: "Quality Audit Review"
    - WhatId: the selected encounter
    - OwnerId: quality review queue
    - Description: "Quantum-selected for audit. Certificate: {CertificateId}"

### Step 5: Audit Report

Create a Salesforce Report on `QRNG_Assignment__c`:

- Filter: Purpose contains "Quality Audit"
- Group by: month
- Show: selected records, certificate status, validation results

## Sample Size Guidelines

| Monthly Encounters | Recommended Sample | Regulatory Basis          |
| ------------------ | ------------------ | ------------------------- |
| < 100              | 10-15              | Spot check                |
| 100-500            | 20-30              | CMS guidelines            |
| 500-2,000          | 30-50              | Statistical significance  |
| 2,000+             | 50-100             | Large-population sampling |

## Why Quantum Sampling for Audits

Regulators increasingly scrutinize sampling methodology:

- **Defensible selection:** The Fairness Certificate proves records weren't cherry-picked
- **Reproducible:** Same quantum bits → same sample (auditors can verify)
- **Independent verification:** IBM Quantum Job ID provides third-party proof
- **Tamper-evident:** Nightly integrity checks detect any post-hoc changes to certificates

## Apex for Large Populations

```java
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = encounterIds;   // All eligible encounter IDs
input.assignmentType = 'Subset';
input.sampleSize = 50;
input.purpose = 'CMS Compliance Audit — March 2026';

List<QuantumRandomAssignment.Output> results =
    QuantumRandomAssignment.assign(new List<QuantumRandomAssignment.Input>{input});
```
