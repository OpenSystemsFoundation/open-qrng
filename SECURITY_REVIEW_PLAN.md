# QuantumFair — Salesforce AppExchange Security Review Plan

**Date:** 2026-03-19
**Package:** QuantumFair (open-qrng)
**Version:** 0.1.0
**Target:** AppExchange Security Review (ISVforce Guide v66.0, Spring '26)

---

## Executive Summary

QuantumFair is a managed Salesforce package providing certified quantum random number generation (QRNG) for fair, auditable business process randomization. This document captures the complete security audit findings, remediation roadmap, and submission preparation plan for the Salesforce AppExchange Security Review.

### Current Status

| Area | Status | Details |
|------|--------|---------|
| LWC Jest Tests | PASS (283/283) | All 19 components passing |
| ESLint | PASS | Zero errors/warnings |
| Prettier | PASS | All files formatted |
| CRUD/FLS Enforcement | FAIL | No enforcement anywhere |
| Sharing Keywords | PARTIAL | 5 classes missing `with sharing` |
| SOQL Injection | PASS | No dynamic SOQL found |
| XSS | PASS | No innerHTML, eval, or external JS |
| API Key Storage | WARN | Using Custom Setting instead of Named Credential |
| System.debug | WARN | 2 instances need review |
| npm Audit | WARN | 9 vulnerabilities (7 low, 1 moderate, 1 high) |

---

## Critical Findings (Must Fix Before Submission)

### 1. CRUD/FLS Enforcement — MISSING EVERYWHERE (Severity: CRITICAL)

**This is the #1 reason for AppExchange security review failure.**

The codebase has **zero** CRUD/FLS enforcement. No instances of:
- `WITH SECURITY_ENFORCED`
- `WITH USER_MODE`
- `Security.stripInaccessible()`
- `Schema.DescribeSObjectResult.isAccessible()`/`isCreateable()`/etc.

All SOQL queries run in **system mode**, bypassing the subscriber org's field-level security settings.

#### Affected Classes (Production Code)

| Class | SOQL Queries | DML Operations | Fix Approach |
|-------|-------------|----------------|--------------|
| `QRNGSetupController` | ~20 queries | 8 DML ops | `WITH USER_MODE` on queries; `Security.stripInaccessible` on DML |
| `QRNGJobPoller` | 2 queries | 3 updates | `WITHOUT SHARING` + false positive doc (system job) |
| `QRNGJobSweeper` | 3 queries | 2 updates | `WITHOUT SHARING` + false positive doc (system job) |
| `QRNGJobProcessor` | ~5 queries | 3 updates | `WITHOUT SHARING` + false positive doc (system job) |
| `FairnessCertificateService` | ~3 queries | 2 upserts | `WITHOUT SHARING` + false positive doc (system job) |
| `QRNGValidationRunner` | 2 queries | 2 updates | `WITHOUT SHARING` + false positive doc (system job) |
| `IntegrityVerificationJob` | 4 queries | 2 updates | `WITHOUT SHARING` + false positive doc (system job) |
| `ComplianceEventLogger` | 0 queries | 2 inserts | `WITHOUT SHARING` + false positive doc (system job) |
| `ComplianceEvidenceExporter` | ~5 queries | 0 DML | `WITH USER_MODE` on queries |
| `ComplianceSummaryJob` | ~3 queries | 0 DML | `WITHOUT SHARING` + false positive doc (system job) |
| `ComplianceDigestJob` | ~3 queries | 0 DML | `WITHOUT SHARING` + false positive doc (system job) |
| `IBMQuantumService` | ~2 queries | 3 inserts | `WITHOUT SHARING` + false positive doc (system job) |
| `IBMQuantumAuth` | 1 query | 0 DML | Read-only custom setting (OK) |
| `QuantumAssignmentEngine` | 0 queries | 0 DML | Pure computation (OK) |
| `QuantumRandomAssignment` | ~2 queries | 1 update | `WITH USER_MODE` on queries |
| `ComplianceControlService` | ~5 queries | 0 DML | `WITH USER_MODE` on queries |

#### Recommended Fix Strategy

**User-facing code** (LWC controllers, invocable methods):
- Add `WITH USER_MODE` to all SOQL queries
- Use `Security.stripInaccessible(AccessType.READABLE, records)` before returning data to LWC
- Use `Security.stripInaccessible(AccessType.CREATABLE/UPDATABLE, records)` before DML

**System/background code** (Queueables, Schedulables, internal services):
- These classes operate on **package-owned custom objects only** (no standard objects, no subscriber data)
- Use explicit `without sharing` keyword with detailed class-level comments explaining the business justification
- Document as false positives in the security review submission

### 2. Missing Sharing Keywords (Severity: HIGH)

Five classes lack the `with sharing` / `without sharing` / `inherited sharing` keyword:

| Class | Type | Recommended Fix |
|-------|------|-----------------|
| `QRNGJobPoller` | Queueable (system job) | Add `without sharing` + comment |
| `QRNGJobPollScheduler` | Schedulable (system job) | Add `without sharing` + comment |
| `QRNGJobSweeper` | Schedulable (system job) | Add `without sharing` + comment |
| `IntegrityVerificationJob` | Schedulable (system job) | Add `without sharing` + comment |
| `QRNGValidationRunner` | Queueable (system job) | Add `without sharing` + comment |

**Justification:** These are internal system jobs that process package-owned custom object records. They are not user-facing entry points. They must operate on all records regardless of the running user's sharing rules to ensure data integrity (e.g., integrity verification must check ALL certificates, not just the running user's).

