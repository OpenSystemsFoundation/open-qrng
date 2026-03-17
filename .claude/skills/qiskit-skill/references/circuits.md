# Circuits Reference — Qiskit v2.3

## Table of Contents

1. [QuantumCircuit Construction](#quantumcircuit-construction)
2. [Registers](#registers)
3. [Standard Gates](#standard-gates)
4. [Circuit Library](#circuit-library)
5. [Parametric Circuits](#parametric-circuits)
6. [Classical Control Flow](#classical-control-flow)
7. [Composition and Manipulation](#composition-and-manipulation)
8. [Visualization and Serialization](#visualization-and-serialization)

---

## QuantumCircuit Construction

```python
from qiskit import QuantumCircuit

# Basic: N qubits, M classical bits
qc = QuantumCircuit(3, 3)

# From registers
from qiskit.circuit import QuantumRegister, ClassicalRegister
qr = QuantumRegister(2, "q")
cr = ClassicalRegister(2, "c")
qc = QuantumCircuit(qr, cr)

# From instructions
qc = QuantumCircuit.from_instructions(instructions, qubits=(), clbits=())

# Copy structure without instructions
empty = qc.copy_empty_like()
```

Key attributes: `qc.qubits`, `qc.clbits`, `qc.data` (list of `CircuitInstruction`),
`qc.num_qubits`, `qc.num_clbits`, `qc.depth()`, `qc.size()`, `qc.count_ops()`,
`qc.layout` (set after transpilation).

## Registers

```python
from qiskit.circuit import QuantumRegister, ClassicalRegister

qr1 = QuantumRegister(2, "qreg1")
qr2 = QuantumRegister(1, "qreg2")
cr = ClassicalRegister(3, "creg")
qc = QuantumCircuit(qr1, qr2, cr)

# Find qubit info
info = qc.find_bit(qr2[0])
print(info.index, info.registers)
```

Multiple classical registers are supported and appear as separate output data fields
when using SamplerV2 (e.g., `result[0].data.alpha.get_counts()`).

## Standard Gates

Single-qubit: `h`, `x`, `y`, `z`, `s`, `sdg`, `t`, `tdg`, `sx`, `sxdg`,
`rx(θ)`, `ry(θ)`, `rz(θ)`, `p(λ)` (phase), `u(θ,φ,λ)`, `id`

Two-qubit: `cx` (CNOT), `cy`, `cz`, `ch`, `swap`, `iswap`, `ecr`,
`rzz(θ)`, `rxx(θ)`, `ryy(θ)`, `rzx(θ)`, `cp(λ)`, `crx(θ)`, `cry(θ)`, `crz(θ)`,
`cu(θ,φ,λ,γ)`, `dcx`, `cs`, `csdg`

Three-qubit: `ccx` (Toffoli), `cswap` (Fredkin), `ccz`

Multi-qubit: `mcx(control_qubits, target)`, `mcp(λ, controls, target)`

Non-unitary: `measure(qubit, cbit)`, `measure_all()`, `reset(qubit)`, `barrier()`

Usage: `qc.h(0)`, `qc.cx(0, 1)`, `qc.rz(3.14, 0)`, `qc.measure(0, 0)`

Append arbitrary gates:

```python
from qiskit.circuit.library import HGate
qc.append(HGate(), [0])
```

## Circuit Library

`qiskit.circuit.library` provides pre-built gates and circuits:

**Standard gates** (as Gate objects): `HGate`, `XGate`, `CXGate`, `RZGate`, etc.

**Parameterized circuits / Ansatze:**

- `EfficientSU2(num_qubits, reps)` — hardware-efficient ansatz
- `TwoLocal(num_qubits, rotation_blocks, entanglement_blocks)`
- `RealAmplitudes(num_qubits)`
- `ExcitationPreserving(num_qubits)`

**Feature maps:**

- `zz_feature_map(num_qubits)` — ZZ feature map (returns Gate)
- `z_feature_map(num_qubits)` — Z feature map (returns Gate)

**Quantum operations:**

- `PauliEvolutionGate(operator, time)` — time evolution under Pauli Hamiltonian
- `QFT(num_qubits)` — Quantum Fourier Transform
- `UnitaryGate(matrix)` — arbitrary unitary
- `DiagonalGate(diag)` — diagonal unitary

**Boolean logic:** `OR`, `AND`, `XOR` gates

Note: In v2.3, prefer Gate-based objects over QuantumCircuit-based ones for better
compiler performance. Many older QuantumCircuit-based classes are deprecated.

## Parametric Circuits

```python
from qiskit.circuit import Parameter, ParameterVector

# Single parameter
theta = Parameter("θ")
qc = QuantumCircuit(1)
qc.ry(theta, 0)

# Parameter vector
params = ParameterVector("p", 3)
qc = QuantumCircuit(3)
for i in range(3):
    qc.rx(params[i], i)

# Bind values
bound = qc.assign_parameters({theta: 1.57})
# Or bind with list (order matches qc.parameters)
bound = qc.assign_parameters([1.57])
```

For primitives, pass parameter values in PUBs rather than binding beforehand:

```python
import numpy as np
param_values = np.array([[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])
job = sampler.run([(isa_circuit, param_values)])
```

## Classical Control Flow

In v2.0+, `c_if` is removed. Use the builder interface:

```python
from qiskit.circuit import QuantumCircuit, ClassicalRegister

qc = QuantumCircuit(2, 2)
qc.h(0)
qc.measure(0, 0)

# if_test with context manager
with qc.if_test((qc.clbits[0], 1)):
    qc.x(1)

# if/else
with qc.if_test((qc.clbits[0], 1)) as else_:
    qc.x(1)
with else_:
    qc.h(1)

# switch statement
cr = ClassicalRegister(2)
qc2 = QuantumCircuit(2, cr)
with qc2.switch(cr) as case:
    with case(0):
        qc2.x(0)
    with case(1):
        qc2.z(0)
    with case(case.DEFAULT):
        qc2.h(0)

# while loop
with qc.while_loop((qc.clbits[0], 0)):
    qc.h(0)
    qc.measure(0, 0)

# for loop
with qc.for_loop(range(5)):
    qc.h(0)
```

Classical expressions (`qiskit.circuit.classical.expr`):

```python
from qiskit.circuit.classical import expr
with qc.if_test(expr.equal(cr, 3)):
    qc.x(0)
```

## Composition and Manipulation

```python
# compose: overlay second circuit onto first
combined = qc_a.compose(qc_b, qubits=[1, 3])
# inplace mutation
qc_a.compose(qc_b, qubits=[1, 3], inplace=True)

# tensor: side-by-side (no qubit overlap)
big = qc_a.tensor(qc_b)

# copy
copy = qc.copy()

# reverse
reversed_qc = qc.reverse_ops()

# inverse (dagger)
inv = qc.inverse()

# Depth and size
print(qc.depth())
print(qc.count_ops())
```

## Visualization and Serialization

```python
# Drawing
qc.draw("mpl")         # matplotlib figure
qc.draw("text")        # ASCII
qc.draw("latex")       # LaTeX source
print(qc)              # equivalent to draw("text")

# QASM 3 export/import (import requires: pip install qiskit[qasm3-import])
# Note: qiskit.qasm2 exists for legacy OpenQASM 2 interop but is not recommended
from qiskit.qasm3 import dumps as dumps3, loads as loads3
qasm3_str = dumps3(qc)
qc3 = loads3(qasm3_str)

# QPY binary serialization (preferred for lossless round-trips)
from qiskit import qpy
with open("circuit.qpy", "wb") as f:
    qpy.dump([qc], f)
with open("circuit.qpy", "rb") as f:
    circuits = qpy.load(f)

# Visualization
from qiskit.visualization import plot_histogram, plot_bloch_multivector
plot_histogram(counts)
```

For comprehensive OpenQASM 3 API details (Exporter class, custom gates,
experimental features, OpenQASM 3.1 language syntax, feature support table),
see **[references/openqasm.md](../references/openqasm.md)**.
