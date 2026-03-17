/**
 * Generates ISA-compliant OpenQASM 3.0 circuits for quantum random number generation.
 * Supports standard QRNG (H+measure) and Bell-test QRNG (entangled pairs).
 *
 * ISA decomposition: H = Rz(π/2) → SX → Rz(π/2)
 * Native gates for IBM Heron r2: rz, sx, x, ecr
 */
public with sharing class QRNGCircuitBuilder {

    /**
     * Build a standard QRNG circuit: H + measure on each qubit
     * Each shot produces numQubits random bits
     */
    public static String buildStandardCircuit(Integer numQubits) {
        // Validate input
        if (numQubits == null || numQubits < 1 || numQubits > 127) {
            throw new QRNGException('Number of qubits must be between 1 and 127');
        }

        String qasm = 'OPENQASM 3.0;\n';
        qasm += 'include "stdgates.inc";\n';
        qasm += 'bit[' + numQubits + '] meas;\n';

        // ISA-compliant Hadamard decomposition on each qubit
        for (Integer i = 0; i < numQubits; i++) {
            qasm += 'rz(pi/2) $' + i + ';\n';
            qasm += 'sx $' + i + ';\n';
            qasm += 'rz(pi/2) $' + i + ';\n';
        }

        // Measure all qubits
        for (Integer i = 0; i < numQubits; i++) {
            qasm += 'meas[' + i + '] = measure $' + i + ';\n';
        }

        return qasm;
    }

    /**
     * Build a Bell-test QRNG circuit for CHSH inequality verification.
     * Creates entangled pairs and measures in complementary bases.
     * Uses 2*numPairs physical qubits.
     */
    public static String buildBellTestCircuit(Integer numPairs) {
        if (numPairs == null || numPairs < 1 || numPairs > 63) {
            throw new QRNGException('Number of Bell pairs must be between 1 and 63');
        }

        Integer totalQubits = numPairs * 2;
        String qasm = 'OPENQASM 3.0;\n';
        qasm += 'include "stdgates.inc";\n';
        qasm += 'bit[' + totalQubits + '] meas;\n';

        for (Integer i = 0; i < numPairs; i++) {
            Integer qA = i * 2;      // First qubit of pair
            Integer qB = i * 2 + 1;  // Second qubit of pair

            // Hadamard on qubit A: rz(π/2) → sx → rz(π/2)
            qasm += 'rz(pi/2) $' + qA + ';\n';
            qasm += 'sx $' + qA + ';\n';
            qasm += 'rz(pi/2) $' + qA + ';\n';

            // Entangle with ECR gate (native 2-qubit gate)
            qasm += 'ecr $' + qA + ', $' + qB + ';\n';

            // Basis rotation on qubit B for CHSH measurement
            // Rotate by π/4 for optimal CHSH violation
            qasm += 'rz(pi/4) $' + qB + ';\n';
            qasm += 'sx $' + qB + ';\n';
            qasm += 'rz(pi/2) $' + qB + ';\n';
        }

        // Measure all qubits
        for (Integer i = 0; i < totalQubits; i++) {
            qasm += 'meas[' + i + '] = measure $' + i + ';\n';
        }

        return qasm;
    }

    /**
     * Calculate total random bits per execution
     */
    public static Integer calculateBitsPerExecution(Integer numQubits, Integer shots) {
        return numQubits * shots;
    }
}
