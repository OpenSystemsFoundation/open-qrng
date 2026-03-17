# QuantumFair (open-qrng)

**Certified quantum random number generation for Salesforce.**
Apache-2.0 | Free on AppExchange | Zero Infrastructure Cost

---

QuantumFair uses real IBM Quantum hardware to generate true randomness — provable by the laws of physics — and creates immutable fairness certificates linked to every assignment. No external servers, no middleware. Everything runs on Salesforce.

## How It Works

1. **Request** — A Flow, Apex trigger, or LWC requests random values for a purpose (e.g., "assign 50 leads across 5 reps fairly")
2. **Generate** — Apex builds an ISA-compliant OpenQASM 3.0 circuit (Hadamard + measure) and submits it to IBM Quantum via Named Credentials
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
4. Select your preferred backend (wizard shows available QPUs)
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
│   ├── classes/          ← Apex (circuit builder, IBM client, poller, validator, engine)
│   ├── lwc/              ← LWC (circuit visualizer, job monitor, certificate viewer)
│   ├── objects/          ← Quantum_Job__c, Fairness_Certificate__c, QRNG_Assignment__c
│   ├── namedCredentials/ ← IBM_Quantum_Runtime, IBM_Quantum External Credential
│   ├── permissionsets/   ← QuantumFair_Admin, QuantumFair_User
│   └── flows/            ← Sample: Quantum Random Lead Assignment
├── config/               ← Scratch org definition
├── ARCHITECTURE.md       ← Full system design (source of truth)
├── CLAUDE.md             ← AI-assisted development config
└── AGENTS.md             ← AI agent role definitions
```

## License

Apache-2.0 — See [LICENSE](LICENSE)
