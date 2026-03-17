# QuantumFair Manual Testing Guide

**Date:** 2026-03-17
**Org Alias:** opendev
**Scratch Org User:** test-msvnjpolyhby@example.com
**Namespace:** OpenSF

---

## Prerequisites

- Salesforce CLI (`sf`) installed
- Access to the `opendev` scratch org
- An IBM Quantum account with API key (free Open Plan is sufficient: https://quantum.cloud.ibm.com)

## 1. Open the Scratch Org

```bash
sf org open -o opendev
```

## 2. Verify Permission Set Assignment

The `QuantumFair_Admin` permission set should already be assigned. Verify:

1. Go to **Setup > Users > Permission Set Assignments**
2. Confirm `QuantumFair Admin` is assigned to your user

If not assigned:
```bash
sf org assign permset -n OpenSF__QuantumFair_Admin -o opendev
```

## 3. Configure IBM Quantum API Key

### Option A: Via the QuantumFair UI

1. In App Launcher, search for **QuantumFair** and open the tab
2. Click the **Setup** tab
3. Enter your IBM Quantum API key in the "IBM Quantum API Key" field
4. Click **Save Settings**
5. Click **Test Connection** — should show "Connected"

### Option B: Via Custom Setting in Setup

1. Go to **Setup > Custom Settings**
2. Find **QRNG Settings** and click **Manage**
3. Click **New** (for org-level defaults)
4. Enter:
   - **IBM API Key:** your IBM Quantum API key
   - **Default Backend:** `ibm_kingston`
   - **Default Shots:** `1024`
   - **Use Bell Test:** unchecked
5. Click **Save**

### Getting an IBM Quantum API Key

1. Go to https://quantum.cloud.ibm.com
2. Create an account (free)
3. Go to **Account Settings > API Token**
4. Copy your API token

## 4. Test the QuantumFair App

### 4.1 Navigate to QuantumFair

1. Open the **App Launcher** (grid icon, top left)
2. Search for "QuantumFair" and click the tab
3. You should see the main app with three tabs: **Dashboard**, **Setup**, **Audit Trail**

### 4.2 Test Connection (Setup Tab)

1. Click the **Setup** tab
2. Click **Test Connection**
3. **Expected:** Badge changes to "Connected", message shows "Connected to IBM Quantum"
4. Available backends should populate in the dropdown
5. Verify the Usage Dashboard shows 0 for all counters

### 4.3 Submit a Quantum Job (Dashboard Tab)

1. Click the **Dashboard** tab
2. In the "Request Quantum Random Assignment" form:
   - **Backend:** ibm_kingston (default)
   - **Number of Qubits:** 4 (start small for testing)
   - **Shots:** 100 (start small to save IBM minutes)
   - **Purpose:** "Manual testing - first QRNG job"
   - **Use Bell Test:** unchecked
3. You should see a circuit diagram preview below the form (4 qubits, each with H gate and measurement)
4. Click **Generate Quantum Random Numbers**
5. **Expected:** Toast message "Job Submitted"
6. The Job Monitor should appear below showing:
   - Status path: Submitted → Queued → Running → Completed
   - Job details (backend, qubits, shots)

### 4.4 Monitor Job Progress

1. After submission, the Job Monitor shows real-time status via Platform Events
2. Watch the progress indicator advance through stages
3. **Typical timing:** 10s-2min depending on IBM queue
4. On completion:
   - Status should show "Completed"
   - A Fairness Certificate should appear
   - A measurement distribution chart should render (Canvas 2D bar chart)

### 4.5 Verify the Fairness Certificate

1. After job completion, the certificate viewer should show:
   - Certificate ID (e.g., CERT-0001)
   - Visual hash (colored pixel art grid generated from SHA-256)
   - IBM Job ID
   - Backend name
   - SHA-256 hashes (raw bitstring, debiased)
   - Validation results (Frequency Test, Runs Test, Chi-Squared — all should show green checkmarks)
   - Status badge: "Certified"
2. Click **Verify Integrity**
3. **Expected:** "Integrity verified - all hashes match"

### 4.6 Test Bell-Test Mode

1. Go back to the Dashboard tab
2. In the request form:
   - **Number of Qubits:** 4
   - **Shots:** 4096 (need more shots for CHSH statistical significance)
   - **Purpose:** "Bell test verification"
   - **Use Bell Test:** checked
3. The circuit diagram should change to show entangled pairs (ECR gates connecting qubit pairs)
4. Submit the job
5. On completion, the certificate should show a CHSH S-Value gauge
6. **Expected:** S > 2.0 indicates quantum-certified randomness (may vary based on hardware noise)

### 4.7 Check the Audit Trail

1. Click the **Audit Trail** tab
2. You should see both completed jobs listed with:
   - Certificate name
   - Purpose
   - Status badge (Certified/Failed)
   - Backend and IBM Job ID
   - Timestamp
3. Click on a certificate name to open the detail modal

## 5. Test Custom Object Records

### 5.1 Quantum Jobs

1. Open the **Quantum Jobs** tab (may need to add it via App Launcher)
2. Verify your submitted jobs appear with correct data
3. Click into a completed job and verify:
   - All fields populated (IBM Job ID, Backend, Status, Circuit QASM, etc.)
   - Raw Results and Debiased Results contain bitstrings
   - Related Fairness Certificates list shows the certificate

### 5.2 Fairness Certificates

1. Open the **Fairness Certificates** tab
2. Verify certificates linked to completed jobs
3. Check all hash fields are populated (64-character hex strings)
4. Check Validation Results contains JSON with test results

## 6. Test Flow Integration

The `QuantumRandomAssignment` invocable action is available in Flow Builder:

1. Go to **Setup > Process Automation > Flows**
2. Create a new **Screen Flow**
3. Add an Action element
4. Search for "Quantum Random Assignment"
5. The action should appear with these inputs:
   - Record IDs (required)
   - Assignee IDs
   - Assignment Type (Uniform/Weighted/Subset)
   - Purpose (required)
   - Number of Qubits
   - Backend
   - Use Bell Test
6. You don't need to activate this flow — just verify the action is available

## 7. Verify Remote Site Settings

1. Go to **Setup > Security > Remote Site Settings**
2. Verify two entries exist:
   - **IBM_Quantum_API** → https://quantum.cloud.ibm.com
   - **IBM_IAM** → https://iam.cloud.ibm.com

## 8. Run Apex Tests (CLI)

```bash
sf apex run test -o opendev --code-coverage --result-format human --wait 10
```

**Expected:** 56 tests, 100% pass rate, ~79% org-wide coverage

## 9. Known Limitations for Testing

- **IBM Queue Times:** Job execution depends on IBM Quantum queue availability. During peak times, jobs may take several minutes.
- **Bell Test S-Value:** The CHSH S-value depends on quantum hardware noise. Current Heron r2 devices typically achieve S ≈ 2.5-2.7 (theoretical maximum is 2√2 ≈ 2.828).
- **IBM Minutes:** Each test circuit uses IBM quantum minutes from your account. Use small qubit/shot counts for testing to conserve minutes.
- **Platform Events:** The real-time job monitoring relies on empApi (Platform Events). If the browser session times out, you may need to refresh to see updated status.
- **Custom Setting Visibility:** The QRNG Settings custom setting has "Protected" visibility, meaning it's only accessible within the OpenSF namespace. This is by design for managed package security.

## 10. Cleanup

To delete the scratch org when done testing:
```bash
sf org delete scratch -o opendev --no-prompt
```

To create a fresh scratch org:
```bash
sf org create scratch -f config/project-scratch-def.json -a opendev -d 7
sf project deploy start -o opendev
sf org assign permset -n OpenSF__QuantumFair_Admin -o opendev
```
