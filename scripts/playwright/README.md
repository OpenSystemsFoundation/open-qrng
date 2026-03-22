# Playwright Scratch Org Login

Headless Salesforce scratch org creation and login using Playwright.

## Prerequisites

The SessionStart hook (`scripts/session-start.sh`) handles all setup automatically.
For manual setup:

```bash
npm install
npx playwright install --with-deps chromium
```

## Usage

### Auto-detect from SFDX_AUTH_URL (default in Claude Code web)

```bash
node scripts/playwright/scratch-org-login.mjs
```

### With existing Dev Hub

```bash
node scripts/playwright/scratch-org-login.mjs --devhub MyDevHub
```

### Fully headless JWT (CI)

```bash
node scripts/playwright/scratch-org-login.mjs \
  --client-id <connected-app-id> \
  --jwt-key-file /path/to/server.key \
  --devhub-username admin@devhub.org
```

### Reuse existing scratch org

```bash
node scripts/playwright/scratch-org-login.mjs --alias qrng-dev --skip-create
```

### Show the browser (debug mode)

```bash
node scripts/playwright/scratch-org-login.mjs --headed
```

## What it does

1. **Authenticates Dev Hub** — via `SFDX_AUTH_URL` (preferred), JWT, or Playwright-assisted OAuth
2. **Creates scratch org** — using `config/project-scratch-def.json`
3. **Logs in headlessly** — uses `sf org open --url-only` to get a front-door URL, then Playwright navigates to it and captures the session
4. **Deploys source** — runs `sf project deploy start`
5. **Assigns permission sets** — `QuantumFair_Admin` and `QuantumFair_User`

## Environment Variables

| Variable                 | Description                                         |
| ------------------------ | --------------------------------------------------- |
| `SFDX_AUTH_URL`          | SFDX auth URL (`force://...`) — preferred method    |
| `SFDX_DISABLE_DNS_CHECK` | Set to `true` for sandboxed environments (auto-set) |
| `SF_DEVHUB_USERNAME`     | Dev Hub username for JWT auth                       |
| `SF_CLIENT_ID`           | Connected App consumer key                          |
| `SF_JWT_KEY_FILE`        | Path to JWT private key file                        |

## Output

- Login screenshot saved to `scripts/playwright/login-screenshot.png`
- Session cookies captured for downstream automation
- Accessibility snapshot printed for headless debugging
