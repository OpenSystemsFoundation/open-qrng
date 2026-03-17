# QuantumFair Local & CI Testing Plan

**Date:** 2026-03-17
**Status:** Approved — implementing

---

## Problem

Currently, all testing requires deploying to a Salesforce scratch org. This is slow (~15-30s per deploy), burns scratch org limits, and can't run in lightweight CI. We need automated testing that runs locally and in GitHub Actions without scratch orgs for every push/PR, with scratch-org-based Apex testing reserved for merges to master.

## Testing Layers

### Layer 1: Local (optional, on-demand only)

No pre-commit hooks. Developers commit and push freely without interruption. Run tests manually when you want:

```bash
npm test                    # LWC Jest
npm run lint                # ESLint
npm run prettier:verify     # Formatting check
```

The existing Husky pre-commit hook will be removed to keep the commit flow fast.

### Layer 2: CI Fast (no scratch org) — runs on every push/PR to any branch

| What                      | Tool                         | Time     |
| ------------------------- | ---------------------------- | -------- |
| Install deps              | `npm ci`                     | ~15s     |
| LWC Jest tests + coverage | `npm run test:unit:coverage` | ~10s     |
| ESLint                    | `npm run lint`               | ~5s      |
| Prettier check            | `npm run prettier:verify`    | ~5s      |
| **Total**                 |                              | **~35s** |

### Layer 3: CI Full (scratch org) — runs on merge/commit to master only

| What                      | Tool                             | Time         |
| ------------------------- | -------------------------------- | ------------ |
| Layer 2 (all above)       | npm scripts                      | ~35s         |
| Authenticate DevHub       | `sf org login` via SFDX Auth URL | ~5s          |
| Create scratch org        | `sf org create scratch`          | ~60-90s      |
| Deploy metadata           | `sf project deploy start`        | ~15s         |
| Run Apex tests            | `sf apex run test`               | ~30s         |
| Check coverage thresholds | Parse test output                | ~2s          |
| Delete scratch org        | `sf org delete scratch`          | ~5s          |
| **Total**                 |                                  | **~3-4 min** |

---

## Implementation Plan

### Phase 1: LWC Jest Tests + Mocks

**What:** Create Jest test files for all 10 LWC components with shared mock utilities.

**Files to create:**

```
force-app/main/default/lwc/
├── __mocks__/                          ← Shared wire adapter mocks
│   └── lightning/
│       ├── empApi.js                   ← Mock for Platform Event subscriptions
│       └── platformShowToastEvent.js   ← Mock for ShowToastEvent
│
├── quantumFairApp/
│   └── __tests__/
│       └── quantumFairApp.test.js
├── qrngSetup/
│   └── __tests__/
│       └── qrngSetup.test.js
├── qrngRequestForm/
│   └── __tests__/
│       └── qrngRequestForm.test.js
├── qrngJobMonitor/
│   └── __tests__/
│       └── qrngJobMonitor.test.js
├── qrngCircuitVisualizer/
│   └── __tests__/
│       └── qrngCircuitVisualizer.test.js
├── qrngResultsVisualizer/
│   └── __tests__/
│       └── qrngResultsVisualizer.test.js
├── qrngFairnessCertificate/
│   └── __tests__/
│       └── qrngFairnessCertificate.test.js
├── qrngAssignmentTable/
│   └── __tests__/
│       └── qrngAssignmentTable.test.js
├── qrngAuditTrail/
│   └── __tests__/
│       └── qrngAuditTrail.test.js
└── qrngBellTestIndicator/
    └── __tests__/
        └── qrngBellTestIndicator.test.js
```

**What each test covers:**

| Component               | Test Cases                                                                  |
| ----------------------- | --------------------------------------------------------------------------- |
| quantumFairApp          | Tab rendering, jobsubmitted event handling, jobcomplete event forwarding    |
| qrngSetup               | Settings wire, save settings imperative call, test connection, toast events |
| qrngRequestForm         | Form validation, submit dispatches jobsubmitted event, Bell test toggle     |
| qrngJobMonitor          | Wire adapter for job details, empApi subscription, status path rendering    |
| qrngCircuitVisualizer   | Canvas rendering called on renderedCallback, qubit count changes            |
| qrngResultsVisualizer   | Distribution computation, canvas rendering, empty state                     |
| qrngFairnessCertificate | Certificate wire, verify button, visual hash canvas, status badge           |
| qrngAssignmentTable     | Wire adapter, datatable columns, empty state                                |
| qrngAuditTrail          | Wire adapter, computed properties (iconName, badgeClass), modal open/close  |
| qrngBellTestIndicator   | Gauge style computation, quantum vs classical verdict                       |

**Mock strategy:**