### 3. API Key Storage in Custom Setting (Severity: HIGH)

`IBMQuantumAuth.cls` reads the IBM API key from `QRNG_Settings__c.IBM_API_Key__c` (a Custom Setting field). The ARCHITECTURE.md describes using Named Credentials, but the actual implementation stores the API key in a Custom Setting.

**Issues:**
- Custom Setting values are **not encrypted at rest** (unlike External Credentials)
- Custom Setting values may be visible to admins via Setup UI
- The security review team will flag this as insecure credential storage

**Recommended Fix:**
- Migrate to **External Credentials** with a **Named Credential** for IBM Quantum API
- Store the API key as an Authentication Parameter on the External Credential's Permission Set Mapping
- The `QRNG_Settings__c.IBM_API_Key__c` field should be deprecated and eventually removed
- **Alternative (if Named Credential migration is deferred):** Document this as a known limitation and explain that the Custom Setting is org-level (not user-level) and requires Setup access to view

### 4. SObject Returned Directly to LWC (Severity: MEDIUM)

Two `@AuraEnabled` methods return SObjects directly instead of DTOs:

- `QRNGSetupController.getJobDetails()` — returns `Quantum_Job__c` with all fields including `Raw_Results__c`
- `QRNGSetupController.getCertificateByJobId()` — returns `Fairness_Certificate__c`

**Issue:** When SObjects are returned directly, FLS is not enforced on the response. Even with `with sharing`, field-level security is bypassed.

**Fix:** Apply `Security.stripInaccessible(AccessType.READABLE, records)` before returning, or convert to DTOs (like the other methods already do).

---

## Medium Findings

### 5. System.debug Statements (Severity: LOW)

Two `System.debug` statements found in production code:

| File | Line | Content | Risk |
|------|------|---------|------|
| `QRNGJobSweeper.cls` | 23 | `'Sweeper re-schedule failed: ' + e.getMessage()` | Low — error message only |
| `QRNGSetupController.cls` | 715 | Backend refresh failure message | Low — error message only |

**Fix:** Remove or guard with a debug-level check. No sensitive data (API keys, tokens, PII) is logged.

### 6. npm Dependency Vulnerabilities (Severity: LOW)

`npm audit` reports 9 vulnerabilities:
- **7 low:** `@tootallnate/once` (transitive via `sfdx-lwc-jest`)
- **1 moderate:** `fast-xml-parser` entity expansion
- **1 high:** `flatted` prototype pollution

**Fix:** Run `npm audit fix` for `fast-xml-parser` and `flatted`. The `@tootallnate/once` chain is in `sfdx-lwc-jest` (dev dependency only, not shipped in the package) — document as not applicable.

### 7. Error Message Exposure in AuraHandledException (Severity: LOW)

Several `@AuraEnabled` methods throw `AuraHandledException` with internal error details:
```apex
throw new AuraHandledException('Failed to get backends: ' + e.getMessage());
```

**Risk:** Internal error messages (stack traces, API response bodies) may leak to the UI.

**Fix:** Log the full error internally and throw a generic user-facing message:
```apex
throw new AuraHandledException('Failed to get backends. Please try again or contact your administrator.');
```

---

