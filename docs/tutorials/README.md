# QuantumFair Domain Tutorials

Step-by-step guides for Salesforce admins to implement quantum-certified fair randomization across industries. Each tutorial uses Flow Builder where possible and notes Apex alternatives for scale.

> **New here?** Start with the [Generalized Pipeline](generalized-pipeline.md) guide to understand the end-to-end QRNG formula before diving into a domain-specific tutorial.

## Prerequisites

Before following any tutorial, ensure:

1. **QuantumFair is installed** in your org (managed package)
2. **IBM Quantum API key** is configured via the QuantumFair Setup tab
3. **Permission sets** are assigned:
    - `QuantumFair_Admin` for admins configuring the system
    - `QuantumFair_User` for end users who trigger assignments
4. **Connection test passes** in the QuantumFair Setup panel

## Tutorials by Domain

### [Sales](sales/)

| Tutorial                                                 | Description                                         |
| -------------------------------------------------------- | --------------------------------------------------- |
| [Lead Round-Robin Assignment](sales/lead-round-robin.md) | Distribute inbound leads fairly across sales reps   |
| [Territory Rebalancing](sales/territory-rebalancing.md)  | Randomly reassign accounts during territory changes |
| [Deal Review Selection](sales/deal-review-selection.md)  | Select deals for pipeline review without bias       |

### [Healthcare](healthcare/)

| Tutorial                                                                   | Description                                  |
| -------------------------------------------------------------------------- | -------------------------------------------- |
| [Patient Provider Assignment](healthcare/patient-provider-assignment.md)   | Assign new patients to providers fairly      |
| [Clinical Trial Randomization](healthcare/clinical-trial-randomization.md) | Randomize participants into treatment groups |
| [Quality Audit Sampling](healthcare/quality-audit-sampling.md)             | Select patient records for compliance audits |

### [Financial Services](financial-services/)

| Tutorial                                                               | Description                                           |
| ---------------------------------------------------------------------- | ----------------------------------------------------- |
| [Audit Case Selection](financial-services/audit-case-selection.md)     | Randomly select accounts for regulatory audit         |
| [Loan Review Assignment](financial-services/loan-review-assignment.md) | Assign loan applications to underwriters without bias |
| [Compliance Spot-Check](financial-services/compliance-spot-check.md)   | Sample transactions for compliance review             |

### [Human Resources](human-resources/)

| Tutorial                                                                  | Description                                              |
| ------------------------------------------------------------------------- | -------------------------------------------------------- |
| [Interview Panel Selection](human-resources/interview-panel-selection.md) | Select unbiased interview panels from eligible reviewers |
| [Shift Assignment](human-resources/shift-assignment.md)                   | Fairly assign premium or undesirable shifts              |
| [Training Slot Allocation](human-resources/training-slot-allocation.md)   | Allocate limited training seats without favoritism       |

### [Education](education/)

| Tutorial                                                          | Description                                       |
| ----------------------------------------------------------------- | ------------------------------------------------- |
| [Class Section Assignment](education/class-section-assignment.md) | Distribute students across sections equitably     |
| [Scholarship Selection](education/scholarship-selection.md)       | Select scholarship recipients from qualified pool |
| [Peer Review Matching](education/peer-review-matching.md)         | Randomly pair students for peer review            |

### [Government](government/)

| Tutorial                                                           | Description                                    |
| ------------------------------------------------------------------ | ---------------------------------------------- |
| [Permit Review Assignment](government/permit-review-assignment.md) | Assign permit applications to reviewers fairly |
| [Inspection Selection](government/inspection-selection.md)         | Select sites for random inspection             |
| [Citizen Panel Selection](government/citizen-panel-selection.md)   | Choose representative citizen advisory panels  |

### [Customer Service](customer-service/)

| Tutorial                                                           | Description                                           |
| ------------------------------------------------------------------ | ----------------------------------------------------- |
| [Case Routing](customer-service/case-routing.md)                   | Route support cases to agents with certified fairness |
| [QA Sample Selection](customer-service/qa-sample-selection.md)     | Select agent interactions for quality review          |
| [Escalation Assignment](customer-service/escalation-assignment.md) | Assign escalated cases to senior agents fairly        |

## Common Patterns

All tutorials follow the same core pattern:

1. **Collect record IDs** — gather the records to be assigned or sampled
2. **Collect assignee IDs** — gather the users, queues, or groups receiving assignments
3. **Call the QuantumFair invocable action** — `Quantum Random Assignment` in Flow Builder
4. **Handle the result** — the action is async; listen for `QRNG_Complete__e` or check the Quantum Job record
5. **View the certificate** — every assignment gets a Fairness Certificate for audit

## Flow vs. Apex

| Approach             | Best For                                          | Limits                                           |
| -------------------- | ------------------------------------------------- | ------------------------------------------------ |
| **Flow Builder**     | < 200 records, admin-maintained, standard objects | Flow collection size, governor limits            |
| **Apex (Invocable)** | > 200 records, complex logic, custom objects      | Requires developer, but same fairness guarantees |

The `Quantum Random Assignment` invocable action works identically in both — Flows call the same Apex under the hood.
