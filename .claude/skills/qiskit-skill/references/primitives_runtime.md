# Primitives & Runtime Reference — Qiskit v2.3

## Table of Contents

1. [Primitives Overview](#primitives-overview)
2. [QiskitRuntimeService Setup](#qiskitruntimeservice-setup)
3. [SamplerV2](#samplerv2)
4. [EstimatorV2](#estimatorv2)
5. [PUBs and Results](#pubs-and-results)
6. [Options and Error Mitigation](#options-and-error-mitigation)
7. [Sessions and Batches](#sessions-and-batches)
8. [Local Simulation](#local-simulation)
9. [Fractional Gates](#fractional-gates)

---

## Primitives Overview

Qiskit provides two primitive types:

| Primitive       | Purpose                             | Input                                      | Output              |
| --------------- | ----------------------------------- | ------------------------------------------ | ------------------- |
| **SamplerV2**   | Sample circuit output distributions | Circuit + params + shots                   | Counts / bitstrings |
| **EstimatorV2** | Compute expectation values          | Circuit + observables + params + precision | Expectation values  |

Three implementations:

- **Qiskit Runtime** (`qiskit_ibm_runtime`): Cloud-based, runs on IBM QPUs with error mitigation.
- **StatevectorSampler/Estimator** (`qiskit.primitives`): Local ideal simulation.
- **BackendSamplerV2/EstimatorV2** (`qiskit.primitives`): Wrap any backend into primitive interface.

Always import V2 explicitly:

```python
from qiskit_ibm_runtime import SamplerV2 as Sampler
from qiskit_ibm_runtime import EstimatorV2 as Estimator
```

## QiskitRuntimeService Setup

```python
from qiskit_ibm_runtime import QiskitRuntimeService

# First time: save credentials
QiskitRuntimeService.save_account(
    channel="ibm_quantum_platform",  # NOT "ibm_quantum" (sunset)
    token="YOUR_API_TOKEN",
    overwrite=True
)

# Later: load saved account
service = QiskitRuntimeService()

# Select a backend
backend = service.least_busy(operational=True, simulator=False)
backend = service.least_busy(operational=True, simulator=False, min_num_qubits=127)

# With fractional gates (experimental)
backend = service.least_busy(use_fractional_gates=True)

# Filter by tags
service = QiskitRuntimeService(tags=["my-tag"])

# Get specific backend
backend = service.backend("ibm_brisbane")
```

**Channel note:** The `ibm_quantum` channel is sunset. Use `ibm_quantum_platform`.

## SamplerV2

Samples output distributions from quantum circuits. Circuits **must** contain measurements.

```python
from qiskit_ibm_runtime import SamplerV2 as Sampler

sampler = Sampler(mode=backend)

# Simple: single circuit
job = sampler.run([isa_circuit])
result = job.result()
pub_result = result[0]
counts = pub_result.data.meas.get_counts()
bitstrings = pub_result.data.meas.get_bitstrings()

# With parameters
job = sampler.run([(isa_circuit, param_values)])

# With custom shots per PUB
job = sampler.run([(isa_circuit, param_values, 4096)])

# Multiple PUBs
job = sampler.run([
    (circuit1,),
    (circuit2, param_values2),
    (circuit3, param_values3, 8192),
])
```

### Multiple Classical Registers

```python
from qiskit import QuantumCircuit
from qiskit.circuit import QuantumRegister, ClassicalRegister

qr = QuantumRegister(12)
alpha = ClassicalRegister(5, "alpha")
beta = ClassicalRegister(7, "beta")
qc = QuantumCircuit(qr, alpha, beta)
qc.measure(qr[:5], alpha)
qc.measure(qr[5:], beta)

# After transpilation and execution:
pub_result = result[0]
print(pub_result.data.alpha.get_counts())
print(pub_result.data.beta.get_counts())
```

### BitArray Results

Results are returned as `BitArray` objects:

```python
from qiskit.primitives.containers import BitArray

ba = pub_result.data.meas  # BitArray
counts = ba.get_counts()
bitstrings = ba.get_bitstrings()
int_outcomes = ba.get_int_counts()
```

## EstimatorV2

Computes expectation values of observables w.r.t. quantum states.

```python
from qiskit_ibm_runtime import EstimatorV2 as Estimator
from qiskit.quantum_info import SparsePauliOp

estimator = Estimator(mode=backend)

# Single observable
observable = SparsePauliOp("ZZ")
isa_obs = observable.apply_layout(isa_circuit.layout)
job = estimator.run([(isa_circuit, isa_obs)])
result = job.result()
print(result[0].data.evs)      # expectation value(s)
print(result[0].data.stds)     # standard deviations

# Multiple observables (broadcast)
observables = [SparsePauliOp("ZZ"), SparsePauliOp("XX")]
job = estimator.run([(isa_circuit, observables)])

# With parameters and precision
job = estimator.run([(isa_circuit, isa_obs, param_values, 0.01)])

# Multiple PUBs
job = estimator.run([
    (circuit1, obs1),
    (circuit2, obs2, params2),
    (circuit3, obs3, params3, 0.05),
])
```

**Critical:** Always apply layout to observables before passing to Estimator:

```python
isa_observable = observable.apply_layout(isa_circuit.layout)
```

### SparsePauliOp

```python
from qiskit.quantum_info import SparsePauliOp

# Single Pauli string
op = SparsePauliOp("XZIY")

# Weighted sum
op = SparsePauliOp.from_list([("ZZ", 1.0), ("XX", 0.5), ("II", -0.3)])

# Combine
combined = op1 + op2
scaled = 2.5 * op
tensor = op1.tensor(op2)
composed = op1.compose(op2)

# Number of qubits
print(op.num_qubits)
```

## PUBs and Results

### PUB Format

| Primitive | PUB Tuple                                                                                                   |
| --------- | ----------------------------------------------------------------------------------------------------------- |
| Sampler   | `(circuit,)` or `(circuit, params)` or `(circuit, params, shots)`                                           |
| Estimator | `(circuit, observables)` or `(circuit, observables, params)` or `(circuit, observables, params, precision)` |

### Parameter Broadcasting

Parameters are NumPy arrays where rows are parameter sets:

```python
import numpy as np
# 5 different parameter sets, each with 2 parameters
param_values = np.random.uniform(0, 2*np.pi, (5, 2))
job = sampler.run([(isa_circuit, param_values)])
# Returns 5 sets of results
```

Estimator supports broadcasting between observables and parameter values arrays.

### Result Structure

```python
result = job.result()           # PrimitiveResult
pub_result = result[0]          # PubResult for first PUB

# Sampler results
pub_result.data.meas            # BitArray
pub_result.data.meas.get_counts()
pub_result.data.meas.get_bitstrings()
pub_result.metadata

# Estimator results
pub_result.data.evs             # ndarray of expectation values
pub_result.data.stds            # ndarray of standard deviations
pub_result.metadata
```

## Options and Error Mitigation

Set options on primitives after initialization:

```python
# Estimator options
estimator = Estimator(mode=backend)
estimator.options.resilience_level = 0   # 0: none, 1: M3 mitigation, 2: ZNE
estimator.options.resilience.measure_mitigation = True
estimator.options.resilience.zne_mitigation = True    # level 2
estimator.options.resilience.noise_factors = (1, 3, 5)
estimator.options.resilience.extrapolator = "LinearExtrapolator"
estimator.options.default_precision = 0.01

# Sampler options
sampler = Sampler(mode=backend)
sampler.options.default_shots = 4096

# Dynamical decoupling (both)
sampler.options.dynamical_decoupling.enable = True
sampler.options.dynamical_decoupling.sequence_type = "XpXm"  # or "XY4", "XX"

# Or pass as dict at init
estimator = Estimator(mode=backend, options={"resilience_level": 2})
sampler = Sampler(mode=backend, options={"default_shots": 4096})
```

### Resilience Levels (Estimator)

| Level | Techniques                                              |
| ----- | ------------------------------------------------------- |
| 0     | No mitigation                                           |
| 1     | Measurement error mitigation (M3/TREX)                  |
| 2     | Zero Noise Extrapolation (ZNE) + measurement mitigation |

## Sessions and Batches

```python
from qiskit_ibm_runtime import Session, Batch

# Session: iterative algorithms (circuits run back-to-back)
with Session(backend=backend) as session:
    estimator = Estimator(mode=session)
    for params in param_list:
        job = estimator.run([(circuit, obs, params)])
        result = job.result()

# Batch: independent circuits (no ordering guarantee, efficient QPU use)
with Batch(backend=backend) as batch:
    sampler = Sampler(mode=batch)
    job1 = sampler.run([circuit1])
    job2 = sampler.run([circuit2])
```

## Local Simulation

Reference primitives for local statevector simulation (no noise model):

```python
from qiskit.primitives import StatevectorSampler, StatevectorEstimator

sampler = StatevectorSampler()
estimator = StatevectorEstimator()

# Same .run() interface — no transpilation required (but can be beneficial)
job = sampler.run([(qc,)])
result = job.result()
```

For noisy simulation, use Qiskit Aer (`qiskit_aer`):

```python
from qiskit_aer import AerSimulator
from qiskit.primitives import BackendSamplerV2

noisy_backend = AerSimulator.from_backend(real_backend)
sampler = BackendSamplerV2(backend=noisy_backend)
```

### Local Testing Mode (qiskit-ibm-runtime)

```python
from qiskit_ibm_runtime.fake_provider import FakeManilaV2
backend = FakeManilaV2()
sampler = Sampler(mode=backend)  # Runs locally with noise model
```

## Fractional Gates

Experimental feature for backends that support fractional gates:

```python
service = QiskitRuntimeService()
backend = service.least_busy(use_fractional_gates=True)
```

This changes the basis gate set to include fractional rotations, potentially
reducing circuit depth.
