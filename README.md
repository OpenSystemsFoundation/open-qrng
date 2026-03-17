# QuantumFair (open-qrng)

**Certified quantum random number generation for Salesforce.**
Apache-2.0 | Free on AppExchange | Zero Infrastructure Cost

---

QuantumFair uses real IBM Quantum hardware to generate true randomness — provable by the laws of physics — and creates immutable fairness certificates linked to every assignment. No external servers, no middleware. Everything runs on Salesforce.

## How It Works

1. **Request** — A Flow, Apex trigger, or LWC requests random values for a purpose (e.g., "assign 50 leads across 5 reps fairly")
2. **Generate** — Apex builds an ISA-compliant OpenQASM 3.0 circuit using native Heron r2 gates (`rz`, `sx`, `x`, `ecr`) and submits it to IBM Quantum via Named Credentials
3. **Execute** — IBM Quantum hardware runs the circuit. A Queueable chain polls for results.
4. **Certify** — Statistical validation (monobit, runs test, chi-squared) + optional CHSH Bell-test. A `Fairness_Certificate__c` record stores circuit params, raw measurement hashes, and validation results.
5. **Assign** — Quantum random bits drive the assignment. The certificate links to every assigned record.
6. **Audit** — Any auditor can verify: circuit ran on IBM hardware (job ID), measurements are statistically random, assignment follows deterministically from measurements.

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
2. Open the QuantumFair Setup tab
3. Enter your IBM Quantum API key into the External Credential (guided wizard)
4. Select your preferred backend (wizard shows available QPUs with health status)
5. Run a test circuit (1 qubit, 100 shots) to verify connectivity
6. Assign `QuantumFair_User` permission set to users who need random assignments

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
│   │   ├── controllers/      ← LWC controllers, @InvocableMethod for Flow
│   │   ├── shared/           ← Provider interface, factory, consumer interface, exceptions
│   │   └── tests/            ← All @isTest classes
│   ├── lwc/
│   │   ├── quantumFairApp/           ← Main app shell
│   │   ├── qrngSetup/               ← Admin config (backend picker, connection test)
│   │   ├── qrngJobStatusPanel/      ← Backend health and job status dashboard
│   │   ├── qrngJobMonitor/          ← Real-time job status via empApi
│   │   ├── qrngCircuitVisualizer/   ← Canvas 2D circuit diagram
│   │   ├── qrngResultsVisualizer/   ← Canvas 2D measurement charts
│   │   ├── qrngRequestForm/         ← Assignment request form
│   │   ├── qrngFairnessCertificate/ ← Certificate document view
│   │   ├── qrngAssignmentTable/     ← Results table
│   │   ├── qrngAuditTrail/          ← Historical job/certificate timeline
│   │   └── qrngBellTestIndicator/   ← CSS gauge for CHSH value
│   ├── objects/              ← Quantum_Job__c, Fairness_Certificate__c, QRNG_Assignment__c
│   ├── namedCredentials/     ← IBM_Quantum_Runtime, IBM_Quantum External Credential
│   ├── permissionsets/       ← QuantumFair_Admin, QuantumFair_User
│   └── flows/                ← Sample: Quantum Random Lead Assignment
├── config/                   ← Scratch org definition
├── ARCHITECTURE.md           ← Full system design (source of truth)
├── CLAUDE.md                 ← AI-assisted development config
└── AGENTS.md                 ← AI agent role definitions
```

## Roadmap

### Now (Current Sprint)

- Integrity verification nightly job (`IntegrityVerificationJob`)
- Coupling map qubit selection for ISA circuit generation
- Bell test circuit fixes for native Heron r2 gate set
- DTO pattern across all LWC components for Apex-to-LWC communication

### Next (Upcoming)

- Flow-based quantum assignment builder
- Assignment engine integration with fairness certificates
- AppExchange security review prep
- Bulk job submission
- Multi-backend failover

### Future (Longer Term)

- Quantum Pareto (QAMOO) optimization package
- PQC readiness scanner
- Quantum key distribution integration
- Real-time CHSH violation monitoring dashboard

## License

Apache-2.0 — See [LICENSE](LICENSE)
