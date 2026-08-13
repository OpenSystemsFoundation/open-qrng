# QuantumFair (open-qrng)

**Certified quantum random number generation for Salesforce.**
Apache-2.0 | Open Source | Zero Infrastructure Cost

---

QuantumFair uses real IBM Quantum hardware to generate true randomness and creates immutable fairness certificates linked to every assignment. No external servers, no middleware. Everything runs on Salesforce.

## How It Works

1. **Request** — A Flow, Apex trigger, or LWC requests random values for a purpose (e.g., "assign 50 leads across 5 reps fairly"). The invocable action is bulk-safe: it inserts pending job records and submits them asynchronously, so it works from record-triggered Flows with up to 200 interviews per invocation.
2. **Generate** — Apex builds an ISA-compliant OpenQASM 3.0 circuit using native Heron r2 gates (`rz`, `sx`, `x`, `ecr`) and submits it to the IBM Quantum REST API (callouts authorized via Remote Site Settings).
3. **Execute** — IBM Quantum hardware runs the circuit. A Queueable/Schedulable chain polls for results with a stretching backoff and a 6-hour wall-clock budget; transient IBM errors are retried, never fatal.
4. **Certify** — Per-qubit von Neumann debiasing, then statistical validation (monobit, runs test, chi-squared) at alpha = 0.01. Certificates are chain-linked via SHA-256 hashes for tamper-evident ordering. SP 800-90B extended health tests run asynchronously and **revoke** the certificate if the pool fails them.
5. **Verify** — A separate CHSH Bell test provides evidence consistent with quantum origin: certification requires the S-value to exceed the classical bound of 2.0 by at least two standard errors ((S − 2.0) > 2σ_S), not just S > 2.0.
6. **Assign** — Quantum random bits drive the assignment via rejection sampling (no modulo bias). Assignments are deterministic given the certified bit pool, and the canonical assignment hash is stamped on the certificate so auditors can replay every draw.
7. **Audit** — Framework-agnostic compliance: evidence maps to ISO 27001, SOC 2, NIST 800-90B, GDPR, and eIDAS. Daily hash digests sent to an external compliance mailbox. Read-only `QuantumFair_Auditor` permission set for external auditors.

## Use Cases

| Process                   | Why Fairness Matters                          |
| ------------------------- | --------------------------------------------- |
| Lead distribution         | Reps contest "unfair" lead quality            |
| A/B test assignment       | Statistical validity requires true randomness |
| Audit sample selection    | Regulators require unbiased sampling          |
| Incentive lotteries       | Employee trust, legal requirements            |
| Case assignment           | Whistleblower protection, bias avoidance      |
| Interview panel selection | Demonstrable non-bias (EU AI Act)             |

## Tech Stack

