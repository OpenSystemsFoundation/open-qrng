# Contributing to QuantumFair

Thanks for your interest in contributing! QuantumFair is an Apache-2.0
licensed Salesforce app providing certified quantum random number generation.
This guide covers setup, testing, and pull request expectations.

## Prerequisites

- Node.js 20+
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- A Salesforce Dev Hub (for scratch orgs) — free
  [Developer Edition](https://developer.salesforce.com/signup) orgs can enable
  Dev Hub in Setup

## Development Setup

```bash
git clone https://github.com/OpenSystemsFoundation/open-qrng.git
cd open-qrng
npm install
```

### Scratch org

```bash
sf org login web --set-default-dev-hub          # authenticate your Dev Hub
sf org create scratch -f config/project-scratch-def.json -a qrng-dev
sf project deploy start --target-org qrng-dev
sf org assign permset -n QuantumFair_Admin --target-org qrng-dev
sf org assign permset -n QuantumFair_User --target-org qrng-dev
sf org open --target-org qrng-dev
```

If you develop from Claude Code on the web, the SessionStart hook in
`.claude/settings.json` performs these steps automatically (see `CLAUDE.md`).

## Testing

All of these must pass before a PR can merge:

```bash
npm run test:unit            # LWC Jest tests
npm run lint                 # ESLint (zero errors/warnings)
npm run prettier:verify      # Formatting check
npm run test:e2e             # Playwright E2E (mock fixture, no org needed)

# Apex tests (requires a scratch org)
sf apex run test --target-org qrng-dev --code-coverage --result-format human --wait 10
```

## Pull Requests

1. Fork and create a feature branch from `master`.
2. Keep changes focused; include tests for new behavior.
3. Read `ARCHITECTURE.md` before structural changes — it is the source of
   truth for system design.
4. Fill in the PR template (summary + testing checklist).

### Required CI checks

- **Test** — Prettier, ESLint, LWC Jest, Playwright E2E
- **Apex Tests** — full Apex suite in a scratch org (runs for same-repo PRs;
  fork PRs cannot access the Dev Hub secret and are skipped)
- **Security Scan** — Salesforce Code Analyzer + npm audit
- **OpenQASM Circuit Validation** — structural QASM checks

## Code Style

- **Prettier** formats everything (`npm run prettier`); CI verifies it.
- **ESLint** must report zero errors and zero warnings.
- **Apex:** `with sharing` on all classes; no raw API keys or PII in code or
  logs; aim for 90%+ test coverage per class.
- **LWC:** no third-party JS libraries; Canvas 2D for visuals; a Jest test
  file for every component.
- **Determinism:** the same quantum bits must always produce the same
  assignment — this is what makes certificates audit-verifiable.

## Reporting Issues

Use the issue templates for bugs and feature requests. For security
vulnerabilities, follow [SECURITY.md](SECURITY.md) — do not open a public
issue.

## License

By contributing, you agree that your contributions will be licensed under the
Apache License 2.0 (see [LICENSE](LICENSE)).
