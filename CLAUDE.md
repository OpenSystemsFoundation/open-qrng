# QuantumFair (open-qrng) — Claude Code Configuration

## Project Overview

QuantumFair is an open-source (Apache-2.0) Salesforce managed package that provides certified quantum random number generation (QRNG) for fair, auditable business process randomization. It uses IBM Quantum hardware to generate true randomness and creates immutable fairness certificates linked to every assignment.

**Core principle:** The app that uses quantum mechanics to prove your business decisions are fair.

## Architecture

Read [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design. Key points:

- **No external servers** — everything runs on Salesforce (Apex, LWC, Platform Events, Custom Objects)
- **BYOQ** — each org provides their own IBM Quantum API key via Named Credentials
- **No Python/Qiskit** — Apex generates ISA-compliant OpenQASM 3.0 directly (trivial for QRNG circuits)
- **Async flow** — submit circuit to IBM, poll via Queueable chain, deliver results via Platform Events

## Agent Definitions

See [AGENTS.md](AGENTS.md) for detailed agent roles, conventions, and quality gates.

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Apex (API v66.0, Spring '26) |
| Frontend | Lightning Web Components (LWS) |
| Visualizations | Canvas 2D (hand-rolled, no libs) |
| Quantum | IBM Quantum REST API (Heron r2) |
| Testing | Apex Tests + sfdx-lwc-jest |
| Linting | ESLint + Prettier (with Apex plugin) |
| CI | GitHub Actions + Salesforce CLI |
| Package | 2GP Managed Package |

## Project Structure

```
open-qrng/
├── force-app/main/default/
│   ├── classes/          ← Apex classes + tests
│   ├── lwc/              ← Lightning Web Components
│   ├── objects/          ← Custom object definitions
│   ├── platformEventChannelMembers/
│   ├── namedCredentials/
│   ├── permissionsets/
│   ├── tabs/
│   ├── flexipages/
│   └── flows/
├── config/               ← Scratch org definition
├── manifest/             ← package.xml
├── scripts/              ← Utility scripts
├── ARCHITECTURE.md       ← System design (source of truth)
├── AGENTS.md             ← AI agent role definitions
└── sfdx-project.json     ← SFDX project config
```

## Commands

```bash
# Install dependencies
npm install

# Run LWC Jest tests
npm run test:unit

# Run tests with coverage
npm run test:unit:coverage

# Lint
npm run lint

# Format check
npm run prettier:verify

# Format fix
npm run prettier

# Create scratch org
sf org create scratch -f config/project-scratch-def.json -a qrng-dev

# Deploy to scratch org
sf project deploy start

# Run Apex tests
sf apex run test --code-coverage --result-format human --wait 10

# Assign permission sets
sf org assign permset -n QuantumFair_Admin
sf org assign permset -n QuantumFair_User
```

## Development Rules

1. **Always read ARCHITECTURE.md** before making structural changes
2. **Apex:** `with sharing` on all classes, Named Credentials for all external calls, 90%+ test coverage per class
3. **LWC:** No third-party JS libs, Canvas 2D for visuals, empApi for real-time events, Jest tests for every component
4. **Security:** No raw API keys in code, no customer data in circuits, no PII in logs, OWD = Private
5. **Determinism:** Same quantum bits must always produce the same assignment (audit verifiable)
6. **Governor limits:** Document callout/SOQL/DML budget in class-level comments for heavy classes
7. **Formatting:** Prettier on save, ESLint zero errors/warnings before commit
8. **Git:** Husky pre-commit hook runs lint-staged (prettier + eslint + jest on changed files)