| Layer          | Technology                                    |
| -------------- | --------------------------------------------- |
| Backend        | Apex (API v66.0, Spring '26)                  |
| Frontend       | Lightning Web Components (LWS)                |
| Visualizations | Canvas 2D (hand-rolled, no libs)              |
| Quantum        | IBM Quantum REST API (Heron r2)               |
| Architecture   | Multi-backend provider pattern, DTO layer     |
| Testing        | Apex Tests + sfdx-lwc-jest + Playwright       |
| Linting        | ESLint + Prettier (with Apex plugin)          |
| CI             | GitHub Actions + Salesforce CLI               |
| Distribution   | Unmanaged package / open-source source deploy |

## Distribution Model

QuantumFair is distributed as an **unmanaged package / open-source source deploy** — not a managed package. The namespace was removed; all metadata is un-namespaced and the app lives at `/lightning/n/QuantumFair`. An AppExchange listing is planned. Because unmanaged packages do not support install handlers, there is no InstallHandler — instead, background jobs are scheduled automatically from within the app (the sweeper and integrity-verification jobs start on the first successful settings save; the compliance digest starts when a compliance email is saved).

## Requirements

- Salesforce org: Enterprise, Unlimited, or Developer Edition
- IBM Quantum account (free Open Plan is sufficient)
- Salesforce CLI (`sf`) for development or source deploys

## Quick Start

```bash
git clone https://github.com/OpenSystemsFoundation/open-qrng.git
cd open-qrng
npm install

# Create scratch org
sf org create scratch -f config/project-scratch-def.json -a qrng-dev

# Deploy
sf project deploy start

# Assign admin permission set
sf org assign permset -n QuantumFair_Admin

# Open the org
sf org open
```

## Post-Install Setup (Admin)

1. **Deploy the source** (`sf project deploy start`) or install the unmanaged package into your org.
2. **Assign the `QuantumFair_Admin` permission set to your admin user.** This is required: privileged actions are gated by the `QuantumFair_Administer` custom permission, which is granted only by this permission set — the System Administrator profile alone is denied.
3. Open the **QuantumFair** app from the App Launcher (`/lightning/n/QuantumFair`) and go to the **Setup** tab.
4. **Enter your IBM Quantum API key** and save. Saving a working key automatically schedules the job sweeper and the nightly certificate integrity-verification job.
5. Optionally set a **Compliance Email** address — saving it automatically schedules the daily hash digest (06:00 org time); clearing it unschedules the digest.
6. **Test the connection** from the Setup tab (the key is verified against IBM IAM).
7. Assign `QuantumFair_User` to users who need random assignments, and `QuantumFair_Auditor` to external auditors (read-only).

## Personas & Security Model

Three permission sets define the app's personas. All three grant access to the `SetupController` Apex class and read access to the `Quantum_Job_Complete__e` / `Quantum_Job_Failed__e` Platform Events (required for the real-time UI):

| Permission set        | Persona          | Access                                                                                                                                                     |
| --------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `QuantumFair_Admin`   | Administrator    | Everything, including the `QuantumFair_Administer` custom permission that gates settings, scheduled-job control, backend verification, and evidence export |
| `QuantumFair_User`    | Business user    | Request assignments, view jobs/certificates/results                                                                                                        |
| `QuantumFair_Auditor` | External auditor | Read-only; raw and debiased bitstrings are withheld (field-level security enforced server-side via `Security.stripInaccessible` / `WITH USER_MODE`)        |

Key security properties (see [SECURITY.md](SECURITY.md) for the disclosure policy and full details):

- The IBM API key is stored in a **Protected hierarchy custom setting** (`Quantum_Settings__c.IBM_API_Key__c`), entered via the Setup tab. It is plaintext at rest — the tradeoff of an unmanaged, zero-infrastructure design — mitigated by: the Protected setting is hidden from ordinary users, the key is never returned to the client (`getSettings` exposes only a `hasApiKey` flag), never logged, and only ever sent to IBM IAM over TLS.
- All privileged `@AuraEnabled` methods check the `QuantumFair_Administer` custom permission.
- OWD is **Private** on all custom objects (detail objects inherit via Controlled by Parent).
- Settings changes are logged to `Compliance_Event__c` as `SETTINGS_CHANGED` events (the key value is never logged).
- Callouts are authorized by three Remote Site Settings: `IBM_IAM`, `IBM_Quantum_API`, `IBM_Resource_Controller`.

## Development

```bash
npm run test:unit           # 445 LWC Jest tests
npm run test:unit:coverage  # Tests with coverage
npm run test:e2e            # 147 Playwright E2E tests (mock fixture)
npm run lint                # ESLint
npm run prettier:verify     # Format check
npm run prettier            # Format fix
```

Apex: ~480 test methods across 30 test classes (`sf apex run test --code-coverage` against a scratch org).

See [ARCHITECTURE.md](ARCHITECTURE.md) for system design, [AGENTS.md](AGENTS.md) for AI-assisted development conventions, and [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute.

## Project Structure

```
open-qrng/
├── force-app/main/default/
│   ├── classes/              ← All Apex classes + tests (flat directory)
│   ├── lwc/
│   │   ├── quantumFairApp/           ← Main app shell (5-tab layout)
│   │   ├── qrngSetup/               ← Admin setup orchestrator
│   │   ├── qrngConnectionSetup/     ← API key + connection test
│   │   ├── qrngSettingsPanel/       ← Backend, shots, compliance email config
│   │   ├── qrngHealthMonitor/       ← Backend health with fidelity scoring
│   │   ├── qrngBackgroundJobs/      ← Scheduler management
│   │   ├── qrngJobDashboard/        ← Filterable job table with real-time updates
│   │   ├── qrngJobMonitor/          ← Real-time job status via empApi
│   │   ├── qrngJobStatusPanel/      ← Job type + status display
│   │   ├── qrngQasmViewer/          ← Canvas 2D OpenQASM circuit renderer
│   │   ├── qrngCircuitVisualizer/   ← Legacy circuit diagram
│   │   ├── qrngResultsVisualizer/   ← Canvas 2D measurement charts
│   │   ├── qrngValidationResults/   ← Statistical + CHSH results (job-type aware)
│   │   ├── qrngRequestForm/         ← Assignment request form
│   │   ├── qrngFairnessCertificate/ ← Certificate document view (works on record pages)
│   │   ├── qrngAssignmentTable/     ← Results table (DTO-based)
│   │   ├── qrngAuditTrail/          ← Historical timeline (real-time updates)
│   │   ├── qrngBellTestIndicator/   ← CSS gauge for CHSH S-value
│   │   ├── qrngChshVisualizer/      ← CHSH correlator breakdown chart
│   │   ├── qrngComplianceExport/    ← Framework evidence JSON download
│   │   ├── qrngEventSubscription/   ← Shared Platform Event subscription utility
│   │   └── qrngUtils/               ← Shared utilities (reduceErrors)
│   ├── objects/
│   │   ├── Quantum_Job__c/          ← Job records (assignment request JSON, poll tracking)
│   │   ├── Fairness_Certificate__c/ ← Chain-linked certificates with verification fields
│   │   ├── Quantum_Assignment__c/   ← Individual assignment records
│   │   ├── Quantum_Provider__c/     ← Quantum provider registry (IBM, future providers)
│   │   ├── Quantum_Backend__c/      ← Backend records + NIST 800-90B entropy fields
│   │   ├── Compliance_Event__c/     ← Compliance audit log
│   │   ├── Compliance_Control__mdt/ ← Control-to-framework mapping (24 seed records)
│   │   ├── Quantum_Settings__c/     ← Protected hierarchy custom settings
│   │   └── Quantum_Job_Complete__e / Quantum_Job_Failed__e  ← Platform Events
│   ├── customMetadata/       ← Compliance control seed records (ISO/SOC/NIST/GDPR/eIDAS)
│   ├── customPermissions/    ← QuantumFair_Administer
│   ├── remoteSiteSettings/   ← IBM_IAM, IBM_Quantum_API, IBM_Resource_Controller
│   ├── cachePartitions/      ← QuantumFair Platform Cache partition (IAM token cache)
│   ├── permissionsets/       ← QuantumFair_Admin, QuantumFair_User, QuantumFair_Auditor
│   ├── applications/, tabs/, layouts/, flexipages/, notificationtypes/
│   └── flows/                ← Sample flows (lead round robin, case routing, ...)
├── e2e/                      ← Playwright E2E tests (mock fixture)
├── config/                   ← Scratch org definition
├── docs/                     ← Production readiness review, tutorials, internal docs
├── ARCHITECTURE.md           ← Full system design (source of truth)
├── CLAUDE.md                 ← AI-assisted development config
├── AGENTS.md                 ← AI agent role definitions
├── SECURITY.md               ← Vulnerability disclosure policy
└── CONTRIBUTING.md           ← Contribution guide
```

## Roadmap

### Now (Current Sprint)

- Multi-provider architecture (IonQ simulator support alongside IBM Quantum)
- Generic provider abstraction for backend-agnostic job submission
- Scratch-org Playwright E2E project (the current suite runs against a mock fixture)

### Next (Upcoming)

- AppExchange listing (planned)
- Multi-backend failover with automatic least-busy routing
- Custom Labels for i18n support
- Big Object migration for high-volume compliance logging
- Enhanced CHSH visualization with correlator scatter plot

### Future (Longer Term)

- Additional quantum providers (Amazon Braket, Azure Quantum)
- Quantum Pareto (QAMOO) optimization package
- PQC readiness scanner
- Quantum key distribution integration
- Real-time CHSH violation monitoring dashboard

## License

Apache-2.0 — See [LICENSE](LICENSE) and [NOTICE](NOTICE)
