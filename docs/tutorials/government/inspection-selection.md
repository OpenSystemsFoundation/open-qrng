# Inspection Selection with Quantum Fairness

Select sites for random inspection using quantum-certified random sampling.

## Business Problem

Regulatory agencies must conduct random inspections (health, safety, environmental, building code). If inspectors or managers choose which sites to inspect, they may avoid difficult locations or target specific businesses. QuantumFair selects sites randomly with a Fairness Certificate proving the selection was unbiased.

## What You'll Build

A Scheduled Flow that monthly selects sites for inspection from the regulated population.

## Step-by-Step: Flow Builder

### Step 1: Create a Schedule-Triggered Flow

- Frequency: **Monthly** (1st of each month)

### Step 2: Get Eligible Sites

**Get Records** element:
- Object: **Account** (or custom Facility/Site object)
- Filters:
  - `RecordType.DeveloperName` = `Regulated_Facility`
  - `License_Status__c` = `Active`
  - `Last_Inspection_Date__c` < 12 months ago (or null)
- Store → `varSiteCollection`

### Step 3: Determine Sample Size

Use risk-based sampling tiers:

| Risk Category | Population % to Sample |
|--------------|----------------------|
| High risk | 20% |
| Medium risk | 10% |
| Low risk | 5% |

Add a **Decision** element to route by risk category, then calculate sample size.

### Step 4: Call Quantum Random Assignment (per risk tier)

For each tier:

| Input | Value |
|-------|-------|
| Record IDs | `{!varTierSiteIds}` |
| Assignment Type | `Subset` |
| Sample Size | `{!varTierSampleSize}` |
| Purpose | `Monthly Inspection — {!varRiskTier} Risk — {!$Flow.CurrentDate}` |
| Use Bell Test | `true` |

Each tier gets its own Fairness Certificate.

### Step 5: Assign Inspectors

After site selection, run a second Quantum Random Assignment to assign inspectors to selected sites:

| Input | Value |
|-------|-------|
| Record IDs | `{!varSelectedSiteIds}` (all tiers combined) |
| Assignee IDs | `{!varInspectorIds}` |
| Assignment Type | `Uniform` |
| Purpose | `Inspector Assignment — {!$Flow.CurrentDate}` |

### Step 6: Create Inspection Records

On `QRNG_Complete__e`:
1. Create Inspection records for each selected site
2. Assign the inspector
3. Set due date
4. Store both Certificate IDs (site selection + inspector assignment)

## Legal Defensibility

If a business challenges an inspection as targeted:
- Produce the Fairness Certificate showing quantum random selection
- The IBM Quantum Job ID allows the business to independently verify
- Statistical validation proves the selection was uniformly random
- The full audit trail is immutable and tamper-checked nightly

## Apex for Large Populations

```java
// Select sites for inspection
QuantumRandomAssignment.Input siteInput = new QuantumRandomAssignment.Input();
siteInput.recordIds = facilityIds;
siteInput.assignmentType = 'Subset';
siteInput.sampleSize = calculateSampleSize(facilityIds.size(), riskTier);
siteInput.purpose = 'Environmental Inspection — ' + Date.today().format();
siteInput.useBellTest = true;

// Assign inspectors to selected sites (after site selection completes)
QuantumRandomAssignment.Input inspInput = new QuantumRandomAssignment.Input();
inspInput.recordIds = selectedSiteIds;
inspInput.assigneeIds = inspectorIds;
inspInput.assignmentType = 'Uniform';
inspInput.purpose = 'Inspector Assignment — ' + Date.today().format();
```