## What's Already Good (Passing)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| `with sharing` on service classes | PASS | 18/18 production service classes use `with sharing` |
| No dynamic SOQL | PASS | Zero instances of `Database.query()` or string concatenation in SOQL |
| No SOQL injection risk | PASS | All queries use bind variables (`:variableName`) |
| No external JavaScript | PASS | Zero `<script>` tags, no CDN references |
| No innerHTML / eval | PASS | Zero instances in LWC code |
| Canvas 2D only (no third-party libs) | PASS | All visualizations use native Canvas 2D API |
| Named Credential metadata packaged | PASS | `IBM_Quantum_Runtime.namedCredential-meta.xml` included |
| Permission Sets defined | PASS | Admin, User, and Auditor permission sets with proper FLS |
| No PII in circuits | PASS | Only circuit definitions (math) sent to IBM — no customer data |
| Platform Events for real-time | PASS | `empApi` used correctly in LWC |
| LWC Jest test coverage | PASS | 283 tests across 19 components |
| ESLint clean | PASS | Zero errors/warnings |
| Prettier formatted | PASS | All files pass format check |
| CSRF protection | PASS | All mutations use `@AuraEnabled` (Lightning handles CSRF tokens) |
| LWS compatible | PASS | No LWS-incompatible APIs used |

---

## Remediation Roadmap

### Phase 1: Critical Fixes (Must Complete Before Submission)

#### 1.1 Add CRUD/FLS Enforcement to User-Facing Code
**Effort:** Medium | **Risk:** Low (additive change)

Target classes (LWC controllers and invocable methods):
- `QRNGSetupController` — Add `WITH USER_MODE` to all SOQL; `stripInaccessible` on DML
- `QuantumRandomAssignment` — Add `WITH USER_MODE` to queries
- `ComplianceControlService` — Add `WITH USER_MODE` to queries
- `ComplianceEvidenceExporter` — Add `WITH USER_MODE` to queries

#### 1.2 Add Sharing Keywords to All Classes
**Effort:** Low | **Risk:** Low

- Add `without sharing` to: `QRNGJobPoller`, `QRNGJobPollScheduler`, `QRNGJobSweeper`, `IntegrityVerificationJob`, `QRNGValidationRunner`
- Add class-level comments explaining the business justification for `without sharing`

#### 1.3 Fix SObject Direct Returns
**Effort:** Low | **Risk:** Low

- `getJobDetails()` — Apply `stripInaccessible` or convert to DTO
- `getCertificateByJobId()` — Apply `stripInaccessible` or convert to DTO

#### 1.4 Remove/Guard System.debug
**Effort:** Trivial | **Risk:** None

- Remove the 2 `System.debug` statements in production code

### Phase 2: Recommended Improvements

#### 2.1 Migrate API Key to External Credential
**Effort:** High | **Risk:** Medium (breaking change for existing installs)

- Create proper External Credential with encrypted storage
- Deprecate `QRNG_Settings__c.IBM_API_Key__c`
- Update `IBMQuantumAuth` to read from External Credential
- Update setup wizard LWC to guide users through External Credential setup

#### 2.2 Sanitize Error Messages
**Effort:** Low | **Risk:** Low

- Replace internal error details in `AuraHandledException` with user-friendly messages
- Log full errors via `ComplianceEventLogger` for admin debugging

#### 2.3 Fix npm Vulnerabilities
**Effort:** Trivial | **Risk:** Low

- Run `npm audit fix` for fixable issues
- Document dev-only dependencies as not shipped in package

### Phase 3: Submission Preparation

#### 3.1 Run Salesforce Code Analyzer
- Install: `sf plugins install @salesforce/sfdx-scanner`
- Run: `sf scanner run --target force-app --format html --outfile code-analyzer-report.html`
- Address all findings or document as false positives

#### 3.2 Prepare Security Review Materials
See `SECURITY_REVIEW_SUBMISSION.md` for the full materials checklist.

#### 3.3 Create Test Org
- Create a scratch org with the package installed
- Assign permission sets
- Configure IBM Quantum connection (or document mock setup)
- Provide admin credentials to Salesforce security team

---

## Security Architecture Summary (For Submission)

### Data Flow

```
User (LWC) → Apex Controller → IBM Quantum REST API
                ↓                       ↓
         Custom Objects          Quantum Hardware
    (Quantum_Job__c,             (no customer data
     Fairness_Certificate__c,     sent — only circuit
     QRNG_Assignment__c)          definitions)
```

