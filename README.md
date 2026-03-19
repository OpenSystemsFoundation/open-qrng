# QuantumFair (open-qrng)

**Certified quantum random number generation for Salesforce.**
Apache-2.0 | Free on AppExchange | Zero Infrastructure Cost

---

QuantumFair uses real IBM Quantum hardware to generate true randomness — provable by the laws of physics — and creates immutable fairness certificates linked to every assignment. No external servers, no middleware. Everything runs on Salesforce.

## How It Works

1. **Request** — A Flow, Apex trigger, or LWC requests random values for a purpose (e.g., "assign 50 leads across 5 reps fairly")
2. **Generate** — Apex builds an ISA-compliant OpenQASM 3.0 circuit using native Heron r2 gates (`rz`, `sx`, `x`, `ecr`) and submits it to IBM Quantum via Named Credentials
3. **Execute** — IBM Quantum hardware runs the circuit. A Queueable chain polls for results.
4. **Certify** — Statistical validation (monobit, runs test, chi-squared). Certificates are chain-linked via SHA-256 hashes for tamper-evident ordering.
5. **Verify** — A separate CHSH Bell test circuit proves quantum origin (S > 2.0 violates classical bounds). Results include correlator breakdown and S-value visualization.
6. **Assign** — Quantum random bits drive the assignment. The certificate links to every assigned record.
7. **Audit** — Framework-agnostic compliance: evidence maps to ISO 27001, SOC 2, NIST 800-90B, GDPR, and eIDAS. Daily hash digests sent to external compliance mailbox. Read-only `QuantumFair_Auditor` permission set for external auditors.

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

| Layer          | Technology                                |
| -------------- | ----------------------------------------- |
| Backend        | Apex (API v66.0, Spring '26)              |
| Frontend       | Lightning Web Components (LWS)            |
| Visualizations | Canvas 2D (hand-rolled, no libs)          |
| Quantum        | IBM Quantum REST API (Heron r2)           |
| Architecture   | Multi-backend provider pattern, DTO layer |
| Testing        | Apex Tests + sfdx-lwc-jest                |
| Linting        | ESLint + Prettier (with Apex plugin)      |
| CI             | GitHub Actions + Salesforce CLI           |
| Package        | 2GP Managed Package                       |

## Requirements

- Salesforce org: Enterprise, Unlimited, or Developer Edition
- IBM Quantum account (free Open Plan is sufficient)
- Salesforce CLI (`sf`) for development

## Quick Start

```bash
git clone <repo-url>
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

## Post-Install Setup

1. Assign `QuantumFair_Admin` permission set to your admin user
2. Open the **QuantumFair** app from the App Launcher
3. Go to the **Setup** tab → **Connection** section
4. Enter your IBM Quantum API key — connection is tested automatically on save
5. Configure default backend (defaults to "Least Busy") and shots in **Settings**
6. Optionally set a **Compliance Email** address for daily hash digest reports
7. Assign `QuantumFair_User` permission set to users who need random assignments
8. Assign `QuantumFair_Auditor` permission set to external auditors (read-only access)

## Development

```bash
npm run test:unit           # LWC Jest tests
npm run test:unit:coverage  # Tests with coverage
npm run lint                # ESLint
npm run prettier:verify     # Format check
npm run prettier            # Format fix
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for system design and [AGENTS.md](AGENTS.md) for AI-assisted development conventions.

## Project Structure

```
open-qrng/
├── force-app/main/default/
│   ├── classes/
│   │   ├── api/              ← IBM Quantum integration (auth, REST client, provider)
│   │   ├── circuits/         ← OpenQASM 3.0 circuit generation (ISA-compliant)
│   │   ├── jobs/             ← Async polling (Queueable chain), sweeper, scheduler
│   │   ├── results/          ← Result parsing, von Neumann debiasing, validation
│   │   ├── certificates/     ← Fairness certificate service, integrity verification
│   │   ├── compliance/       ← Event logger, digest email, summary job, evidence export
│   │   ├── controllers/      ← LWC controllers, @InvocableMethod for Flow
│   │   ├── shared/           ← Provider interface, factory, consumer interface, exceptions
│   │   └── tests/            ← All @isTest classes
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
│   │   ├── qrngFairnessCertificate/ ← Certificate document view
│   │   ├── qrngAssignmentTable/     ← Results table
│   │   ├── qrngAuditTrail/          ← Historical timeline (real-time updates)
│   │   ├── qrngBellTestIndicator/   ← CSS gauge for CHSH S-value
│   │   ├── qrngChshVisualizer/      ← CHSH correlator breakdown chart
│   │   ├── qrngComplianceExport/    ← Framework evidence JSON download
│   │   └── qrngEventSubscription/   ← Shared Platform Event subscription utility
│   ├── objects/
│   │   ├── Quantum_Job__c/          ← Job records with QPU time tracking
│   │   ├── Fairness_Certificate__c/ ← Chain-linked certificates with verification fields
│   │   ├── Quantum_Assignment__c/      ← Individual assignment records
│   │   ├── Quantum_Backend__c/         ← Backend config + NIST 800-90B entropy fields
│   │   ├── Compliance_Event__c/     ← Exception-only compliance audit log
│   │   ├── Compliance_Control__mdt/ ← Control-to-framework mapping (24 seed records)
│   │   └── Quantum_Settings__c/        ← Hierarchy custom settings
│   ├── customMetadata/       ← Compliance control seed records (ISO/SOC/NIST/GDPR/eIDAS)
│   ├── namedCredentials/     ← IBM_Quantum_Runtime, IBM_Quantum External Credential
│   ├── permissionsets/       ← QuantumFair_Admin, QuantumFair_User, QuantumFair_Auditor
│   ├── layouts/              ← Page layouts for all custom objects
│   ├── flexipages/           ← Record pages for Job, Certificate, Compliance Event
│   └── flows/                ← Sample: Quantum Random Lead Assignment
├── config/                   ← Scratch org definition
├── ARCHITECTURE.md           ← Full system design (source of truth)
├── CLAUDE.md                 ← AI-assisted development config
└── AGENTS.md                 ← AI agent role definitions
```

## Roadmap

### Now (Current Sprint)

- Multi-provider architecture (IonQ simulator support alongside IBM Quantum)
- Generic provider abstraction for backend-agnostic job submission
- Flow-based quantum assignment builder
- Assignment engine integration with fairness certificates

### Next (Upcoming)

- AppExchange security review prep
- Bulk job submission
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

Apache-2.0 — See [LICENSE](LICENSE)
