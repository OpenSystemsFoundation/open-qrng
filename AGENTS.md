# QuantumFair (open-qrng) — Agent Definitions

This file defines AI agent roles for developing QuantumFair, an open-source Salesforce app distributed as an unmanaged package / source deploy. Each agent has a specific responsibility boundary and set of conventions it must follow.

---

## Agent: apex-developer

**Role:** Builds and modifies Apex classes, triggers, and test classes for the QuantumFair package.

### Conventions

- All Apex classes use `with sharing` unless explicitly documented otherwise (async system-maintenance workers like `JobPoller`/`JobPollScheduler` are documented `without sharing`)
- No namespace: the project distributes as an unmanaged package / source deploy — object/field API names are un-namespaced
- Every service class gets a corresponding `_Test` class alongside it in the flat `classes/` directory
- Test classes must achieve 90%+ code coverage per class, not just org-wide
- Use `@TestSetup` for shared test data, never insert data in individual test methods without justification
- Callouts to the IBM Quantum REST API are authorized via Remote Site Settings; the API key lives in the Protected custom setting `Quantum_Settings__c.IBM_API_Key__c` and is only ever sent to IBM IAM for token exchange — never construct endpoint URLs containing API keys
- Platform Cache (`local.QuantumFair` partition) for ephemeral data (IAM bearer tokens); backend/provider config lives in `Quantum_Provider__c`/`Quantum_Backend__c` records
- Privileged `@AuraEnabled` methods must call `requireAdmin()` (the `QuantumFair_Administer` custom permission gate); controller reads enforce FLS via `WITH USER_MODE` / `Security.stripInaccessible`
- Randomness consumption uses rejection sampling only — never modulo, never a pseudo-random fallback
- Queueable chains for async polling — never use `@future` for IBM job polling
- Governor limit budget awareness: document callout count, SOQL count, and heap usage in class-level comments for any class that processes quantum results
- Von Neumann debiasing, SHA-256 hashing, and statistical validation are deterministic — test with known input/output fixtures
- Use `System.assert` with descriptive messages, never bare `System.assert(true)`
- **DTO pattern:** Use dedicated DTO inner classes or wrapper classes for all data passed between Apex controllers and LWC components. Never return raw SObject records or untyped Maps to the front end.
- **Provider pattern:** All quantum backend integrations implement the `QuantumProvider` interface. Use `QuantumProviderFactory` to obtain provider instances — never instantiate providers directly.
- **Native Heron r2 gates:** Circuit generation must use the native ISA gate set (`rz`, `sx`, `x`, `ecr`). No abstract/logical gates — all circuits are pre-transpiled in Apex.
- **Coupling map awareness:** Qubit selection must respect the backend coupling map. Validate qubit connectivity before circuit submission.

### Apex Class Organization

All classes live in the flat `force-app/main/default/classes/` directory (test classes alongside their sources), organized by domain responsibility:

| Domain       | Purpose                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------ |
| API          | IBM Quantum integration — auth, REST client, response parsing, provider impl               |
| Circuits     | OpenQASM 3.0 circuit generation (ISA-compliant)                                            |
| Jobs         | Async submission queueable, polling chain, job processor, sweeper, poll scheduler          |
| Results      | Result parsing, per-qubit von Neumann debiasing, statistical validation, assignment engine |
| Certificates | Fairness certificate service, integrity verification, chaining                             |
| Compliance   | Event logger, digest email, summary job, evidence export                                   |
| Controllers  | LWC controller, @InvocableMethod for Flow Builder                                          |
| Shared       | Interfaces (QuantumProvider, QuantumConsumer), factory, exceptions                         |

### Key Classes

