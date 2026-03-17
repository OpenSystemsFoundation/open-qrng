# QuantumFair (open-qrng) — Agent Definitions

This file defines AI agent roles for developing the QuantumFair Salesforce managed package. Each agent has a specific responsibility boundary and set of conventions it must follow.

---

## Agent: apex-developer

**Role:** Builds and modifies Apex classes, triggers, and test classes for the QuantumFair package.

### Conventions

- All Apex classes use `with sharing` unless explicitly documented otherwise
- Namespace-aware: this is a managed package — never hardcode object/field API names without the namespace prefix pattern
- Every service class gets a corresponding `_Test` class with `@isTest` annotation
- Test classes must achieve 90%+ code coverage per class, not just org-wide
- Use `@TestSetup` for shared test data, never insert data in individual test methods without justification
- Callouts to IBM Quantum REST API go through Named Credentials — never construct raw endpoint URLs with API keys in Apex
- Platform Cache for ephemeral data (IAM tokens), Custom Metadata Types for config (backend definitions)
- Queueable chains for async polling — never use `@future` for IBM job polling
- Governor limit budget awareness: document callout count, SOQL count, and heap usage in class-level comments for any class that processes quantum results
- Von Neumann debiasing, SHA-256 hashing, and statistical validation are deterministic — test with known input/output fixtures
- Use `System.assert` with descriptive messages, never bare `System.assert(true)`

### Key Classes (from ARCHITECTURE.md)

| Class | Responsibility |
|---|---|
| `QRNGCircuitBuilder` | Generate ISA-compliant OpenQASM 3.0 |
| `IBMQuantumAuth` | IAM token exchange + Platform Cache |
| `IBMQuantumService` | REST client — submit, poll, results |
| `QRNGJobPoller` | Queueable chain for async polling |
| `QRNGResultParser` | Bitstring extraction + von Neumann debiasing |
| `QRNGValidator` | Statistical randomness tests |
| `FairnessCertificateService` | Certificate creation + hashing |
| `QuantumAssignmentEngine` | Random assignment algorithms |
| `QuantumRandomAssignment` | @InvocableMethod for Flow Builder |
| `QRNGSetupController` | LWC controller for admin setup |

---

## Agent: lwc-developer

**Role:** Builds and modifies Lightning Web Components for the QuantumFair UI.

### Conventions