- Apex methods: sfdx-lwc-jest auto-mocks `@salesforce/apex/*` imports — each test provides mock data via `jest.mock()` or the wire adapter test utility
- `lightning/empApi`: manual mock that simulates subscribe/unsubscribe
- `lightning/platformShowToastEvent`: manual mock that captures dispatched toasts
- Canvas 2D: jsdom doesn't have Canvas — mock `getContext('2d')` to return a stub

### Phase 2: GitHub Actions Workflows

**Files to create:**

```
.github/
└── workflows/
    ├── test.yml           ← Layer 2: runs on every push/PR
    └── apex-test.yml      ← Layer 3: runs on merge to master
```

#### `.github/workflows/test.yml` — Fast CI (every push/PR)

```yaml
name: Test
on:
    push:
        branches: ['**']
    pull_request:
        branches: [master]

jobs:
    test:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
            - uses: actions/setup-node@v4
              with:
                  node-version: 20
                  cache: npm
            - run: npm ci
            - run: npm run prettier:verify
            - run: npm run lint
            - run: npm run test:unit:coverage
            - uses: actions/upload-artifact@v4
              if: always()
              with:
                  name: coverage
                  path: coverage/
```

#### `.github/workflows/apex-test.yml` — Full CI (PRs targeting master + merge to master)

```yaml
name: Apex Tests
on:
    push:
        branches: [master]
    pull_request:
        branches: [master]

jobs:
    apex-test:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
            - uses: actions/setup-node@v4
              with:
                  node-version: 20
                  cache: npm
            - run: npm ci

            # Install Salesforce CLI
            - run: npm install -g @salesforce/cli

            # Authenticate DevHub
            - run: echo "${{ secrets.SFDX_AUTH_URL }}" > auth.txt && sf org login sfdx-url -f auth.txt -a devhub -d && rm auth.txt

            # Create scratch org
            - run: sf org create scratch -f config/project-scratch-def.json -a ci-test -d 1 -w 10

            # Deploy
            - run: sf project deploy start -o ci-test --ignore-conflicts

            # Run Apex tests
            - run: sf apex run test -o ci-test --code-coverage --result-format json --output-dir apex-results --wait 15

            # Check coverage threshold (79% org-wide minimum)
            - run: |
                  COVERAGE=$(cat apex-results/test-result-codecoverage.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(int(float(d[-1]['coveredPercent'])))")
                  echo "Org coverage: ${COVERAGE}%"
                  if [ "$COVERAGE" -lt 75 ]; then echo "Coverage below 75%!" && exit 1; fi

            # Cleanup
            - if: always()
              run: sf org delete scratch -o ci-test --no-prompt || true

            # Upload results
            - uses: actions/upload-artifact@v4
              if: always()
              with:
                  name: apex-test-results
                  path: apex-results/
```

### Phase 3: Jest Coverage Thresholds

Add to `jest.config.js`:

```javascript
module.exports = {
    ...require('@salesforce/sfdx-lwc-jest/config'),
    testPathIgnorePatterns: ['.localdevserver'],
    coverageThreshold: {
        global: {
            branches: 70,
            functions: 80,
            lines: 80,
            statements: 80
        }
    }
};
```

### Phase 4: GitHub Secrets Setup (manual, documented)

The user needs to add one GitHub secret for Apex CI:

- `SFDX_AUTH_URL` — the DevHub auth URL

Generate it locally:

```bash
sf org display -o <devhub-alias> --verbose --json | jq -r '.result.sfdxAuthUrl'
```

Then add it to GitHub repo Settings > Secrets and variables > Actions.

---

## What Runs Where — Summary

| Check         | Local (on-demand)         | PR CI                | Master CI            |
| ------------- | ------------------------- | -------------------- | -------------------- |
| Prettier      | `npm run prettier:verify` | all files            | all files            |
| ESLint        | `npm run lint`            | all files            | all files            |
| LWC Jest      | `npm test`                | all tests + coverage | all tests + coverage |
| Apex deploy   | -                         | -                    | scratch org          |
| Apex tests    | -                         | -                    | scratch org          |
| Coverage gate | -                         | Jest 80%             | Jest 80% + Apex 75%  |

**Philosophy:** Commits and pushes are never blocked. CI catches issues. Developer fixes on the next commit.

---

## Estimated Effort

| Phase                           | Work                             |
| ------------------------------- | -------------------------------- |
| Phase 1: LWC Jest tests + mocks | 10 test files + 2 mock files     |
| Phase 2: GitHub Actions         | 2 workflow files                 |
| Phase 3: Coverage thresholds    | 1 config update                  |
| Phase 4: Secret setup           | Manual — documented instructions |

---

## Decisions (Resolved 2026-03-17)

1. **Coverage thresholds** — 80% LWC / 75% Apex org-wide. Approved.
2. **Apex CI frequency** — Runs on PRs targeting master AND merge to master. PR is the key quality gate.
3. **Canvas mocking** — Shallow testing (verify render called, not pixel output). Approved.
