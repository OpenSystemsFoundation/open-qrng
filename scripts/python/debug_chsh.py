"""
Debug CHSH Bell Inequality  - compare Qiskit high-level vs ISA-decomposed circuits.

Tests:
1. Qiskit high-level (h, cx, ry) on StatevectorEstimator -> should give S = 2*sqrt(2)
2. ISA-decomposed (rz, sx, cz) on StatevectorEstimator -> reveals decomposition bugs
3. (Optional) Run on real IBM hardware with both approaches

Usage:
  python scripts/debug_chsh.py              # local simulator only
  python scripts/debug_chsh.py --hardware   # also run on IBM hardware
"""

import math
import sys
import os
import numpy as np
from dotenv import load_dotenv

load_dotenv()

from qiskit import QuantumCircuit
from qiskit.quantum_info import SparsePauliOp, Operator
from qiskit.primitives import StatevectorEstimator
from qiskit.qasm3 import dumps

# -- CHSH angles --
alice_angles = [0, math.pi / 4]                # a, a'
bob_angles   = [math.pi / 8, 3 * math.pi / 8]  # b, b'

settings = [
    ("E(a,b)",   alice_angles[0], bob_angles[0],  +1),
    ("E(a,b')",  alice_angles[0], bob_angles[1],  -1),
    ("E(a',b)",  alice_angles[1], bob_angles[0],  +1),
    ("E(a',b')", alice_angles[1], bob_angles[1],  +1),
]

observable = SparsePauliOp("ZZ")


def build_highlevel_circuits():
    """Qiskit high-level gates (h, cx, ry)  - known correct."""
    circuits = []
    for label, theta_a, theta_b, _ in settings:
        qc = QuantumCircuit(2, name=label)
        qc.h(0)
        qc.cx(0, 1)
        if abs(theta_a) > 1e-10:
            qc.ry(-2 * theta_a, 0)
        if abs(theta_b) > 1e-10:
            qc.ry(-2 * theta_b, 1)
        circuits.append(qc)
    return circuits


def ry_decomposed_old(qc, qubit, theta):
    """
    OLD (WRONG) Ry decomposition - what our Apex code currently uses.
    Formula: Ry(t) = Rz(-pi/2) . SX . Rz(pi - t) . SX . Rz(-pi/2)
    """
    qc.rz(-math.pi / 2, qubit)
    qc.sx(qubit)
    qc.rz(math.pi - theta, qubit)
    qc.sx(qubit)
    qc.rz(-math.pi / 2, qubit)


def ry_decomposed(qc, qubit, theta):
    """
    CORRECTED Ry decomposition from Qiskit transpiler output.
    Formula: Ry(t) = SX . Rz(pi + t) . SX . Rz(pi)
    """
    qc.sx(qubit)
    qc.rz(math.pi + theta, qubit)
    qc.sx(qubit)
    qc.rz(math.pi, qubit)


def build_isa_circuits():
    """ISA-decomposed gates (rz, sx, cz)  - matches our Apex code."""
    circuits = []
    for label, theta_a, theta_b, _ in settings:
        qc = QuantumCircuit(2, name=label)

        # H on qubit 0: Rz(pi/2) . SX . Rz(pi/2)
        qc.rz(math.pi / 2, 0)
        qc.sx(0)
        qc.rz(math.pi / 2, 0)

        # CNOT = H(1) . CZ(0,1) . H(1)
        qc.rz(math.pi / 2, 1)
        qc.sx(1)
        qc.rz(math.pi / 2, 1)
        qc.cz(0, 1)
        qc.rz(math.pi / 2, 1)
        qc.sx(1)
        qc.rz(math.pi / 2, 1)

        # Measurement basis rotations
        if abs(theta_a) > 1e-10:
            ry_decomposed(qc, 0, -2 * theta_a)
        if abs(theta_b) > 1e-10:
            ry_decomposed(qc, 1, -2 * theta_b)

        circuits.append(qc)
    return circuits


def run_chsh(circuits, label):
    """Run 4 CHSH circuits on StatevectorEstimator and compute S."""
    estimator = StatevectorEstimator()
    pubs = [(qc, observable) for qc in circuits]
    result = estimator.run(pubs).result()

    print(f"\n{'=' * 60}")
    print(f"  {label}")
    print(f"{'=' * 60}")

    s_value = 0
    for i, (name, _, _, coeff) in enumerate(settings):
        ev = float(result[i].data.evs)
        contribution = coeff * ev
        s_value += contribution
        sign = "+" if coeff > 0 else "-"
        print(f"  {name:12s} = {ev:+.6f}  (coeff {sign}1, contribution {contribution:+.6f})")

    print(f"\n  S = {s_value:.6f}")
    print(f"  Classical bound: 2.0")
    print(f"  Quantum bound:   {2 * math.sqrt(2):.6f}")
    if abs(s_value) > 2:
        print(f"  PASS: |S| = {abs(s_value):.6f} > 2")
    else:
        print(f"  FAIL: |S| = {abs(s_value):.6f} <= 2")

    return s_value


