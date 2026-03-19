# Lead Round-Robin Assignment with Quantum Fairness

Distribute inbound leads fairly across sales reps using quantum-certified randomization, so no rep can claim the system is biased.

## Business Problem

Traditional round-robin or random assignment in Salesforce uses pseudo-random number generators (PRNGs) that are deterministic and can exhibit patterns. When commission structures are involved, reps may question whether assignment is truly fair. QuantumFair solves this with IBM Quantum hardware and an auditable Fairness Certificate for every batch.

## What You'll Build

A Flow that:

1. Triggers when new leads arrive (or on a schedule)
2. Collects unassigned leads
3. Calls the Quantum Random Assignment action to distribute them across reps
4. Creates a Fairness Certificate proving the assignment was unbiased

## Prerequisites

- QuantumFair installed and connected to IBM Quantum
- A Queue or Public Group containing your sales reps
- `QuantumFair_User` permission set assigned to the running user

## Step-by-Step: Flow Builder

### Step 1: Create a Record-Triggered Flow

1. Go to **Setup > Flows > New Flow**
2. Select **Record-Triggered Flow**
3. Object: **Lead**
4. Trigger: **A record is created**
5. Entry conditions: `OwnerId` equals your unassigned queue ID
6. Optimize for: **Actions and Related Records**

### Step 2: Get Unassigned Leads

Add a **Get Records** element:

- Object: **Lead**
- Filter: `OwnerId` = `{!$Record.OwnerId}` AND `Status` = `New`
- Store: **All records** → variable `varLeadCollection`

> **Tip:** For high-volume orgs, consider a Scheduled Flow that batches leads every 15 minutes instead of triggering per-record. This reduces quantum job submissions.

### Step 3: Get Sales Rep IDs

Add a **Get Records** element:

- Object: **GroupMember**
- Filter: `GroupId` = your sales rep queue/group ID
- Store: **All records** → variable `varRepMembers`

Then use an **Assignment** element to extract the `UserOrGroupId` values into a text collection variable `varRepIds`.

### Step 4: Extract Lead IDs

Use an **Assignment** element or **Loop** to collect `{!varLeadCollection.Id}` values into a text collection variable `varLeadIds`.

### Step 5: Call Quantum Random Assignment

Add an **Action** element:

- Category: **QuantumFair**
- Action: **Quantum Random Assignment**
- Set input values:

| Input           | Value                                            |
| --------------- | ------------------------------------------------ |
| Record IDs      | `{!varLeadIds}`                                  |
| Assignee IDs    | `{!varRepIds}`                                   |
| Assignment Type | `Uniform`                                        |
| Purpose         | `Lead Round-Robin Assignment`                    |
| Use Bell Test   | `false` (set to `true` for maximum auditability) |

- Store output in `varJobId` and `varSuccess`

### Step 6: Handle the Async Result

The quantum job runs asynchronously. Results arrive via the `Quantum_Job_Complete__e` Platform Event. You have two options:

**Option A: Platform Event-Triggered Flow (Recommended)**

Create a second Flow triggered by `Quantum_Job_Complete__e`:

1. Match on `Job_Id__c` = the submitted job ID
2. Query `Quantum_Assignment__c` records for that job
3. Update each Lead's `OwnerId` to the assigned rep

**Option B: Check the Job Record**

The `Quantum_Job__c` record updates to `Completed` status. A time-based Flow can check for completed jobs and apply assignments.

### Step 7: Verify Fairness

After assignment completes:

1. Navigate to the **Quantum Job** record
2. Click the related **Fairness Certificate**
3. Verify the certificate shows `Status = Certified`
4. The certificate contains SHA-256 hashes of raw bits, debiased bits, and final assignments

## Assignment Distribution Example

With 10 leads and 3 reps, a `Uniform` assignment distributes leads as evenly as quantum randomness allows:

| Rep   | Expected | Typical Result |
| ----- | -------- | -------------- |
| Rep A | ~3.3     | 3 or 4         |
| Rep B | ~3.3     | 3 or 4         |
| Rep C | ~3.3     | 3 or 4         |

Over time, the distribution converges to perfectly uniform — and every batch has a certificate proving it.

## Scaling with Apex

For orgs processing 1,000+ leads per batch, call the invocable from Apex to handle collection building more efficiently:

```java
// Apex: Bulk lead assignment
List<QuantumRandomAssignment.Input> inputs = new List<QuantumRandomAssignment.Input>();
QuantumRandomAssignment.Input input = new QuantumRandomAssignment.Input();
input.recordIds = leadIds;        // List<String> of Lead IDs
input.assigneeIds = repIds;       // List<String> of User IDs
input.assignmentType = 'Uniform';
input.purpose = 'Bulk Lead Round-Robin';
inputs.add(input);

List<QuantumRandomAssignment.Output> outputs = QuantumRandomAssignment.assign(inputs);
String jobId = outputs[0].jobId;  // Track the async job
```

## Audit Trail

Every lead assignment batch creates:

1. A **Quantum Job** record with the circuit, raw measurements, and IBM job ID
2. A **Fairness Certificate** with cryptographic hashes
3. Individual **QRNG Assignment** records linking each lead to its assigned rep

Auditors can independently verify the assignment by:

- Checking the IBM Quantum job via the external Job ID
- Re-hashing the raw bitstring to confirm the certificate
- Re-running the deterministic assignment algorithm with the same bits

## Next Steps

- Enable **Bell Test** mode for high-stakes assignments (proves quantum origin via CHSH inequality violation)
- Add a **Weighted** assignment type if senior reps should receive more leads
- Build a **Report** on `Quantum_Assignment__c` to track distribution over time
