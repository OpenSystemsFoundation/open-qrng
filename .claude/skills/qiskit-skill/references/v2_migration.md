# Qiskit v2.0–v2.3 Migration Reference

## Table of Contents

1. [v2.0 Breaking Changes](#v20-breaking-changes)
2. [v2.1–v2.2 Changes](#v21-v22-changes)
3. [v2.3 Changes](#v23-changes)
4. [Migration Patterns](#migration-patterns)

---

## v2.0 Breaking Changes

### Classical Conditions: `c_if` Removed

```python
# OLD (removed)
qc.x(0).c_if(cr, 3)

# NEW: if_test context manager
with qc.if_test((cr, 3)):
    qc.x(0)

# With else
with qc.if_test((cr, 3)) as else_:
    qc.x(0)
with else_:
    qc.h(0)

# Complex expressions
from qiskit.circuit.classical import expr
with qc.if_test(expr.equal(cr, 3)):
    qc.x(0)
```

### Instruction duration/unit Fields Removed

Gates no longer store `duration` and `unit` attributes. Query the `Target` instead:

```python
target = backend.target
props = target["cx"][2, 4]
duration = None if props is None else props.duration
```

`QuantumCircuit.duration` attribute is deprecated. Use `QuantumCircuit.estimate_duration()`.

### Transpiler Argument Cleanup

Removed from `generate_preset_pass_manager` and `transpile`:

- `inst_map` — Qiskit Pulse is deprecated
- `backend_properties` — use `target`
- `instruction_durations` — use `target`
- `timing_constraints` — use `target`

Build a `Target` if needed:

```python
target = Target.from_configuration(
    basis_gates=basis_gates,
    coupling_map=coupling_map,
    instruction_durations=durations,
)
pm = generate_preset_pass_manager(target=target, optimization_level=2)
```

### Condition Attribute Removed from Instruction

`Instruction.condition` no longer exists. Use `IfElseOp` via `qc.if_test()`.

### Preset Pass Manager Default Level

Default `optimization_level` changed to **2** (was 1 in some contexts).

### generate_pre_op_passmanager Deprecated

Translation plugins now handle ISA directionality. Typically no replacement needed.

## v2.1–v2.2 Changes

### v2.1

- `VF2PostLayout` re-enabled at optimization_level=3 with `strict_direction=True`.
- Performance improvements in Rust-based transpiler passes.

### v2.2

- **Last version supporting Python 3.9.**
- Minimum Rust build version: 1.85.
- C API: `QkTarget` supports parameterized gates via `qk_target_entry_new()`.
- New standalone transpiler pass functions in C API.
- Deprecated circuit library classes replaced with Gate equivalents:
    - Many QuantumCircuit-based library classes deprecated in favor of Gate subclasses.
    - Use function-based constructors (e.g., `zz_feature_map()`) instead of class-based ones.
- `ElidePermutations` bug fix for `PermutationGate` mapping.
- `PhaseOracle`/`PhaseOracleGate`/`BitFlipOracleGate` DIMACS loading fixed.

## v2.3 Changes

### Python & Platform Support

- **Python 3.9 dropped** (end of life October 2025).
- **macOS Intel downgraded to Tier 2** platform support.
- All CPython versions from 3.10 onwards supported.

### Transpilation

- **C API expanded:** More of `Target` (`QkTarget`) and `DAGCircuit` (`QkDag`) accessible from C.
  Individual transpilation stage functions available (e.g., `qk_transpile_stage_layout()`).
- **PauliProductMeasurement instruction:** Projective measurement into Pauli product basis.
  Enables transpiling to Pauli-based computation basis via `LitinskiTransformation` pass.
- **Improved fault-tolerant transpilation** performance and feature set.

### Internal Changes

- **ControlFlowOp Rust-native representation:** Transition ongoing, may cause temporary
  performance regression with control-flow circuits. Expected to improve in later versions.
- `ControlFlowOp` blocks no longer track `name` or `metadata` fields.
- `Gate.control(annotated=True)` now returns native controlled gate when available.

### Transpiler Tuning

- `VF2PostLayout` at optimization_level=3: reduced max call/trial limits for highly
  symmetric circuits on large coupling maps.
- `WrapAngles.DEFAULT_REGISTRY` is the preferred registry location.
- `VF2Layout`/`VF2PostLayout` `max_trials` behavior changed: on-the-fly score-and-prune
  means "complete" layouts are encountered less frequently.

### Future

- No Qiskit 3.0 expected until later in 2026; no current need for breaking changes.
- Further feature releases in 2.x series planned.

## Migration Patterns

### backend.run() → SamplerV2

```python
# OLD
from qiskit import transpile
transpiled = transpile(qc, backend)
job = backend.run(transpiled, shots=1024)
counts = job.result().get_counts()

# NEW
from qiskit.transpiler import generate_preset_pass_manager
from qiskit_ibm_runtime import SamplerV2 as Sampler

pm = generate_preset_pass_manager(backend=backend, optimization_level=2)
isa = pm.run(qc)
sampler = Sampler(mode=backend)
job = sampler.run([isa])
counts = job.result()[0].data.meas.get_counts()
```

### V1 Primitives → V2 Primitives

```python
# OLD V1
from qiskit_ibm_runtime import Estimator, Options
options = Options()
options.resilience_level = 2
estimator = Estimator(backend, options=options)
job = estimator.run(circuits, observables)

# NEW V2
from qiskit_ibm_runtime import EstimatorV2 as Estimator
estimator = Estimator(mode=backend)
estimator.options.resilience_level = 2
job = estimator.run([(isa_circuit, isa_observable)])
result = job.result()
print(result[0].data.evs)
```

Key V1 → V2 differences:

- Input: list of PUB tuples instead of separate circuit/observable lists.
- Options: set on instance attributes, not via Options class.
- Results: indexed by PUB, access `.data.evs` / `.data.meas`.
- Observables must be applied to ISA layout.

### ibm_quantum → ibm_quantum_platform

```python
# OLD
QiskitRuntimeService.save_account(channel="ibm_quantum", token="...")

# NEW
QiskitRuntimeService.save_account(channel="ibm_quantum_platform", token="...")
```