| Class                        | Domain       | Responsibility                                   |
| ---------------------------- | ------------ | ------------------------------------------------ |
| `IBMQuantumAuth`             | API          | IAM token exchange + Platform Cache              |
| `IBMQuantumService`          | API          | REST client — submit, poll, results              |
| `IBMQuantumProvider`         | API          | QuantumProvider implementation for IBM Quantum   |
| `IBMResponseParser`          | API          | IBM response shape parsing                       |
| `CircuitBuilder`             | Circuits     | Generate ISA-compliant OpenQASM 3.0              |
| `QuantumSubmissionQueueable` | Jobs         | Chained async submission of Pending jobs         |
| `JobPoller`                  | Jobs         | Queueable poll chain (backoff, transient retry)  |
| `JobPollScheduler`           | Jobs         | Schedulable hop between polls                    |
| `JobProcessor`               | Jobs         | Idempotent completion processing + assignments   |
| `JobSweeper`                 | Jobs         | Scheduled safety net for stale/abandoned jobs    |
| `ResultParser`               | Results      | Bitstring extraction + per-qubit von Neumann     |
| `RandomnessValidator`        | Results      | Statistical randomness tests (alpha = 0.01)      |
| `ValidationRunner`           | Results      | Async SP 800-90B suite — can revoke certificates |
| `QuantumAssignmentEngine`    | Results      | Rejection-sampled assignment algorithms          |
| `FairnessCertificateService` | Certificates | Certificate creation + chain linking             |
| `IntegrityVerificationJob`   | Certificates | Nightly re-hash verification of certificates     |
| `ComplianceEventLogger`      | Compliance   | Audit event creation + hashing                   |
| `ComplianceDigestJob`        | Compliance   | Daily hash digest email to compliance mailbox    |
| `ComplianceSummaryJob`       | Compliance   | Aggregate compliance summary                     |
| `ComplianceEvidenceExporter` | Compliance   | Framework-specific evidence JSON export          |
| `ComplianceControlService`   | Compliance   | Query compliance control-to-framework mapping    |
| `SetupController`            | Controllers  | LWC controller (permission-gated, FLS-enforced)  |
| `QuantumRandomAssignment`    | Controllers  | @InvocableMethod for Flow Builder (bulk-safe)    |
| `QuantumProvider`            | Shared       | Interface for quantum backend providers          |
| `QuantumProviderFactory`     | Shared       | Factory for obtaining provider instances         |
| `QuantumConsumer`            | Shared       | Interface for custom randomness consumers        |
| `QuantumException`           | Shared       | Package-specific exception class                 |

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
- **DTO pattern:** Controllers return typed DTO objects. LWC components consume DTO properties directly — no manual field mapping from raw SObject shapes. Use safe `Number()` casts for numeric DTO fields in `formatTime`/`formatPercent`-style helpers.

### Component Map

| Component                 | Purpose                                                                   |
| ------------------------- | ------------------------------------------------------------------------- |
| `quantumFairApp`          | Main app shell (5-tab layout: Dashboard/Jobs/Setup/Operations/Compliance) |
| `qrngSetup`               | Admin setup orchestrator (delegates to child components)                  |
| `qrngConnectionSetup`     | API key input + auto-connection test                                      |
| `qrngSettingsPanel`       | Backend, shots, compliance email config                                   |
| `qrngHealthMonitor`       | Backend health with fidelity scoring + timestamps                         |
| `qrngBackgroundJobs`      | Scheduler management UI                                                   |
| `qrngJobDashboard`        | Filterable job table with real-time Platform Event updates                |
| `qrngJobStatusPanel`      | Job type + status display on record pages                                 |
| `qrngJobMonitor`          | Real-time single-job status via empApi                                    |
| `qrngQasmViewer`          | Canvas 2D OpenQASM circuit renderer (ISA + multi-circuit)                 |
| `qrngCircuitVisualizer`   | Legacy circuit diagram                                                    |
| `qrngResultsVisualizer`   | Canvas 2D measurement charts                                              |
| `qrngValidationResults`   | Statistical + CHSH results (job-type aware)                               |
| `qrngRequestForm`         | Assignment request form                                                   |
| `qrngFairnessCertificate` | Certificate document view                                                 |
| `qrngAssignmentTable`     | Results table                                                             |
| `qrngAuditTrail`          | Historical timeline with real-time updates                                |
| `qrngBellTestIndicator`   | CSS gauge for CHSH S-value                                                |
| `qrngChshVisualizer`      | CHSH correlator breakdown chart                                           |
| `qrngComplianceExport`    | Framework evidence JSON download                                          |
| `qrngEventSubscription`   | Shared Platform Event subscription utility                                |
| `qrngUtils`               | Shared utilities (reduceErrors)                                           |

