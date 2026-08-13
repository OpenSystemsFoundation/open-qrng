# QuantumFair Flow Templates

Out-of-the-box Salesforce Flow templates that ship with QuantumFair. These templates use **standard Salesforce objects** (Lead, Case, Opportunity, Account) so they work in every org without customization.

## How to Use a Template

1. Go to **Setup > Flows > New Flow**
2. Select **Build from a Template** (or look in the template gallery)
3. Search for **"QRNG"** to find all QuantumFair templates
4. Select a template and click **Create**
5. Update the **TODO** items (queue IDs, group IDs, filters) for your org
6. Save, activate, and test

> **Tip:** Templates are created in **Draft** status. You must customize the placeholder values (marked with `TODO` comments) before activating.

## Available Templates

### 1. QRNG Lead Round-Robin Assignment

| Property            | Value                                                 |
| ------------------- | ----------------------------------------------------- |
| **Object**          | Lead                                                  |
| **Flow Type**       | Record-Triggered (After Create)                       |
| **Assignment Mode** | Uniform                                               |
| **Use Case**        | Distribute new inbound leads fairly across sales reps |

**What it does:**

- Triggers when a Lead is created with a specific queue owner
- Queries all unassigned Leads in that queue
- Gets sales reps from a Group/Queue
- Calls QuantumFair for provably fair Uniform distribution

**Customize:**

- `varQueueId` — your unassigned Lead queue ID
- `varRepGroupId` — your sales rep group/queue ID
- Entry condition filters (Status, Lead Source, etc.)

**Pair with:** A Platform Event-Triggered Flow on `QRNG_Complete__e` to auto-update Lead `OwnerId` fields.

**Tutorial:** [Lead Round-Robin Assignment](sales/lead-round-robin.md)

---

### 2. QRNG Case Routing

| Property            | Value                                                 |
| ------------------- | ----------------------------------------------------- |
| **Object**          | Case                                                  |
| **Flow Type**       | Record-Triggered (After Create)                       |
| **Assignment Mode** | Uniform                                               |
| **Use Case**        | Route support cases to agents with certified fairness |

**What it does:**

- Triggers when a Case is created in a support queue
- Queries open Cases in that queue
- Gets support agents from a Group/Queue
- Calls QuantumFair for fair agent assignment

**Customize:**

- `varSupportQueueId` — your support queue ID
- `varAgentGroupId` — your agent group/queue ID
- Consider adding a Scheduled Path (every 15 min) for high-volume orgs

**Pair with:** A Platform Event-Triggered Flow on `QRNG_Complete__e` to auto-update Case `OwnerId` fields and notify agents.

**Tutorial:** [Case Routing](customer-service/case-routing.md)

---

### 3. QRNG Opportunity Review Selection

| Property            | Value                                         |
| ------------------- | --------------------------------------------- |
| **Object**          | Opportunity                                   |
| **Flow Type**       | Schedule-Triggered (Weekly)                   |
| **Assignment Mode** | Subset                                        |
| **Use Case**        | Select deals for pipeline review without bias |

**What it does:**

- Runs weekly on a schedule
- Queries open Opportunities above a dollar threshold
- Uses Subset mode to select a random sample for review
- No assignees needed — it selects _which_ deals, not _who_ reviews them

**Customize:**

- `varSampleSize` — number of deals to select (default: 10)
- `varAmountThreshold` — minimum deal amount (default: $50,000)
- Schedule frequency and start time
- Add filters for stage, close date, etc.

**Pair with:** A Platform Event-Triggered Flow on `QRNG_Complete__e` to create review Tasks on selected Opportunities.

**Tutorial:** [Deal Review Selection](sales/deal-review-selection.md)

---

### 4. QRNG Account Territory Rebalance

| Property            | Value                                      |
| ------------------- | ------------------------------------------ |
| **Object**          | Account                                    |
| **Flow Type**       | Screen Flow (admin-launched)               |
| **Assignment Mode** | Uniform or Weighted (user choice)          |
| **Use Case**        | Reassign accounts during territory changes |

**What it does:**