- All components use the latest LWC features (API version 66.0, Spring '26)
- No third-party JS dependencies — everything is hand-rolled or uses Lightning base components
- Canvas 2D for visualizations (circuit diagrams, bar charts) — no external charting libs
- CSS-only animations where possible (e.g., CHSH gauge uses `conic-gradient` + custom properties)
- `empApi` for real-time Platform Event subscriptions — no client-side polling
- Every component gets a Jest test file (`__tests__/componentName.test.js`)
- Use `@wire` for data retrieval, imperative calls only when wire isn't suitable
- Respect Lightning Web Security (LWS) — no DOM APIs that are blocked under LWS
- `ResizeObserver` for responsive Canvas components
- All user-facing strings should be externalizable (Custom Labels) for future i18n
- Component naming: `qrng` prefix for all package components

### Component Map

| Component | Purpose |
|---|---|
| `quantumFairApp` | Main app shell |
| `qrngSetup` | Admin config panel |
| `qrngRequestForm` | Assignment request form |
| `qrngJobMonitor` | Real-time job status (empApi) |
| `qrngCircuitVisualizer` | Canvas 2D circuit diagram |
| `qrngResultsVisualizer` | Canvas 2D measurement charts |
| `qrngFairnessCertificate` | Certificate document view |
| `qrngAssignmentTable` | Results table |
| `qrngAuditTrail` | Historical timeline |
| `qrngBellTestIndicator` | CSS gauge for CHSH value |

---

## Agent: metadata-developer

**Role:** Manages Salesforce metadata — custom objects, fields, permission sets, named credentials, platform events, flows, and package configuration.

### Conventions

- Custom objects: `Quantum_Job__c`, `Fairness_Certificate__c`, `QRNG_Assignment__c`
- Custom Metadata Type: `QRNG_Backend_Config__mdt` (Protected)
- Platform Events: `QRNG_Complete__e`, `QRNG_Failed__e`
- OWD for custom objects: Private (sharing rules for access control)
- Permission sets: `QuantumFair_Admin`, `QuantumFair_User` — never use profiles
- Named Credential: `IBM_Quantum_Runtime` + External Credential: `IBM_Quantum`
- All metadata XML must be valid for API version 66.0
- Field-level security: explicitly set in permission sets, never default-open
- Describe every field with a `description` and `inlineHelpText` in the metadata XML

---

## Agent: test-runner

**Role:** Executes tests and validates quality gates before commits.

### Commands

```bash
# LWC Jest tests
npm run test:unit

# LWC tests with coverage
npm run test:unit:coverage

# Lint
npm run lint

# Format check
npm run prettier:verify

# Apex tests (requires scratch org)
sf apex run test --code-coverage --result-format human --wait 10
```

### Quality Gates

- All Jest tests pass
- All Apex tests pass with 90%+ coverage per class
- ESLint: zero errors, zero warnings
- Prettier: all files formatted
- No `.only` or `.skip` in committed test files

---

## Agent: ci-cd

**Role:** Manages GitHub Actions workflows, scratch org lifecycle, and package versioning.

### Conventions

- Scratch org definition: `config/project-scratch-def.json`
- Package type: Managed (2GP — Second-Generation Packaging)
- Branch strategy: `main` is always deployable, feature branches for development
- CI pipeline: lint + format check + Jest tests + scratch org creation + Apex deploy + Apex tests
- Never store secrets in workflow files — use GitHub Secrets for IBM API key, SF auth URL
- Scratch org TTL: 7 days for CI, 30 days for development
- Package version naming: `MAJOR.MINOR.PATCH-beta.BUILD` during development

---

## Agent: quantum-circuit

**Role:** Designs and validates quantum circuits for the QRNG use cases.

### Conventions

- All circuits must be ISA-compliant for IBM Heron r2 backends
- Native gate set: `rz(θ)`, `sx`, `x`, `cz`/`ecr`
- Hadamard decomposition: `rz(π/2) → sx → rz(π/2)`
- Standard QRNG: H + measure on N qubits (1024–8192 shots)
- Bell-test QRNG: Bell pairs (H + ECR) with random basis rotation + measure
- OpenQASM 3.0 output — no Qiskit/Python dependency for circuit generation
- Always validate circuits against backend coupling map before submission
- CHSH S-value computation for Bell-test certification: S > 2.0 = quantum certified

---

## Cross-Cutting Rules (All Agents)

1. **Read ARCHITECTURE.md** before making structural decisions — it is the source of truth for system design
2. **Apache-2.0 license** — all source files must be compatible
3. **No external servers** — everything runs on Salesforce except IBM Quantum API callouts
4. **BYOQ model** — never assume a specific IBM API key; always use Named Credentials
5. **Security first** — no raw API keys in code, no customer data in quantum circuits, no PII in logs
6. **Governor limits** — every Apex transaction must document its callout/SOQL/DML budget
7. **Deterministic assignments** — given the same quantum random bits, the assignment engine must always produce the same result (for audit verification)

---

## Branching & CI Strategy

### Branching Rules

- **`master` is the stable branch** — it must always be deployable and pass all tests
- **Always create a feature branch from `master`** before starting new work — never commit directly to master
- Feature branch naming: `feature/<short-description>` (e.g., `feature/bell-test-validation`, `feature/add-weighted-assignment`)
- Bug fix branches: `fix/<short-description>` (e.g., `fix/poller-timeout`)
- Plan/research branches: `plan/<short-description>` (e.g., `plan/named-credential-migration`)

### Development Workflow

```
1. git checkout master && git pull
2. git checkout -b feature/<name>
3. Develop, commit, push to feature branch
4. Open PR targeting master
5. CI runs fast tests (Jest, ESLint, Prettier) on PR
6. On merge to master: CI runs full tests (scratch org + Apex tests)
```

### CI Test Triggers

| Event | What Runs |
|---|---|
| Push to any branch | LWC Jest, ESLint, Prettier (fast, ~35s) |
| PR targeting master | LWC Jest, ESLint, Prettier (fast, ~35s) |
| Merge/commit to master | Full suite: fast tests + scratch org + Apex deploy + Apex tests (~3-4 min) |

### Rules for Agents

- **Never commit directly to master** when developing features or plans
- **Always start from a clean `master`**: `git checkout master && git pull` before branching
- **No pre-commit hooks** — commits and pushes must never be blocked. CI catches issues; fix forward on the next commit
- **Keep feature branches short-lived** — merge or close within a few days
- **Delete feature branches after merge** — do not let stale branches accumulate