---

## Agent: metadata-developer

**Role:** Manages Salesforce metadata — custom objects, fields, permission sets, named credentials, platform events, flows, and package configuration.

### Conventions

- Custom objects: `Quantum_Job__c`, `Fairness_Certificate__c`, `Quantum_Assignment__c`, `Quantum_Provider__c`, `Quantum_Backend__c`, `Compliance_Event__c`
- Custom Metadata Types: `Compliance_Control__mdt` (24 seed records)
- Custom Settings: `Quantum_Settings__c` (Protected Hierarchy — IBM API key, default backend, shots, compliance email)
- Custom Permissions: `QuantumFair_Administer` (granted only in the Admin permission set; gates privileged @AuraEnabled methods)
- Platform Events: `Quantum_Job_Complete__e`, `Quantum_Job_Failed__e`
- OWD for custom objects: Private (master-detail children Controlled by Parent)
- Permission sets: `QuantumFair_Admin`, `QuantumFair_User`, `QuantumFair_Auditor` (read-only) — never use profiles; all three grant `SetupController` class access + Platform Event read
- Remote Site Settings: `IBM_IAM`, `IBM_Quantum_API`, `IBM_Resource_Controller` (no Named/External Credentials — the API key lives in the Protected custom setting)
- Platform Cache partition: `QuantumFair` (IAM bearer token cache)
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
- **Org-wide Apex coverage must be 75%+ minimum** — this is a Salesforce production deployment requirement. Never lower this threshold; always write the missing tests.
- ESLint: zero errors, zero warnings
- Prettier: all files formatted
- No `.only` or `.skip` in committed test files
- **DTO contracts:** Controller methods must return DTO types, not raw SObjects or untyped Maps. Test assertions should validate DTO property names and types.

---

## Agent: ci-cd

**Role:** Manages GitHub Actions workflows, scratch org lifecycle, package versioning, and the Claude Code on the web development loop.

### Conventions

- Scratch org definition: `config/project-scratch-def.json` (non-namespaced — the project has no namespace)
- Distribution: unmanaged package / open-source source deploy (no 2GP packaging, no `packageAliases`)
- Branch strategy: `master` is always deployable, feature branches for development
- CI pipeline: lint + format check + Jest tests + scratch org creation + Apex deploy + Apex tests (fork-safe; workflows use concurrency groups)
- Never store secrets in workflow files — use GitHub Secrets for IBM API key, SF auth URL
- Scratch org TTL: 7 days for CI, 30 days for development
- Version naming: `MAJOR.MINOR.PATCH` in `sfdx-project.json` / CHANGELOG.md

### Claude Code Web Session Setup

Every Claude Code web session automatically provisions a scratch org via `scripts/session-setup.sh` (triggered by `.claude/settings.json` SessionStart hook). The hook:

1. Authenticates DevHub from `SFDX_AUTH_URL` (set as environment variable in web settings)
2. Creates or reuses scratch org (`SF_SCRATCH_ALIAS`, default: `qrng-dev`)
3. Deploys all metadata with `sf project deploy start`
4. Assigns `QuantumFair_Admin` + `QuantumFair_User` permission sets
5. Persists `SF_INSTANCE_URL` and `SF_ACCESS_TOKEN` to `CLAUDE_ENV_FILE` for the session

### CI Feedback Loop Workflows

