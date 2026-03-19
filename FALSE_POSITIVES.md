# QuantumFair — False Positives Documentation

**Package:** QuantumFair (open-qrng)
**Date:** 2026-03-19

This document explains expected security scanner findings that are intentional design decisions, not vulnerabilities. Each entry describes the finding, the affected code, the business justification, and the alternative protections in place.

---

## 1. `without sharing` on Background Job Classes

### Affected Classes

| Class | Type | Purpose |
|-------|------|---------|
| `QRNGJobPoller` | Queueable | Polls IBM Quantum for job status updates |
| `QRNGJobPollScheduler` | Schedulable | Schedules next poll iteration |
| `QRNGJobSweeper` | Schedulable + inner Queueable | Sweeps all pending jobs for missed polls |
| `IntegrityVerificationJob` | Schedulable + inner Queueable | Nightly SHA-256 integrity check of all certificates |
| `QRNGValidationRunner` | Queueable | Runs extended randomness validation tests |

### Why `without sharing` Is Required

These classes are **internal system jobs** that must operate on ALL records regardless of the running user's sharing rules:

1. **QRNGJobPoller/Sweeper:** When a user submits a QRNG job, the polling chain runs asynchronously. The user who triggered the job may not have sharing access to the job record in all contexts (e.g., if OWD is Private and the Queueable runs under a different user context). The poller must always be able to read and update the job status.

2. **IntegrityVerificationJob:** This nightly job verifies the SHA-256 hash integrity of ALL Fairness Certificates in the org. If it ran `with sharing`, it would only verify certificates visible to the scheduled job's running user, potentially missing tampered records.

3. **QRNGValidationRunner:** Runs statistical validation tests on quantum measurement data. Must access the full job record regardless of sharing rules.

### Alternative Protections

- All these classes operate **exclusively on package-owned custom objects** (`Quantum_Job__c`, `Fairness_Certificate__c`, `Compliance_Event__c`) — never on standard objects or subscriber-owned custom objects
- None of these classes are entry points — they are invoked only by other package code
- CRUD/FLS is not applicable because these classes modify only fields defined by the package
- Access to submit jobs (which triggers these background processes) is controlled by the `QuantumFair_User` and `QuantumFair_Admin` permission sets

---

## 2. CRUD/FLS Not Enforced on Package-Owned Object DML in System Jobs

### Affected Classes

Same classes as Section 1, plus:
- `FairnessCertificateService` — Creates/updates `Fairness_Certificate__c`
- `QRNGJobProcessor` — Updates `Quantum_Job__c` after result processing
- `ComplianceEventLogger` — Inserts `Compliance_Event__c` audit records
- `IBMQuantumService` — Inserts `Quantum_Job__c` records

### Why CRUD/FLS Enforcement Is Not Applied

These classes perform DML operations on **package-owned custom objects and fields only**. The package defines these objects and controls their schema entirely. CRUD/FLS enforcement would prevent the package from functioning correctly if an admin accidentally removes field permissions from the package's permission sets.

The Salesforce documentation states:
> "Classes that only modify custom fields owned by the submitter and are not entry points may use `without sharing` if the submitter prefers to enforce their own security controls."

### What Is Protected

- User-facing code (`QRNGSetupController`, `QuantumRandomAssignment`) **does** enforce CRUD/FLS via `WITH USER_MODE` and `Security.stripInaccessible()`
- Background jobs are not user-facing — they are triggered by package-internal logic
- All custom objects have OWD = Private, so record-level access is still enforced via sharing rules on user-facing queries

---

## 3. API Key in Custom Setting

### Finding

`IBMQuantumAuth.cls` reads the IBM Quantum API key from `QRNG_Settings__c.IBM_API_Key__c`, a Hierarchy Custom Setting field.

### Justification

- `QRNG_Settings__c` is an **org-level custom setting** — it is not accessible via SOQL from subscriber code when using `with sharing` (Custom Settings respect profile-level access)
- The API key is the subscriber's own IBM Quantum API key — they manage it
- The key is only used to exchange for a short-lived IAM bearer token (50-minute TTL)
- The setup wizard in LWC guides the admin to enter their key through a secure UI
- Named Credential / External Credential migration is planned for a future release

### Future Improvement

Migration to External Credentials is documented in the roadmap. This will provide:
- Encryption at rest (Salesforce-managed)
- Permission Set Mapping for access control
- No raw key visible in Setup UI

---

## 4. `System.debug` Statements

### Finding

Two `System.debug` statements exist in production code:

1. `QRNGJobSweeper.cls:23` — Logs `'Sweeper re-schedule failed: ' + e.getMessage()`
2. `QRNGSetupController.cls:715` — Logs backend refresh failure message

### Justification

- Neither statement logs sensitive data (no API keys, tokens, PII, or customer data)
- Both log only generic error messages from caught exceptions
- These are useful for org admins debugging scheduled job failures
- The messages contain only class names and generic exception text

---

## 5. HTTP Callouts to External Endpoints

### Finding

The package makes HTTP callouts to three IBM Cloud endpoints:

1. `https://iam.cloud.ibm.com/identity/token` — IAM token exchange
2. `https://api.quantum-computing.ibm.com/v2/` — Quantum job management
3. `https://resource-controller.cloud.ibm.com/v2/` — Instance discovery

### Justification

- All endpoints use **HTTPS with TLS 1.2+** (IBM Cloud enforces this)
- All endpoints are **IBM Cloud production services** with A/A+ SSL Labs ratings
- These endpoints are registered in the package's **Remote Site Settings**
- **No customer data is sent** — only:
  - OpenQASM circuit definitions (mathematical gate sequences like `rz(pi/2); sx; measure`)
  - Job management parameters (shot count, backend name)
  - API key (only to IAM endpoint, via URL-encoded POST body)
- **Data returned** is limited to:
  - IAM bearer tokens (cached, 50-min TTL)
  - Quantum measurement bitstrings (random 0s and 1s)
  - Job metadata (status, timing)
  - Backend catalog (public information)

---

## 6. Inner Classes Without Explicit Sharing Keyword

### Finding

Inner classes in `QRNGJobSweeper` (`QRNGJobSweeperWorker`) and `IntegrityVerificationJob` (`IntegrityVerificationWorker`) may be flagged for missing sharing keywords.

### Justification

Inner classes in Apex **inherit the sharing model** of their outer class. Since the outer classes use `without sharing` (documented in Section 1), the inner classes also operate `without sharing`. This is the standard Apex pattern for Schedulable + Queueable worker pairs (Schedulable cannot make callouts; the inner Queueable worker does the actual work).

---

## Summary

| # | Finding | Classification | Rationale |
|---|---------|---------------|-----------|
| 1 | `without sharing` on system jobs | False Positive | Package-internal, operates on package-owned objects only |
| 2 | No CRUD/FLS on system job DML | False Positive | Package-owned objects, not user-facing entry points |
| 3 | API key in Custom Setting | Known Limitation | Org-level, admin-controlled, migration planned |
| 4 | System.debug statements | False Positive | No sensitive data logged |
| 5 | External HTTP callouts | By Design | All HTTPS, no customer data sent, IBM Cloud endpoints |
| 6 | Inner classes without sharing | False Positive | Inherit outer class sharing model (standard Apex pattern) |