### What Data Leaves the Org

Only **OpenQASM circuit definitions** (mathematical gate sequences) are sent to IBM Quantum. These contain:
- Gate operations (`rz`, `sx`, `measure`)
- Qubit indices (integers)
- Shot count (integer)

**No customer data, PII, or org-specific information** is included in any external callout.

### What Data Returns to the Org

- Quantum measurement bitstrings (random 0s and 1s)
- Job metadata (status, timing, backend info)

### Credential Security

- IBM API key stored in `QRNG_Settings__c` (Custom Setting, org-level)
- IAM bearer token cached in static variable (transaction-scoped, 50-min TTL)
- All external callouts use HTTPS (TLS 1.2+)
- Named Credential metadata is packaged for future migration

### Access Control

- **OWD:** Private on all custom objects
- **Permission Sets:** Admin (full CRUD), User (read + create jobs), Auditor (read-only)
- **Sharing:** `with sharing` enforced on all user-facing classes
- **No global classes** (all are `public`)

---

## Appendix: File-by-File Security Matrix

| Class | Sharing | CRUD/FLS | Dynamic SOQL | External Callout | System.debug |
|-------|---------|----------|--------------|-----------------|--------------|
| QRNGSetupController | `with sharing` | NONE | No | Yes (via provider) | 1 |
| IBMQuantumService | `with sharing` | NONE | No | Yes | No |
| IBMQuantumAuth | `with sharing` | NONE | No | Yes | No |
| IBMQuantumProvider | `with sharing` | NONE | No | Yes | No |
| IBMResponseParser | `with sharing` | N/A (no SOQL) | No | No | No |
| QRNGCircuitBuilder | `with sharing` | N/A (no SOQL) | No | No | No |
| QRNGResultParser | `with sharing` | N/A (no SOQL) | No | No | No |
| QRNGValidator | `with sharing` | N/A (no SOQL) | No | No | No |
| QRNGJobPoller | **MISSING** | NONE | No | Yes (via provider) | No |
| QRNGJobPollScheduler | **MISSING** | N/A (no SOQL) | No | No | No |
| QRNGJobSweeper | **MISSING** | NONE | No | Yes (via provider) | 1 |
| QRNGJobProcessor | `with sharing` | NONE | No | No | No |
| QRNGValidationRunner | **MISSING** | NONE | No | No | No |
| IntegrityVerificationJob | **MISSING** | NONE | No | No | No |
| FairnessCertificateService | `with sharing` | NONE | No | No | No |
| QuantumAssignmentEngine | `with sharing` | N/A (no SOQL) | No | No | No |
| QuantumRandomAssignment | `with sharing` | NONE | No | No | No |
| ComplianceEventLogger | `with sharing` | NONE | No | No | No |
| ComplianceEvidenceExporter | `with sharing` | NONE | No | No | No |
| ComplianceControlService | `with sharing` | NONE | No | No | No |
| ComplianceSummaryJob | `with sharing` | NONE | No | No | No |
| ComplianceDigestJob | `with sharing` | NONE | No | No | No |
| QuantumProviderFactory | `with sharing` | NONE | No | No | No |
| QuantumProvider | interface | N/A | N/A | N/A | N/A |
| QRNGConsumer | interface | N/A | N/A | N/A | N/A |
| QRNGException | exception | N/A | N/A | N/A | N/A |

---

## References

- [Security Requirements for AppExchange Partners](https://developer.salesforce.com/docs/atlas.en-us.packagingGuide.meta/packagingGuide/security_review_create_secure_solution.htm)
- [Required Materials for Security Review Submission](https://developer.salesforce.com/docs/atlas.en-us.packagingGuide.meta/packagingGuide/security_review_required_materials.htm)
- [Top 20 Vulnerabilities Found in AppExchange Security Review](https://developer.salesforce.com/blogs/2023/08/the-top-20-vulnerabilities-found-in-the-appexchange-security-review)
- [Prepare Your App to Pass the Security Review](https://developer.salesforce.com/blogs/2023/04/prepare-your-app-to-pass-the-appexchange-security-review)
- [Trailhead: Security Review Submission Process](https://trailhead.salesforce.com/content/learn/modules/isv_security_review/isv_security_review_submit)
- [ISVforce Guide PDF (Spring '26)](https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_packaging_guide.pdf)