| Workflow        | Trigger                    | Posts Results To                               |
| --------------- | -------------------------- | ---------------------------------------------- |
| `test.yml`      | All pushes + PRs to master | PR comment (LWC Test Results) + commit comment |
| `e2e-debug.yml` | All pushes + PRs to master | PR comment (E2E Test Results) + commit comment |
| `apex-test.yml` | Push/PR to master          | PR comment (Apex Test Results)                 |

All workflows use `actions/github-script` to create or update a single bot comment per result type (avoids comment spam). Results include collapsible failure details.

### Developing Features from the Web

```bash
# 1. Session starts → hook auto-provisions scratch org
# 2. Create feature branch
git checkout -b feature/my-feature

# 3. Develop (write code, deploy to scratch org, run tests)
sf project deploy start --target-org qrng-dev
sf apex run test --code-coverage --result-format human --wait 10
npm run test:unit

# 4. Push and read CI feedback
git push -u origin feature/my-feature
# CI runs → results appear as commit comments
gh api repos/OWNER/REPO/commits/$(git rev-parse HEAD)/comments

# 5. Iterate: fix failures, push again
# 6. Create PR when ready
gh pr create --title "feat: my feature" --body "..."
```

---

## Agent: quantum-circuit

**Role:** Designs and validates quantum circuits for the QRNG use cases.

### Conventions

- All circuits must be ISA-compliant for IBM Heron r2 backends
- Native gate set: `rz(θ)`, `sx`, `x`, `ecr`
- Hadamard decomposition: `rz(π/2) → sx → rz(π/2)`
- Standard QRNG: H + measure on N qubits (1024-8192 shots)
- Bell-test QRNG: Bell pairs (H + ECR) with random basis rotation + measure
- OpenQASM 3.0 output — no Qiskit/Python dependency for circuit generation
- **Coupling map integration:** Always validate qubit connectivity against the backend coupling map before circuit submission. Use physically connected qubits for two-qubit gates.
- CHSH S-value computation for Bell-test certification: requires (S − 2.0) > 2σ_S (classical bound violated by at least two standard errors — "consistent with quantum origin", never "proves")
- **Gate fidelity:** Prefer qubits and connections with higher gate fidelity when coupling map data is available

---

## Scratch Org & App Navigation

The scratch org alias is set by the session hook (default: `qrng-dev`, configurable via `SF_SCRATCH_ALIAS`). On Claude Code web sessions, the org is provisioned automatically.

```bash
# Get the front door login URL (SFDX_DISABLE_DNS_CHECK is set automatically via .claude/settings.json env)
sf org open -o qrng-dev --url-only

# QuantumFair app tab URL (append to scratch org lightning domain)
# https://<scratch-org-domain>.scratch.lightning.force.com/lightning/n/QuantumFair

# Deploy changes during development
sf project deploy start --target-org qrng-dev --ignore-conflicts

# Run Apex tests against the scratch org
sf apex run test --target-org qrng-dev --code-coverage --result-format human --wait 10

# Assign permission sets (done automatically by session hook)
sf org assign permset --name QuantumFair_Admin --target-org qrng-dev
sf org assign permset --name QuantumFair_User --target-org qrng-dev
```

The QuantumFair tab is un-namespaced. Always use `/lightning/n/QuantumFair` to navigate to the main app page.

### Manual Scratch Org Setup (local CLI without session hook)

If developing locally without the session hook, or if `SFDX_AUTH_URL` is not set:

```bash
# Authenticate your DevHub
sf org login web --alias devhub --set-default-dev-hub

# Create scratch org
sf org create scratch -f config/project-scratch-def.json -a qrng-dev -d 7

# Deploy and assign permsets
sf project deploy start --target-org qrng-dev
sf org assign permset -n QuantumFair_Admin --target-org qrng-dev
sf org assign permset -n QuantumFair_User --target-org qrng-dev
```

---

## Environment Setup (Claude Code Web)

### SessionStart Hook

The project includes a SessionStart hook (`scripts/session-start.sh`) that automatically:

