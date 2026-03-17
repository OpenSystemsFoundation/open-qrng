# OpenQASM 3 Reference — Qiskit v2.3

## Table of Contents
1. [Overview](#overview)
2. [Qiskit qasm3 Module API](#qiskit-qasm3-module-api)
3. [OpenQASM 3 Language Reference](#openqasm-3-language-reference)
4. [Version 3.1 Changes](#version-31-changes)
5. [Qiskit Feature Support Table](#qiskit-feature-support-table)
6. [Serialization: QASM 3 vs QPY](#serialization-comparison)
7. [Common Patterns and Pitfalls](#common-patterns-and-pitfalls)

---

## Overview

OpenQASM 3 (Open Quantum Assembly Language) is an imperative programming language for
describing quantum circuits and algorithms. The current live specification is **version 3.1**
(https://openqasm.com, source at https://github.com/openqasm/openqasm).

OpenQASM 3 is a major expansion over the earlier QASM 2 (now legacy) with classical control flow, typed variables,
subroutines, explicit timing, gate modifiers, pulse-level definitions, and
input/output parameters. It is the standard intermediate representation for quantum
circuits across the ecosystem.

Qiskit provides `qiskit.qasm3` for converting between OpenQASM 3 and `QuantumCircuit`.
For import, install: `pip install qiskit[qasm3-import]`

**Note:** OpenQASM is not a lossless serialization format for `QuantumCircuit`.
Use `qiskit.qpy` (binary) for round-trip serialization. Use OpenQASM 3 for
interoperability, dynamic circuits, and sharing with non-Qiskit tools.

---

## Qiskit qasm3 Module API

### Exporting (QuantumCircuit → OpenQASM 3)

```python
from qiskit.qasm3 import dump, dumps

# To string
qasm3_str = dumps(qc)

# To file stream
with open("circuit.qasm3", "w") as f:
    dump(qc, f)
```

**Output example:**
```
OPENQASM 3.0;
include "stdgates.inc";
bit[2] meas;
qubit[2] q;
h q[0];
cx q[0], q[1];
barrier q[0], q[1];
meas[0] = measure q[0];
meas[1] = measure q[1];
```

### Exporter Class (Advanced)

For multi-circuit sessions or fine-grained control:

```python
from qiskit.qasm3 import Exporter, ExperimentalFeatures

exporter = Exporter(
    includes=("stdgates.inc",),       # include files to emit
    basis_gates=("U",),               # backend basis gates
    disable_constants=False,          # True → always emit float literals
    allow_aliasing=False,             # True → allow register aliasing
    indent="  ",                      # indentation string
    experimental=ExperimentalFeatures(0),  # experimental feature flags
    annotation_handlers=None,         # namespace → OpenQASM3Serializer mapping
    implicit_defcals=None,            # instruction name → DefcalInstruction
)

qasm_str = exporter.dumps(qc)
exporter.dump(qc, stream)
```

Only `stdgates.inc` is fully understood by the exporter. Other includes require you to
pass the gate names in `basis_gates` to avoid duplicate `gate` definitions.

### Experimental Features

```python
from qiskit.qasm3 import ExperimentalFeatures

# SWITCH_CASE_V1: export switch using old proposal syntax (break-based)
# Default (no flag): uses stabilized syntax (case-block-based)
qasm_str = dumps(qc, experimental=ExperimentalFeatures.SWITCH_CASE_V1)

# Combine flags with |
qasm_str = dumps(qc, experimental=flag1 | flag2)
```

### Importing (OpenQASM 3 → QuantumCircuit)

**Requires:** `pip install qiskit[qasm3-import]` (installs `qiskit_qasm3_import`)

```python
from qiskit.qasm3 import load, loads

# From string
program = """
OPENQASM 3.0;
include "stdgates.inc";
qubit[2] q;
bit[2] c;
h q[0];
cx q[0], q[1];
c = measure q;
"""
qc = loads(program)

# From file
qc = load("circuit.qasm3")

# With physical qubit count (for hardware-addressed programs using $N)
prog = '''
OPENQASM 3.0;
include "stdgates.inc";
h $0;
cx $0, $1;
'''
qc = loads(prog, num_qubits=127)
```

**Parameters:**
- `num_qubits` — physical qubit count for programs using `$N` addressing
- `annotation_handlers` — dict mapping namespaces to `OpenQASM3Serializer` objects
  (new in Qiskit v2.1, requires `qiskit_qasm3_import>=0.6.0`)

### Custom Gate Handling (Import)

```python
from qiskit.qasm3 import CustomGate, loads, STDGATES_INC_GATES

# STDGATES_INC_GATES — tuple of CustomGate for stdgates.inc (used by default)
my_gates = list(STDGATES_INC_GATES) + [
    CustomGate(constructor=MyGateClass, name="my_gate", num_params=1, num_qubits=2),
]
qc = loads(program, custom_gates=my_gates)
```

`CustomGate` fields: `constructor` (callable → Gate), `name` (as in QASM), `num_params`, `num_qubits`.

### Exceptions

- `qasm3.QASM3ExporterError` — failure during export
- `qasm3.QASM3ImporterError` — failure during import (invalid file or unsupported features)

---

## OpenQASM 3 Language Reference

Based on the live specification v3.1 (https://openqasm.com).

### Program Structure

```
OPENQASM 3.0;          // or OPENQASM 3; (minor version optional, defaults to 0)
include "stdgates.inc"; // standard gate library
```

### Qubit Declarations

```
qubit q;               // single qubit
qubit[5] reg;          // 5-qubit register
qubit[127] device;     // full device register

// Physical qubits (hardware-level, skip routing)
h $0;
cx $0, $1;
```

### Classical Types

```
bit b;                 // single classical bit
bit[8] byte_reg;       // bit register
bool flag = true;      // boolean (byte-aligned, unlike bit which is bit-packed)
int[32] counter = 0;   // signed integer
uint[8] idx;           // unsigned integer
float[64] val = 3.14;  // IEEE 754 floating point
angle[32] phi;         // angle type (new in 3.0)
complex[float[64]] z;  // complex number
duration t = 300ns;    // duration
stretch s;             // flexible timing
```

**`bit` vs `bool`**: `bit` is the scalar of `bit[n]` (bit-packed register type, cannot be
array base type). `bool` is byte-aligned and can be used as an array base type.

### Arrays

```
array[int[32], 5] data;                  // 1D array of 5 int[32]
array[float[64], 3, 4] matrix;           // 2D array (3×4)
array[bit[8], 10] registers;             // array of bit registers

// Arrays of size zero ARE allowed; integers and angles must have size > 0
// qubit is NOT a valid array base type (changed in 3.1)
// stretch is NOT a valid array base type
```

### Gate Definitions

```
gate my_bell a, b {
    h a;
    cx a, b;
}

// Parameterized gates
gate my_rx(theta) q {
    rx(theta) q;
}

// Hierarchical — gates can use other defined gates
gate toffoli a, b, c {
    h c;
    cx b, c;
    tdg c;
    cx a, c;
    t c;
    cx b, c;
    tdg c;
    cx a, c;
    t b; t c; h c;
    cx a, b;
    t a; tdg b;
    cx a, b;
}
```

### Gate Modifiers

```
// Controlled gate
ctrl @ x q[0], q[1];               // CX equivalent
ctrl(2) @ x q[0], q[1], q[2];     // CCX (Toffoli)

// Negated control (activate on |0⟩)
negctrl @ x q[0], q[1];

// Inverse (adjoint)
inv @ s q[0];                       // S-dagger

// Power
pow(0.5) @ x q[0];                 // sqrt(X)

// Combined modifiers
ctrl @ inv @ s q[0], q[1];         // controlled S-dagger
```

Gate modifiers are resolved during transpilation — hardware cannot execute them directly.

### Classical Control Flow

```
// if/else
if (c[0]) {
    x q[0];
} else {
    h q[0];
}

// while loop
while (c == "00") {
    h q[0];
    c[0] = measure q[0];
}

// for loop
for uint i in [0:4] {
    rx(float(i) * 0.1) q[0];
}

// switch (stabilized syntax in v3.1)
switch (creg) {
    case 0, 1 {
        x q[0];
    }
    case 2 {
        z q[0];
    }
    default {
        h q[0];
    }
}
```

### Subroutines

```
def my_sub(qubit q, float[64] theta) -> bit {
    rx(theta) q;
    return measure q;
}

// Subroutines with array parameters (readonly or mutable)
def sum_array(readonly array[int[8], #dim = 1] arr) -> int[32] {
    int[32] total = 0;
    for int i in [0:sizeof(arr, 0)-1] {
        total += int[32](arr[i]);
    }
    return total;
}

// Extern — opaque reference to classical computation
extern parity(bit[n]) -> bit;
```

Quantum bits are passed by reference; classical values by value.
A given qubit can only appear once in a subroutine call.

### Input/Output Parameters

```
input float[64] theta;     // provided at run-time
input angle[32] param;
output bit[2] result;

qubit[2] q;
ry(theta) q[0];
cx q[0], q[1];
result = measure q;
```

Enables variational algorithms (VQE, QAOA) — same compiled circuit, different parameters.
If no `output` declaration is provided, all classical variables are returned (legacy default).

### Timing and Duration

```
duration a = 300ns;
delay[a] q[0];              // explicit delay

stretch s;                   // flexible timing placeholder
delay[s] q[0];

box [100ns] {                // boxed expression with duration
    rx(pi) q[0];
    ry(pi/2) q[1];
}

barrier q;                   // scheduling barrier
```

### Directives: Pragmas and Annotations

```
// Pragmas — global directives, processed immediately
pragma ibm.user alice account 12345678
pragma ibm.max_temp qpu 0.4

// Annotations — attached to the next statement
@openqasm.noswap
box {
    rx(pi) q[0];
    cnot q[0], q[3];
}

@openqasm.reversible
gate multiply a, b, x { x = a * b; }
```

In v3.1, namespacing is recommended: `pragma <namespace>.<n>`, `@<namespace>.<n>`.
Annotations support dotted identifier lists (e.g., `@openqasm.crosstalk`).
Pragmas/annotations should be ignored if unsupported — program meaning shouldn't change.

### Explicit No-Operation (v3.1)

```
nop q[0], q[1];    // marks qubits as "used" without any operation
```

Useful inside `box` scopes to include qubits in timing without performing operations.

### Register Aliasing

```
qubit[4] q;
let alias = q[0:1];         // alias for q[0] and q[1]
let pick = q[{0, 3}];       // alias for q[0] and q[3]
let combined = q[0:1] ++ q[3:3];  // concatenation
```

### Built-in Constants and Functions

Constants: `pi`, `euler` (Euler's number), `tau` (2π)

Math functions: `arccos`, `arcsin`, `arctan`, `ceiling`, `cos`, `exp`, `floor`,
`log`, `mod`, `popcount`, `rotl`, `rotr`, `sin`, `sqrt`, `tan`

**Note:** The `pow` function was removed in 3.1 (conflicts with `pow` gate modifier).
Use the `**` operator instead: `float[64] result = x ** y;`

### Measurement

```
bit result = measure q[0];          // single qubit
bit[3] results = measure q;         // entire register
c[0] = measure q[0];               // assign to existing bit
measure q -> c;                     // arrow syntax (legacy compat)
```

### Complete Example (from OpenQASM GitHub)

```
/*
 * Repeat-until-success circuit for Rz(theta),
 * cos(theta-pi)=3/5, from Nielsen and Chuang, Chapter 4.
 */
OPENQASM 3;
include "stdgates.inc";

def segment(qubit[2] anc, qubit psi) -> bit[2] {
  bit[2] b;
  reset anc;
  h anc;
  ccx anc[0], anc[1], psi;
  s psi;
  ccx anc[0], anc[1], psi;
  z psi;
  h anc;
  measure anc -> b;
  return b;
}

qubit input;
qubit[2] ancilla;
bit[2] flags = "11";
bit output;

reset input;
h input;

while(int(flags) != 0) {
  flags = segment ancilla, input;
}
rz(pi - arccos(3 / 5)) input;
h input;
output = measure input;
```

---

## Version 3.1 Changes

Key changes from 3.0 → 3.1 (live spec):

- **Namespaced pragmas/annotations**: Recommended `pragma <ns>.<n>` and `@<ns>.<n>`
  format to avoid collisions between implementations. Annotation keywords now support
  dotted identifier lists.
- **`nop` statement**: Explicit no-operation `nop <qubits>;` to mark qubits as "used"
  by a scope without implying operations.
- **`pow` function removed**: Conflicted with `pow` gate modifier; use `**` operator.
- **`qubit` no longer valid array base type**: `qubit[n]` is not equivalent to an array.
- **Arrays/registers of size zero allowed**: But `int` and `angle` must have size > 0.
- **`sizeof()` clarified**: Does not operate on `bit` or `qubit` registers.
- **`bit` vs `bool` distinction clarified**: `bit` is bit-packed (scalar of `bit[n]`),
  cannot be array base type. `bool` is byte-aligned, can be array base type.
- **Various gate math corrections**: Minor fixes in `sdg`, `rx`, `ry`, `rz`, `crx`, `cry`
  descriptions (gate meanings unchanged).
- **Standard library documented**: Content of `stdgates.inc` explicitly documented.
- **Operator precedence**: Associativity added to the operator-precedence table.

---

## Qiskit Feature Support Table

Summary of Qiskit SDK support for OpenQASM 3 features (as of Qiskit v2.3, July 2025):

| Feature | Parse (import) | Export (dump) | Hardware (Runtime) |
|---|---|---|---|
| Basic gates (stdgates.inc) | Yes | Yes | Yes |
| Custom gate definitions | Yes | Yes | Via transpile |
| Gate modifiers (ctrl@, inv@, pow@, negctrl@) | Eager eval | Yes | Via transpile |
| Classical control flow (if/else, while, for, switch) | Yes | Yes | Yes (dynamic circuits) |
| break/continue | Partial | Partial | No |
| Nested control flow | Yes | Yes | No |
| Classical types (bit, int, uint, float, bool) | Limited | Yes | Partial |
| Input parameters | Yes | Yes | Yes |
| Output parameters | Yes | Yes | Yes |
| Register aliasing (let) | Yes (concat) | Yes | Discouraged |
| Duration/stretch | No | Yes | Limited |
| Subroutines (def) | No | Yes | No |
| Annotations | Yes (v0.6.0+) | Yes (v2.1+) | No |
| Physical qubits ($N) | Yes | Yes (after transpile) | Yes |

**Key limitation:** `qiskit_qasm3_import` v0.6.0 does not support parsing variable
declarations, duration/stretch types, or subroutine definitions. Most Qiskit users
build circuits in Python and never need to parse QASM 3 files directly.

---

## Serialization Comparison

| | QPY (`qiskit.qpy`) | OpenQASM 3 (`qiskit.qasm3`) |
|---|---|---|
| **Format** | Binary | Text |
| **Lossless** | Yes | Mostly |
| **Use case** | Save/load Qiskit circuits | Interop / dynamic circuits / sharing |
| **Control flow** | Yes | Yes |
| **Parameters** | Yes (native) | Yes |
| **Cross-platform** | Qiskit only | Universal |
| **Performance** | Fast | Moderate |

**Recommendation:** Use QPY for saving/loading Qiskit circuits. Use OpenQASM 3 for
sharing with non-Qiskit tools or submitting to hardware compilers.

---

## Common Patterns and Pitfalls

### Round-Trip Export/Import

```python
from qiskit import QuantumCircuit
from qiskit.qasm3 import dumps, loads

qc = QuantumCircuit(2)
qc.h(0)
qc.cx(0, 1)
qc.measure_all()

qasm_str = dumps(qc)
qc_loaded = loads(qasm_str)   # requires qiskit[qasm3-import]
```

### Physical Qubit Programs

```python
from qiskit.qasm3 import loads

prog = """
OPENQASM 3.0;
include "stdgates.inc";
h $0;
cx $0, $1;
bit[2] c;
c[0] = measure $0;
c[1] = measure $1;
"""
qc = loads(prog, num_qubits=127)
```

### Exporting with Custom Basis Gates

```python
from qiskit.qasm3 import Exporter

exporter = Exporter(
    includes=("stdgates.inc", "my_backend.inc"),
    basis_gates=("cx", "rz", "sx", "x", "my_custom_gate"),
)
qasm_str = exporter.dumps(qc)
```

### Error Handling

```python
from qiskit import qasm3

try:
    qc = qasm3.loads(qasm3_str)
except qasm3.QASM3ImporterError as e:
    print(f"Import error: {e}")

try:
    output = qasm3.dumps(qc)
except qasm3.QASM3ExporterError as e:
    print(f"Export error: {e}")
```

### Key Pitfalls

- **Import requires extra package**: `pip install qiskit[qasm3-import]`
- **Not all QASM 3 features parse yet**: Variable declarations, duration/stretch,
  subroutines are export-only as of Qiskit v2.3
- **Gate modifiers are eagerly evaluated on import**: `inv @ s` becomes `Sdg` in the
  resulting `QuantumCircuit` — the modifier structure is not preserved
- **Use `**` not `pow()`**: The `pow` function was removed in OpenQASM 3.1
- **Transpile before hardware execution**: Gate modifiers, custom gates, and non-ISA
  instructions must be resolved via transpilation
- **Use QPY, not QASM, for lossless Qiskit serialization**
