---
name: qiskit-skill
description: >
    Write, debug, optimize, and explain quantum computing code using Qiskit SDK v2.3 and
    qiskit-ibm-runtime. Triggers on any mention of Qiskit, quantum circuits, quantum computing
    with Python, IBM Quantum, quantum gates, transpilation, quantum primitives (Sampler/Estimator),
    SparsePauliOp, QuantumCircuit, or running circuits on IBM quantum hardware. Use when the user
    wants to: (1) build or modify quantum circuits, (2) transpile circuits for hardware,
    (3) run circuits via Qiskit Runtime primitives (EstimatorV2/SamplerV2), (4) simulate locally
    with StatevectorEstimator/StatevectorSampler, (5) use error mitigation/suppression,
    (6) work with quantum information (operators, states), (7) serialize circuits (QASM2/3, QPY),
    or (8) understand Qiskit concepts and APIs. Also triggers on VQE, QAOA, Grover, quantum
    entanglement code, Bell state, GHZ state, any IBM Quantum Platform task, OpenQASM, QASM,
    qasm2, qasm3, OpenQASM 3 syntax, stdgates.inc, QASM export/import, or QPY serialization.
---

# Qiskit SDK v2.3 Skill

## Installation

```
pip install 'qiskit[all]~=2.3.0'
pip install qiskit-ibm-runtime
```

Requires Python ≥3.10 (Python 3.9 dropped in v2.3). For hardware access, also install `qiskit-ibm-runtime`.

## Core Workflow: Qiskit Patterns

Every quantum program follows four steps:

1. **Map** the problem → quantum circuits + operators
2. **Optimize** circuits via transpilation for target hardware
3. **Execute** using primitives (Sampler or Estimator)
4. **Analyze** results

## Quick Reference

### Circuit Construction

```python
from qiskit import QuantumCircuit

qc = QuantumCircuit(2)       # 2 qubits
qc.h(0)                      # Hadamard on qubit 0
qc.cx(0, 1)                  # CNOT: control=0, target=1
qc.measure_all()             # Add measurements to all qubits
qc.draw("mpl")               # Visualize
```

Key methods: `qc.h()`, `qc.x()`, `qc.cx()`, `qc.rz()`, `qc.measure()`, `qc.barrier()`,
`qc.append(gate, qubits)`, `qc.compose(other_circuit)`.

Parametric circuits:

```python
from qiskit.circuit import Parameter
theta = Parameter("θ")
qc = QuantumCircuit(1)
qc.ry(theta, 0)
```

### Transpilation

Use `generate_preset_pass_manager` (preferred) or `transpile()`:

```python
from qiskit.transpiler import generate_preset_pass_manager

pm = generate_preset_pass_manager(backend=backend, optimization_level=2)
isa_circuit = pm.run(qc)
```

- `optimization_level`: 0 (none) → 3 (maximum). Default is 2.
- Pass a `backend` to auto-configure basis gates, coupling map, and target.
- Stages: init → layout → routing → translation → optimization → scheduling.
- In v2.0+, deprecated args (`inst_map`, `backend_properties`, `instruction_durations`, `timing_constraints`) are removed. Use `target` parameter or pass a `backend` directly.

### Primitives (Execution)

Two V2 primitives in `qiskit-ibm-runtime`:

**SamplerV2** — samples output distributions:

```python
from qiskit_ibm_runtime import QiskitRuntimeService, SamplerV2 as Sampler

service = QiskitRuntimeService()
backend = service.least_busy(operational=True, simulator=False)
sampler = Sampler(mode=backend)
job = sampler.run([isa_circuit])
result = job.result()
counts = result[0].data.meas.get_counts()
```

**EstimatorV2** — computes expectation values:

```python
from qiskit_ibm_runtime import EstimatorV2 as Estimator
from qiskit.quantum_info import SparsePauliOp

observable = SparsePauliOp("ZZ")
estimator = Estimator(mode=backend)
job = estimator.run([(isa_circuit, observable)])
result = job.result()
exp_val = result[0].data.evs
```

