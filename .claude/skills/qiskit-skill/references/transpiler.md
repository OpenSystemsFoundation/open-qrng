# Transpiler Reference — Qiskit v2.3

## Table of Contents

1. [Overview](#overview)
2. [generate_preset_pass_manager](#generate_preset_pass_manager)
3. [Optimization Levels](#optimization-levels)
4. [Transpiler Stages](#transpiler-stages)
5. [Custom Pass Managers](#custom-pass-managers)
6. [ISA Circuits](#isa-circuits)
7. [v2.3 Transpiler Features](#v23-transpiler-features)

---

## Overview

Transpilation converts abstract quantum circuits into ISA (Instruction Set Architecture)
circuits that respect the hardware's basis gates, coupling map, and timing constraints.

Two main entry points:

```python
# Preferred: generate a reusable pass manager
from qiskit.transpiler import generate_preset_pass_manager
pm = generate_preset_pass_manager(backend=backend, optimization_level=2)
isa_circuit = pm.run(qc)

# Convenience function (wraps the above)
from qiskit import transpile
isa_circuit = transpile(qc, backend=backend, optimization_level=2)
```

## generate_preset_pass_manager

```python
generate_preset_pass_manager(
    optimization_level=2,     # 0, 1, 2, or 3
    backend=None,             # BackendV2 instance
    target=None,              # Target object (alternative to backend)
    basis_gates=None,         # e.g. ['cx', 'id', 'rz', 'sx', 'x']
    coupling_map=None,        # CouplingMap or list of edges
    initial_layout=None,      # Layout object
    layout_method=None,       # 'trivial', 'dense', 'sabre'
    routing_method=None,      # 'basic', 'stochastic', 'sabre'
    translation_method=None,  # 'translator', 'synthesis'
    scheduling_method=None,   # 'alap', 'asap'
    approximation_degree=1.0,
    seed_transpiler=None,
    unitary_synthesis_method='default',
    hls_config=None,          # HLSConfig for high-level synthesis
    dt=None,                  # Backend timing unit (seconds)
    qubits_initially_zero=True,
)
```

Returns a `StagedPassManager` that can be reused: `pm.run(circuit)` or `pm.run([circuits])`.

**v2.0+ removed args:** `inst_map`, `backend_properties`, `instruction_durations`,
`timing_constraints`. Use `Target.from_configuration(...)` if needed.

## Optimization Levels

| Level | Description                                                                                                                                                         |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | No optimization. Maps to backend constraints only. Good for device characterization.                                                                                |
| 1     | Light optimization. Adjacent gate collapsing, layout search with VF2Layout + SabreLayout fallback.                                                                  |
| 2     | Medium optimization (default). More aggressive gate cancellation, VF2Layout/VF2PostLayout, peephole optimization.                                                   |
| 3     | Maximum optimization. Full VF2PostLayout re-evaluation with strict_direction=True, unitarity-based resynthesis, gate commutativity exploited. Longer compile times. |

## Transpiler Stages

The six-stage pipeline:

1. **init** — Unrolls custom instructions, converts to 1- and 2-qubit gates, initial cleanup.
2. **layout** — Maps virtual qubits to physical qubits.
    - `VF2Layout`: tries exact subgraph isomorphism (no swaps needed).
    - `SabreLayout`: heuristic fallback.
    - `TrivialLayout`: i-th virtual → i-th physical.
    - `DenseLayout`: maps to most connected subgraph.
3. **routing** — Inserts SWAPs to satisfy coupling constraints.
    - `SabreSwap`: default, heuristic.
    - `StochasticSwap`: randomized.
    - `BasicSwap`: simple greedy.
4. **translation** — Converts to basis gates of the target.
5. **optimization** — Gate cancellation, commutation analysis, resynthesis.
    - `VF2PostLayout` re-runs at level 3 after optimization.
6. **scheduling** — Inserts delays/timing. `alap` (as late as possible) or `asap`.

## Custom Pass Managers

```python
from qiskit.transpiler import PassManager, StagedPassManager
from qiskit.transpiler.passes import Optimize1qGatesDecomposition, CXCancellation

# Simple custom pass manager
pm = PassManager([Optimize1qGatesDecomposition(), CXCancellation()])
optimized = pm.run(qc)

# Modify a stage of a preset manager
preset_pm = generate_preset_pass_manager(backend=backend, optimization_level=2)
preset_pm.optimization = PassManager([Optimize1qGatesDecomposition()])
isa = preset_pm.run(qc)
```

### Target and GenericBackendV2

```python
from qiskit.providers.fake_provider import GenericBackendV2
fake_backend = GenericBackendV2(num_qubits=5)
pm = generate_preset_pass_manager(backend=fake_backend, optimization_level=2)

# Access target
target = fake_backend.target
print(target.operation_names)
print(target.qargs)
```

## ISA Circuits

After transpilation, a circuit is "ISA-compatible":

- Only uses basis gates supported by the backend.
- Respects coupling map (2-qubit gates only on connected pairs).
- Virtual qubits mapped to physical qubits.

The layout is stored in `isa_circuit.layout` as a `TranspileLayout`:

```python
layout = isa_circuit.layout
# Get the routing permutation
perm = layout.routing_permutation()
# Apply layout to an observable
isa_observable = observable.apply_layout(layout)
```

## v2.3 Transpiler Features

- **C API expansion:** `QkTarget`, `QkDag` available from C for custom transpiler passes.
  Individual stage functions like `qk_transpile_stage_layout()` available.
- **PauliProductMeasurement instruction:** Projective measurement into Pauli product basis.
  Used with `LitinskiTransformation` pass for fault-tolerant transpilation.
- **ControlFlowOp Rust-native representation:** Internal transition (may cause temporary
  performance regression with control-flow circuits).
- **VF2PostLayout tuning:** max_trials argument behavior changed; on-the-fly score-and-prune.
- **WrapAngles.DEFAULT_REGISTRY:** Preferred location for wrap angles registry.
- **Python 3.9 dropped, macOS Intel downgraded to Tier 2.**
- **`Gate.control(annotated=True)` behavior:** Now returns native controlled gate when available
  instead of AnnotatedOperation.
