# QuantumFair — Security Review Submission Checklist

**Target:** Salesforce AppExchange Security Review
**Package Type:** 2GP Managed Package
**Architecture:** Apex + LWC + IBM Quantum REST API (external callout)

---

## Pre-Submission Checklist

### 1. Package Requirements

- [ ] Package is a **managed 2GP** created from an ACTIVE Partner Business Org (PBO) Dev Hub
- [ ] Package version is uploaded and ready (not beta)
- [ ] Package namespace is registered
- [ ] All Apex classes have 90%+ test coverage
- [ ] All tests pass in a clean scratch org

### 2. Code Security (Apex)

- [ ] **CRUD/FLS enforced** on all user-facing SOQL queries (`WITH USER_MODE` or `WITH SECURITY_ENFORCED`)
- [ ] **CRUD/FLS enforced** on all DML operations (`Security.stripInaccessible()`)
- [ ] **Sharing keyword** declared on every class (`with sharing`, `without sharing`, or `inherited sharing`)
- [ ] **No dynamic SOQL** without bind variables (SOQL injection prevention)
- [ ] **No `System.debug`** with sensitive data (API keys, tokens, PII)
- [ ] **No hardcoded credentials** in source code
- [ ] **AuraHandledException** messages sanitized (no internal error details)
- [ ] All external callouts use **HTTPS** (TLS 1.2+)
- [ ] API credentials stored in **External Credentials / Named Credentials** (not plain text)

### 3. Code Security (LWC)

- [ ] **No external JavaScript** (all JS bundled as static resources or in LWC modules)
- [ ] **No innerHTML** or `lwc:dom="manual"` usage
- [ ] **No eval()** or dynamic code execution
- [ ] **No third-party libraries** (all visualizations hand-rolled with Canvas 2D)
- [ ] LWS (Lightning Web Security) compatible
- [ ] CSP (Content Security Policy) compliant

### 4. Data Security

- [ ] **OWD = Private** on all custom objects
- [ ] **Permission Sets** defined with appropriate FLS for Admin, User, Auditor roles
- [ ] **No PII** sent in external callouts
- [ ] **No customer data** in quantum circuits (only math)
- [ ] Sensitive fields (API keys) stored encrypted

### 5. Static Analysis

- [ ] **Salesforce Code Analyzer** report generated and clean (or false positives documented)
- [ ] **ESLint** passing with zero errors/warnings
- [ ] **Prettier** formatting verified
- [ ] **npm audit** — no high/critical vulnerabilities in shipped code

### 6. Test Coverage

- [ ] **Apex unit tests:** 90%+ coverage per class
- [ ] **LWC Jest tests:** All components covered (currently 283 tests, 19 suites)
- [ ] **Integration tests:** End-to-end flow tested with mock IBM responses
- [ ] **Negative tests:** Error paths, invalid inputs, governor limits tested

---

## Required Submission Materials

### Document 1: Architecture & Data Flow Diagram

**File:** `ARCHITECTURE.md` (already exists)

Must include:
- System architecture diagram showing all components
- Data flow diagram showing what data enters and leaves the org
- External endpoint inventory (IBM Quantum REST API)
- Authentication flow (IAM token exchange)
- Description of all custom objects and their relationships

### Document 2: Salesforce Code Analyzer Report

**How to generate:**
```bash
# Install the scanner plugin
sf plugins install @salesforce/sfdx-scanner

# Run the full scan
sf scanner run --target force-app --format html --outfile reports/code-analyzer-report.html

# Run with specific rules for security
sf scanner run --target force-app --category Security --format html --outfile reports/security-scan.html
```

### Document 3: False Positives Documentation

**File:** `FALSE_POSITIVES.md`

Document any Code Analyzer findings that are false positives with:
- The specific rule/violation
- The affected class and line number
- Why it's a false positive
- What alternative protection is in place

### Document 4: External Endpoint Inventory

| Endpoint | Purpose | Auth Method | Data Sent |
|----------|---------|-------------|-----------|
| `https://iam.cloud.ibm.com/identity/token` | IAM token exchange | API key (POST body, URL-encoded) | API key only |
| `https://api.quantum-computing.ibm.com/v2/` | Quantum job management | Bearer token (IAM) | OpenQASM circuits, shot count |
| `https://resource-controller.cloud.ibm.com/v2/` | Instance discovery | Bearer token (IAM) | None (GET only) |

**Note:** All endpoints use HTTPS (TLS 1.2+). No customer data is sent — only quantum circuit definitions (mathematical gate sequences) and job management parameters.

### Document 5: Test Environment Setup Guide

**For the Salesforce Security Review Team:**

1. **Log in** to the test org with the provided admin credentials
2. **Assign** `QuantumFair_Admin` permission set to your user
3. **Navigate** to the QuantumFair app (App Launcher > QuantumFair)
4. **Configure** IBM Quantum connection:
   - Go to QuantumFair Setup tab
   - Enter the provided IBM Quantum API key
   - Click "Test Connection"
   - Select a backend (e.g., `ibm_brisbane`)
5. **Submit a test job:**
   - Click "New QRNG Job"
   - Set qubits = 8, shots = 1024
   - Click "Submit"
   - Observe real-time status updates via Platform Events
6. **View results:**
   - Circuit visualization (Canvas 2D)
   - Measurement distribution chart
   - Fairness Certificate with SHA-256 hashes
   - Statistical validation results

### Document 6: Permission Set Documentation

| Permission Set | Purpose | Object Access | Who Gets It |
|---------------|---------|---------------|-------------|
| `QuantumFair_Admin` | Full administration | Full CRUD on all objects, ViewAllRecords | Org admins who configure IBM connection |
| `QuantumFair_User` | Standard usage | Create jobs, Read all objects | Users who request random assignments |
| `QuantumFair_Auditor` | Read-only audit | Read-only on all objects | Compliance officers reviewing certificates |

---

## External Endpoint Security Requirements

All external endpoints must receive an **A grade** on SSL Labs. Verify:

```bash
# Check IBM IAM endpoint
curl -sI https://iam.cloud.ibm.com/identity/token | head -5

# Check IBM Quantum API endpoint
curl -sI https://api.quantum-computing.ibm.com | head -5

# Check IBM Resource Controller endpoint
curl -sI https://resource-controller.cloud.ibm.com | head -5
```

These are IBM Cloud production endpoints and should consistently score A or A+ on SSL Labs.

---

## Submission Timeline

| Step | Action | ETA |
|------|--------|-----|
| 1 | Complete Phase 1 critical fixes (CRUD/FLS, sharing) | 1-2 days |
| 2 | Run Salesforce Code Analyzer and address findings | 1 day |
| 3 | Prepare test org with IBM Quantum connection | 1 day |
| 4 | Compile all submission documents | 1 day |
| 5 | Submit via Partner Publishing Console | Day 5 |
| 6 | Review period (typical) | 4-5 weeks |

---

## Fee

- **Free apps:** No fee
- **Paid apps:** $999 per submission attempt

QuantumFair is a **free** AppExchange listing (Apache-2.0), so no fee applies (fee waiver code may be requested if needed).

---

## Post-Submission

- Respond promptly to any security team questions
- Fix any findings and resubmit if needed (most apps pass on 2nd attempt)
- After approval: annual re-review may be required
- New package versions: attestation only (no full re-review unless architectural changes)
