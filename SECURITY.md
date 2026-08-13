# Security Policy

QuantumFair is a compliance and audit product — we take security reports
seriously and appreciate responsible disclosure.

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/OpenSystemsFoundation/open-qrng/security/advisories/new)
("Report a vulnerability" on the repository's Security tab).

Include, where possible:

- A description of the vulnerability and its impact
- Steps to reproduce (org configuration, affected component, payload)
- Any suggested remediation

## Response Targets

- **Acknowledgement:** within 14 days of the report
- **Triage and initial assessment:** communicated in the advisory thread
- **Fix and disclosure:** coordinated with the reporter; we credit
  reporters in the release notes unless they prefer otherwise

## Supported Versions

| Version                          | Supported |
| -------------------------------- | --------- |
| Latest `master` / latest release | Yes       |
| Older releases                   | No        |

QuantumFair is distributed as open source (deploy from source or install as
an unmanaged package), so upgrading to the latest release is the supported
remediation path.

## Scope Notes

- QuantumFair runs entirely on the Salesforce platform; there are no
  project-operated servers.
- Each org supplies its own IBM Quantum API key (BYOQ). Compromise scenarios
  involving that key in your org's configuration should also be reported to
  your Salesforce admin and IBM.
- npm dependencies are development-only; the package ships no npm runtime
  code.
