# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- QuantumFair app logo (the Bloch sphere icon) as the Lightning app's brand
  image: shipped as the `QuantumFairLogo` ContentAsset and shown in the App
  Launcher and, with the app's theme override, top left while the app is open

### Changed

- CI simplified to one workflow, `ci.yml`: ESLint, Prettier and LWC Jest on
  pull requests and pushes to `master`, with no org and no secrets. Removed the
  scratch-org Apex workflow, both Playwright E2E workflows, OpenQASM
  validation, the security scan and the PR/commit result comments. Apex tests
  still run in the dev scratch org and in every package version build

## [1.0.0] - 2026-11-14

First public release, published as an Open Systems Foundation Labs tech demo
and distributed as an unlocked package with no namespace (install link on the GitHub release)
and as source.

### Install

QuantumFair 1.0.0 is an unlocked package with no namespace (package version
ID `04tTt0000001QWjIAM`). Log in as an admin, open the link for your org type
and choose **Install for Admins Only**:

| Org                             | Install link                                                                      |
| ------------------------------- | --------------------------------------------------------------------------------- |
| Production or Developer Edition | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tTt0000001QWjIAM |
| Sandbox                         | https://test.salesforce.com/packaging/installPackage.apexp?p0=04tTt0000001QWjIAM  |

Or with the Salesforce CLI:

```bash
sf package install --package 04tTt0000001QWjIAM --target-org <your-org> --wait 20 --security-type AdminsOnly
```

Then assign the `QuantumFair_Admin` permission set to yourself and follow the
[manual](https://github.com/OpenSystemsFoundation/open-qrng/blob/v1.0.0/docs/manual.md)
to connect your IBM Quantum account. You can also deploy from source (see the
README).

### Added

- Unlocked package `QuantumFair` (no namespace) v1.0 and GitHub release
- `scripts/seed-demo-data.sh`: seeds a scratch org with demo jobs,
  certificates and assignments by feeding mocked IBM Sampler results through
  the real processing pipeline — explore the app without an IBM account
- Screenshots in `docs/images/`
- `docs/solution-design.md` (technical design, consolidated from the former
  `ARCHITECTURE.md` and `PROVIDERS.md`) and `docs/manual.md` (installation,
  configuration, usage, Flow integration, verification, troubleshooting)

- Apache-2.0 `LICENSE` and `NOTICE` files; `license` and `engines` fields in
  `package.json`
- Open-source process files: `SECURITY.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, issue and PR templates, Dependabot config
- `QuantumFair` Platform Cache partition for the IBM auth token cache
  (zero default allocation; auth falls back gracefully without capacity)

### Changed

- README rewritten for the public release; documentation corrected to
  match the code (Heron native two-qubit gate is `cz`; no AppExchange
  listing)
- Distribution model set to a no-namespace package / source deploy: removed the
  `OpenSF` namespace from `sfdx-project.json`, the scratch org definition, and
  the sample flows' invocable action names
- Sample flows now document that the invocable action enqueues work
  asynchronously and results arrive via the `Quantum_Job_Complete__e`
  Platform Event; removed references to non-existent companion flows
- CI hardening: fork-safe gating for scratch-org and comment steps,
  concurrency groups, trimmed workflow permissions, security scan now fails
  on Code Analyzer/npm audit findings, QASM validation targets
  `CircuitBuilder.cls` and fails on missing files, Playwright reporter
  configuration restored so E2E result comments work
- Regenerated `manifest/package.xml` from actual source (adds
  CustomApplication, Layout, RemoteSiteSetting; drops fossil entries)
- Bumped 5 straggler components from API v62.0 to v66.0

### Fixed

- IBM API: pin `IBM-API-Version` to `2026-04-15`. The former `2025-11-01` is not
  a published version; IBM silently served 2025-05-01, which is deprecated and
  sunsets on 2027-01-01
- IBM job status `Cancelled - Ran too long` is now terminal (`Failed`) instead
  of `Unknown`, which retried the job until the 6-hour budget ran out
- The IBM provider record stored the retired `api.quantum-computing.ibm.com`
  base URL; it now stores `https://quantum.cloud.ibm.com/api`
- Serial and approximate-entropy tests used a `3 × df` shortcut for the
  chi-squared critical value, which is too strict for small df and revoked
  about 6.6% (serial) and 1.7% (approximate entropy) of genuinely random
  pools. Both now use exact alpha = 0.01 critical values
- `SetupController_Test` passed only when the user running the tests
  already held the QuantumFair permission sets; tests that read through the
  controller now run as a dedicated admin test user, so they pass in any org
  (including the package build org)
- `QuantumSubmissionQueueable_Test` was missing its `-meta.xml`, so a clean
  source deploy failed
- Docs no longer claim the Protected custom-setting flag hides the API key
  (it is only enforced in namespaced managed packages); access is limited by
  the View All Custom Settings / Customize Application permissions
- Fairness certificate details overlapped in narrow containers (record-page
  sidebar); they now use stacked SLDS description lists
- CHSH S-values are shown rounded to three decimals in the certificate and
  audit trail

### Removed

- Dead `Quantum_Backend_Config__mdt` custom metadata type
- Dead `lint-staged`/`precommit` tooling (CI-only enforcement) and the
  duplicate standalone `playwright` dependency
- Stale `.forceignore` rules
- Internal working docs, the production readiness review, and the per-domain
  tutorials (folded into the manual)

[Unreleased]: https://github.com/OpenSystemsFoundation/open-qrng/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/OpenSystemsFoundation/open-qrng/releases/tag/v1.0.0