PUB (Primitive Unified Bloc) format:

- Sampler: `(circuit, parameter_values?, shots?)`
- Estimator: `(circuit, observables, parameter_values?, precision?)`

### Local Simulation (No Hardware)

```python
from qiskit.primitives import StatevectorSampler, StatevectorEstimator

sampler = StatevectorSampler()
estimator = StatevectorEstimator()
# Same .run() interface as Runtime primitives
```

### Error Mitigation Options (Runtime)

```python
estimator = Estimator(mode=backend)
estimator.options.resilience_level = 2          # 0, 1, or 2
estimator.options.resilience.measure_mitigation = True
sampler.options.dynamical_decoupling.enable = True
sampler.options.dynamical_decoupling.sequence_type = "XpXm"
```

## Key Modules

| Module                           | Purpose                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `qiskit.circuit`                 | QuantumCircuit, gates, parameters                                                                             |
| `qiskit.circuit.library`         | Standard gates, ansatze, feature maps                                                                         |
| `qiskit.quantum_info`            | SparsePauliOp, Statevector, Operator, DensityMatrix                                                           |
| `qiskit.transpiler`              | generate_preset_pass_manager, transpile, passes                                                               |
| `qiskit.primitives`              | StatevectorSampler, StatevectorEstimator (local sim)                                                          |
| `qiskit.synthesis`               | Circuit synthesis routines                                                                                    |
| `qiskit.qasm3`                   | OpenQASM 3 import/export (load/loads/dump/dumps/Exporter; import requires `pip install qiskit[qasm3-import]`) |
| `qiskit.qpy`                     | Binary circuit serialization                                                                                  |
| `qiskit.visualization`           | plot_histogram, plot_bloch_multivector, circuit drawing                                                       |
| `qiskit.providers.fake_provider` | GenericBackendV2 for testing                                                                                  |

## Reference Files

For detailed information, read these reference files as needed:

- **[references/circuits.md](references/circuits.md)** — Deep dive on QuantumCircuit API, circuit library, parametric circuits, classical control flow, compose/append patterns
- **[references/transpiler.md](references/transpiler.md)** — Transpiler stages, optimization levels, custom pass managers, v2.0+ changes
- **[references/primitives_runtime.md](references/primitives_runtime.md)** — Complete guide to V2 primitives, PUBs, result handling, options, sessions/batches, error mitigation, QiskitRuntimeService setup
- **[references/openqasm.md](references/openqasm.md)** — Comprehensive OpenQASM 3 guide (v3.1 spec): qiskit.qasm3 full API (load/loads/dump/dumps/Exporter), OpenQASM 3 language features (classical types, control flow, gate modifiers, subroutines, timing, pragmas/annotations), v3.1 changes, Qiskit feature support table, QPY vs QASM comparison
- **[references/v2_migration.md](references/v2_migration.md)** — Breaking changes in Qiskit v2.0–v2.3, removed APIs, migration patterns

## Common Pitfalls

- **Always transpile before running on hardware.** Circuits must be ISA-compatible.
- **V1 primitives are removed.** Use `EstimatorV2`/`SamplerV2` explicitly.
- **`backend.run()` is removed.** Migrate to SamplerV2.
- **`c_if` is removed in v2.0.** Use `qc.if_test()` context manager instead.
- **Instruction `duration`/`unit` fields removed from gates in v2.0.** Query `Target` for durations.
- **`ibm_quantum` channel is sunset.** Use `ibm_quantum_platform` channel.
- **Sampler circuits must contain measurements.**
- **Observables must be applied to the ISA layout:** `observable.apply_layout(isa_circuit.layout)`.
- **OpenQASM 3 import requires extra package:** `pip install qiskit[qasm3-import]` (installs `qiskit_qasm3_import`).
- **OpenQASM is not lossless.** Use QPY for full round-trip serialization of QuantumCircuit.
- **Not all QASM 3 features can be parsed yet.** Variable declarations, duration/stretch types, and subroutines are export-only as of Qiskit v2.3.