- Admin launches the flow manually
- Screen collects: assignment type, weights, purpose, Bell Test toggle
- Queries Accounts (customize filters for your territory)
- Gets target reps from a Group/Queue
- Calls QuantumFair with the selected configuration
- Shows confirmation screen with Job ID

**Customize:**

- `varRepGroupId` — your target rep group/queue ID
- Account query filters (territory, industry, type, etc.)
- Default Bell Test setting (enabled by default for high-stakes rebalances)

**Pair with:** A Platform Event-Triggered Flow on `QRNG_Complete__e` to auto-update Account `OwnerId` fields.

**Tutorial:** [Territory Rebalancing](sales/territory-rebalancing.md)

---

### 5. QRNG Generic Record Assignment

| Property            | Value                                        |
| ------------------- | -------------------------------------------- |
| **Object**          | Any                                          |
| **Flow Type**       | Screen Flow                                  |
| **Assignment Mode** | All three (Uniform, Weighted, Subset)        |
| **Use Case**        | Copy-and-adapt starting point for any object |

**What it does:**

- Screen collects: record IDs, assignee IDs, assignment type, weights, sample size, purpose, Bell Test
- Accepts comma-separated IDs as text input (replace with Get Records for production use)
- Routes to the correct QuantumFair action call based on assignment type
- Shows result screen with Job ID and next steps

**How to adapt:**

1. Create a new Flow from this template
2. Replace the text input fields with **Get Records** elements for your specific object
3. Add loops to extract IDs into the `varRecordIds` and `varAssigneeIds` collections
4. Optionally change the trigger type (Record-Triggered, Scheduled, etc.)
5. Add a Platform Event-Triggered companion Flow for `QRNG_Complete__e`

This template demonstrates all three assignment modes and is the fastest way to get started with any custom or industry object.

---

## Completing the Async Loop

All templates submit the quantum job asynchronously. To auto-apply results, create a **companion flow**:

### Platform Event-Triggered Flow (QRNG_Complete\_\_e)

1. **Trigger:** `QRNG_Complete__e` Platform Event
2. **Get Records:** Query `QRNG_Assignment__c` where `Quantum_Job__c` matches `Job_Id__c` from the event
3. **Loop + Update:** For each assignment record, update the source record's `OwnerId` (or relevant field) to the assigned value
4. **Optional:** Send notifications, create Tasks, log audit entries

This companion pattern is the same for all templates — only the update target (Lead, Case, Account, Opportunity) differs.

## Template Coverage Matrix

| Tutorial Domain                | Standard Object | Template                           | Why / Why Not                           |
| ------------------------------ | --------------- | ---------------------------------- | --------------------------------------- |
| Sales: Lead Round-Robin        | Lead            | **QRNG_Lead_Round_Robin**          | Every org has Leads                     |
| Sales: Territory Rebalance     | Account         | **QRNG_Account_Rebalance**         | Every org has Accounts                  |
| Sales: Deal Review             | Opportunity     | **QRNG_Opportunity_Review**        | Every org has Opportunities             |
| Customer Service: Case Routing | Case            | **QRNG_Case_Routing**              | Every org has Cases                     |
| Any domain                     | Any object      | **QRNG_Generic_Record_Assignment** | Copy and adapt                          |
| Healthcare                     | Custom objects  | Use Generic template               | Requires Health Cloud or custom objects |
| Financial Services             | Custom objects  | Use Generic template               | Requires FSC or custom objects          |
| Education                      | Custom objects  | Use Generic template               | Requires EDA or custom objects          |
| Government                     | Custom objects  | Use Generic template               | Requires custom objects                 |
| Human Resources                | Custom objects  | Use Generic template               | Requires custom objects                 |

## What About Contacts?

Contacts don't have a common out-of-the-box assignment scenario like Leads or Cases. However, you can easily adapt the **Generic template** or the **Lead Round-Robin template** for Contact assignment by:

1. Changing the trigger object from Lead to Contact
2. Adjusting the query filters
3. Updating the `OwnerId` assignment in the companion flow

The pattern is identical — only the object name and filter criteria change.
