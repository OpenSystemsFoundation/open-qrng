# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Apache-2.0 `LICENSE` and `NOTICE` files; `license` and `engines` fields in
  `package.json`
- Open-source process files: `SECURITY.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, issue and PR templates, Dependabot config
- `QuantumFair` Platform Cache partition for the IBM auth token cache
  (zero default allocation; auth falls back gracefully without capacity)

### Changed

- Distribution model set to unmanaged package / source deploy: removed the
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

### Removed

- Dead `Quantum_Backend_Config__mdt` custom metadata type
- Dead `lint-staged`/`precommit` tooling (CI-only enforcement) and the
  duplicate standalone `playwright` dependency
- Stale `.forceignore` rules and internal working docs from the repo root
  (moved to `docs/internal/`)