1. Installs Salesforce CLI (`sf`)
2. Installs GitHub CLI (`gh`)
3. Installs Playwright + Chromium (headless browser)
4. Sets `SFDX_DISABLE_DNS_CHECK=true` (required in sandboxed environments where DNS is restricted)
5. Authenticates the Dev Hub via `SFDX_AUTH_URL` environment variable
6. Runs `npm install`

### Required Environment Variables

| Variable                 | Purpose                                   | Required |
| ------------------------ | ----------------------------------------- | -------- |
| `SFDX_AUTH_URL`          | SFDX auth URL (`force://...`) for Dev Hub | Yes      |
| `SFDX_DISABLE_DNS_CHECK` | Skip DNS validation in sandboxed envs     | Auto-set |

### Headless Scratch Org Login (Playwright)

Use Playwright to headlessly log into scratch orgs and interact with the Salesforce UI:

```bash
# Full setup: authenticate, create scratch org, login, deploy, assign permsets
node scripts/playwright/scratch-org-login.mjs

# Reuse existing scratch org
node scripts/playwright/scratch-org-login.mjs --skip-create --alias qrng-dev

# Skip deploy (just auth + login)
node scripts/playwright/scratch-org-login.mjs --skip-create --skip-deploy
```

### Playwright Version Pinning

The project pins `playwright@1.56.1` in `package.json` to match the Chromium binary installed by the SessionStart hook. If the global Playwright version changes, update the local pin to match:

```bash
# Check installed global version
cat /opt/node22/lib/node_modules/playwright/package.json | grep version

# Pin local to match
npm install --save-dev playwright@<version>
```

### Headless UI Debugging

Playwright enables UI debugging without a visible browser:

- **Screenshots:** `page.screenshot()` — capture visual state
- **DOM inspection:** `page.content()` — get full HTML
- **JS evaluation:** `page.evaluate(() => ...)` — run code in page context
- **Accessibility tree:** `page.accessibility.snapshot()` — structured page description
- **Console capture:** `page.on('console', msg => ...)` — see JS console output
- **Network interception:** `page.route()` — mock or inspect API calls
- **Element text:** `page.locator('.selector').textContent()` — read specific values

---

## Cross-Cutting Rules (All Agents)

1. **Read ARCHITECTURE.md** before making structural decisions — it is the source of truth for system design
2. **Apache-2.0 license** — all source files must be compatible
3. **No external servers** — everything runs on Salesforce except IBM Quantum API callouts
4. **BYOQ model** — never assume a specific IBM API key; each org enters its own key via the Setup tab (Protected custom setting)
5. **Security first** — no raw API keys in code or logs, key never returned to the client, no customer data in quantum circuits, no PII in logs
6. **Governor limits** — every Apex transaction must document its callout/SOQL/DML budget
7. **Deterministic assignments** — given the same quantum random bits, the assignment engine must always produce the same result (for audit verification)
8. **DTO pattern** — all Apex-to-LWC communication uses typed DTOs, not raw SObjects or untyped Maps
9. **Provider pattern** — quantum backend integrations are abstracted behind the `QuantumProvider` interface, instantiated via `QuantumProviderFactory`

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

| Event                  | What Runs                                                                  |
| ---------------------- | -------------------------------------------------------------------------- |
| Push to any branch     | LWC Jest, ESLint, Prettier (fast, ~35s)                                    |
| PR targeting master    | LWC Jest, ESLint, Prettier (fast, ~35s)                                    |
| Merge/commit to master | Full suite: fast tests + scratch org + Apex deploy + Apex tests (~3-4 min) |

### Rules for Agents

- **Never commit directly to master** when developing features or plans
- **Always start from a clean `master`**: `git checkout master && git pull` before branching
- **No pre-commit hooks** — commits and pushes must never be blocked. CI catches issues; fix forward on the next commit
- **Keep feature branches short-lived** — merge or close within a few days
- **Delete feature branches after merge** — do not let stale branches accumulate