def find_correct_ry_decomposition():
    """Use Qiskit transpiler to find the correct rz+sx decomposition of Ry."""
    from qiskit.transpiler import generate_preset_pass_manager
    from qiskit.providers.fake_provider import GenericBackendV2

    print(f"\n{'=' * 60}")
    print(f"  Qiskit Transpiler Ry Decomposition (ground truth)")
    print(f"{'=' * 60}")

    # Use a generic 2-qubit backend with rz, sx, cz basis gates
    backend = GenericBackendV2(num_qubits=2, basis_gates=["rz", "sx", "cz"])
    pm = generate_preset_pass_manager(backend=backend, optimization_level=2)

    test_angles = [
        ("Ry(-pi/4)", -math.pi / 4),
        ("Ry(-3pi/4)", -3 * math.pi / 4),
        ("Ry(-pi/2)", -math.pi / 2),
        ("Ry(pi/4)", math.pi / 4),
    ]

    for label, theta in test_angles:
        qc = QuantumCircuit(1)
        qc.ry(theta, 0)
        transpiled = pm.run(qc)
        print(f"\n  {label} (theta = {theta:.4f}):")
        print(f"    {dumps(transpiled)}")

        # Verify equivalence
        ref_op = Operator(qc)
        trans_op = Operator(transpiled)
        print(f"    Equivalent: {ref_op.equiv(trans_op)}")


def verify_ry_decomposition():
    """Compare Ry gate matrix vs our rz+sx decomposition for key angles."""
    print(f"\n{'=' * 60}")
    print(f"  Ry Decomposition Verification (our formula)")
    print(f"{'=' * 60}")

    test_angles = [
        ("Ry(-pi/4) [b=pi/8]", -math.pi / 4),
        ("Ry(-3pi/4) [b'=3pi/8]", -3 * math.pi / 4),
        ("Ry(-pi/2) [a'=pi/4]", -math.pi / 2),
    ]

    for label, theta in test_angles:
        # Reference: Qiskit's Ry gate
        ref = QuantumCircuit(1)
        ref.ry(theta, 0)
        ref_op = Operator(ref)

        # Our decomposition
        decomp = QuantumCircuit(1)
        ry_decomposed(decomp, 0, theta)
        decomp_op = Operator(decomp)

        # Compare (up to global phase)
        equiv = ref_op.equiv(decomp_op)
        diff = np.max(np.abs(ref_op.data - decomp_op.data))

        print(f"\n  {label} (theta = {theta:.4f})")
        print(f"    Reference matrix:\n      {ref_op.data[0]}\n      {ref_op.data[1]}")
        print(f"    Decomposed matrix:\n      {decomp_op.data[0]}\n      {decomp_op.data[1]}")
        print(f"    Equivalent (up to global phase): {equiv}")
        print(f"    Max element difference: {diff:.6f}")
        if not equiv:
            # Check if it's Ry(-theta) instead
            neg = QuantumCircuit(1)
            neg.ry(-theta, 0)
            neg_op = Operator(neg)
            neg_equiv = neg_op.equiv(decomp_op)
            print(f"    Equivalent to Ry({-theta:.4f})? {neg_equiv}")


def main():
    # Step 0: Get correct Ry decomposition from Qiskit
    find_correct_ry_decomposition()

    # Step 1: Verify our Ry decomposition
    verify_ry_decomposition()

    # Step 2: High-level circuits (ground truth)
    hl_circuits = build_highlevel_circuits()
    run_chsh(hl_circuits, "HIGH-LEVEL (h, cx, ry)  - ground truth")

    # Step 3: ISA-decomposed circuits (what Apex builds)
    isa_circuits = build_isa_circuits()
    run_chsh(isa_circuits, "ISA-DECOMPOSED (rz, sx, cz)  - Apex equivalent")

    # Step 4: Print QASM for comparison
    print(f"\n{'=' * 60}")
    print(f"  OpenQASM 3  - ISA circuits")
    print(f"{'=' * 60}")
    for i, qc in enumerate(isa_circuits):
        print(f"\n--- {settings[i][0]} ---")
        print(dumps(qc))

    # Step 5: Optional hardware run
    if "--hardware" in sys.argv:
        run_hardware(isa_circuits)


def run_hardware(circuits):
    """Run on real IBM hardware."""
    try:
        from qiskit_ibm_runtime import QiskitRuntimeService, EstimatorV2 as Estimator

        api_key = os.getenv("IBM_API_KEY")
        if not api_key:
            print("No IBM_API_KEY in .env  - skipping hardware run")
            return

        service = QiskitRuntimeService(
            channel="ibm_quantum",
            token=api_key
        )
        backend = service.least_busy(operational=True, simulator=False)
        print(f"\n{'=' * 60}")
        print(f"  Running on IBM hardware: {backend.name}")
        print(f"{'=' * 60}")

        # Transpile
        from qiskit.transpiler import generate_preset_pass_manager
        pm = generate_preset_pass_manager(backend=backend, optimization_level=2)
        isa_circuits = pm.run(circuits)
        isa_obs = observable.apply_layout(isa_circuits[0].layout)

        estimator = Estimator(mode=backend)
        estimator.options.resilience_level = 2

        pubs = [(qc, isa_obs) for qc in isa_circuits]
        job = estimator.run(pubs)
        print(f"  Job ID: {job.job_id()}")
        print(f"  Waiting for results...")
        result = job.result()

        s_value = 0
        for i, (name, _, _, coeff) in enumerate(settings):
            ev = float(result[i].data.evs)
            s_value += coeff * ev
            print(f"  {name:12s} = {ev:+.6f}")

        print(f"\n  S = {s_value:.6f}")

    except ImportError:
        print("qiskit-ibm-runtime not installed  - pip install qiskit-ibm-runtime")
    except Exception as e:
        print(f"Hardware run failed: {e}")


if __name__ == "__main__":
    main()
