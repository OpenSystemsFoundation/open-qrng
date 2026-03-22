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

| Layer          | Technology                              |
| -------------- | --------------------------------------- |
| Backend        | Apex (API v66.0, Spring '26)            |
| Frontend       | Lightning Web Components (LWS)          |
| Visualizations | Canvas 2D (hand-rolled, no libs)        |
| Quantum        | IBM Quantum REST API (Heron r2)         |
| Testing        | Apex Tests + sfdx-lwc-jest + Playwright |
| Linting        | ESLint + Prettier (with Apex plugin)    |
| CI             | GitHub Actions + Salesforce CLI         |
| Package        | 2GP Managed Package                     |

## Project Structure

```
open-qrng/
├── .claude/
│   ├── settings.json     ← SessionStart hook config (auto-provisions scratch org)
│   └── hooks/            ← Hook scripts
├── e2e/                  ← Playwright E2E tests
│   ├── fixtures/         ← Mock HTML fixture for local E2E
│   ├── pages/            ← Page Object Models
│   └── *.spec.ts         ← Test suites (7 files, ~90 tests)
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
├── scripts/
│   └── session-setup.sh  ← Auto scratch org setup (SessionStart hook)
├── ARCHITECTURE.md       ← System design (source of truth)
├── AGENTS.md             ← AI agent role definitions
├── playwright.config.ts  ← Playwright E2E config
└── sfdx-project.json     ← SFDX project config
```

## Commands

```bash
# ── Quick tests (no scratch org needed) ───────────
npm install                          # Install dependencies
npm run test:unit                    # Run 314 LWC Jest tests
npm run test:unit:coverage           # Jest with coverage report
npm run lint                         # ESLint
npm run prettier:verify              # Format check
npm run prettier                     # Format fix

# ── Playwright E2E (mock fixture, no org needed) ──
npm run test:e2e                     # Run all E2E tests
npm run test:e2e:headed              # Run with browser visible
npm run test:e2e:debug               # Debug mode
npm run test:e2e:report              # View HTML report

# ── Scratch org (auto-provisioned on web sessions) ─
sf project deploy start --target-org qrng-dev   # Deploy changes
sf apex run test --target-org qrng-dev \
  --code-coverage --result-format human --wait 10  # Apex tests

# ── Manual scratch org setup (if not using session hook) ─
sf org create scratch -f config/project-scratch-def.json -a qrng-dev
sf project deploy start --target-org qrng-dev
sf org assign permset -n QuantumFair_Admin --target-org qrng-dev
sf org assign permset -n QuantumFair_User --target-org qrng-dev
```

## Claude Code on the Web — Development Cycle

This project is designed to be fully developed from **Claude Code on the web** (claude.ai/code). Every session automatically provisions a Salesforce scratch org, deploys the package, and sets up the full test pipeline — no local machine required.

### Environment Setup

Configure these **environment variables** in your Claude Code web environment settings:

| Variable           | Required | Description                                                  |
| ------------------ | -------- | ------------------------------------------------------------ |
| `SFDX_AUTH_URL`    | Yes      | DevHub SFDX auth URL (`sfdx://...`) for scratch org creation |
| `SF_SCRATCH_ALIAS` | No       | Scratch org alias (default: `qrng-dev`)                      |
| `SF_SCRATCH_DAYS`  | No       | Scratch org duration in days (default: `7`)                  |
| `SKIP_SF_SETUP`    | No       | Set to `true` to skip Salesforce setup                       |

**Setup script** (paste into environment settings → Setup script field):

```bash
#!/bin/bash
npm install -g @salesforce/cli || true
```

The Salesforce CLI install goes in the setup script (runs once, before Claude Code launches). Everything else is handled by the **SessionStart hook** in `.claude/settings.json` which runs automatically on every session.

### What Happens on Session Start

The `scripts/session-setup.sh` hook runs automatically and:

1. Installs npm dependencies
2. Authenticates the DevHub using `SFDX_AUTH_URL`
3. Creates a scratch org (or reuses an existing one)
4. Deploys all source metadata to the scratch org
5. Assigns `QuantumFair_Admin` and `QuantumFair_User` permission sets
6. Persists `SF_INSTANCE_URL` and `SF_ACCESS_TOKEN` as session env vars
7. Prints a summary with the org URL and available commands

### Development → Test → Deploy Loop

Each feature branch follows this cycle, entirely from Claude Code on the web:

```
┌─────────────────────────────────────────────────────┐
│  1. SESSION START (automatic)                       │
│     └─ Hook authenticates DevHub, creates scratch   │
│        org, deploys source, assigns permsets         │
├─────────────────────────────────────────────────────┤
│  2. DEVELOP                                         │
│     └─ Write Apex, LWC, metadata on feature branch  │
│     └─ Deploy changes: sf project deploy start      │
├─────────────────────────────────────────────────────┤
│  3. TEST LOCALLY (in session)                       │
│     └─ npm run test:unit        (314 Jest tests)    │
│     └─ npm run lint             (ESLint)            │
│     └─ npm run prettier:verify  (formatting)        │
│     └─ sf apex run test         (Apex in scratch)   │
│     └─ npm run test:e2e         (Playwright E2E)    │
├─────────────────────────────────────────────────────┤
│  4. PUSH & CI FEEDBACK                              │
│     └─ git push to feature branch                   │
│     └─ GitHub Actions run all test suites           │
│     └─ Results posted as PR/commit comments          │
│     └─ Read results: gh api repos/.../comments      │
├─────────────────────────────────────────────────────┤
│  5. ITERATE                                         │
│     └─ Read CI output, fix failures, push again     │
│     └─ E2E failures → add Jest/Apex tests           │
│     └─ Repeat until all green                       │
├─────────────────────────────────────────────────────┤
│  6. CREATE PR                                       │
│     └─ gh pr create or use Claude Code web UI       │
│     └─ CI runs full suite, results in PR comments   │
└─────────────────────────────────────────────────────┘
```

### Parallel Development

Start multiple Claude Code web sessions to work on different features simultaneously:

```bash
claude --remote "Fix the CHSH S-value rounding in QRNGValidator"
claude --remote "Add min-entropy threshold to settings panel"
claude --remote "Write Apex tests for ComplianceEvidenceExporter edge cases"
```

Each session gets its own scratch org and runs independently.

### CI Feedback Loop

All three GitHub Actions workflows post structured results as PR/commit comments:

| Workflow        | What it reports                                     |
| --------------- | --------------------------------------------------- |
| `test.yml`      | Jest results (pass/fail per test), ESLint, Prettier |
| `e2e-debug.yml` | Playwright E2E results with failure screenshots     |
| `apex-test.yml` | Apex test results with org-wide coverage %          |

Read CI output from the session:

```bash
# List recent commit comments (test results)
gh api repos/OWNER/REPO/commits/HEAD/comments

# List PR comments
gh api repos/OWNER/REPO/issues/PR_NUMBER/comments
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
