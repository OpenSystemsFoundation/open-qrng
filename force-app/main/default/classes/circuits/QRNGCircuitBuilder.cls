/**
 * Generates ISA-compliant OpenQASM 3.0 circuits for quantum random number generation.
 * Supports standard QRNG (H+measure) and Bell-test QRNG (entangled pairs).
 *
 * ISA decomposition: H = Rz(π/2) → SX → Rz(π/2)
 * Native gates for IBM Heron r2: rz, sx, x, cz
 * All circuits use physical qubit addressing ($N) — no virtual qubits.
 *
 * Governor limits: 0 callouts (pure computation)
 */
public with sharing class QRNGCircuitBuilder {
    /**
     * Represents a coupled qubit pair with readout quality score.
     */
    public class CoupledPair implements Comparable {
        public Integer q0;
        public Integer q1;
        public Double score; // lower is better (sum of readout errors)

        public CoupledPair(Integer q0, Integer q1, Double score) {
            this.q0 = q0;
            this.q1 = q1;
            this.score = score;
        }

        public Integer compareTo(Object other) {
            CoupledPair o = (CoupledPair) other;
            if (this.score < o.score)
                return -1;
            if (this.score > o.score)
                return 1;
            return 0;
        }
    }

    /**
     * Build a standard QRNG circuit: H + measure on each qubit.
     * Uses physical qubit indices sorted by readout fidelity when available.
     */
    public static String buildStandardCircuit(Integer numQubits) {
        return buildStandardCircuit(numQubits, null);
    }

    /**
     * Build a standard QRNG circuit using the best qubits by readout error.
     * @param numQubits Number of qubits to use
     * @param readoutErrors Map of qubit index → readout error rate (optional)
     */
    public static String buildStandardCircuit(
        Integer numQubits,
        Map<Integer, Double> readoutErrors
    ) {
        if (numQubits == null || numQubits < 1 || numQubits > 127) {
            throw new QRNGException(
                'Number of qubits must be between 1 and 127'
            );
        }

        // Select best qubits by readout fidelity
        List<Integer> qubits = selectBestQubits(numQubits, readoutErrors);

        String qasm = 'OPENQASM 3.0;\n';
        qasm += 'include "stdgates.inc";\n';
        qasm += 'bit[' + numQubits + '] meas;\n';

        // ISA-compliant Hadamard decomposition on each qubit
        for (Integer i = 0; i < numQubits; i++) {
            Integer q = qubits[i];
            qasm += 'rz(pi/2) $' + q + ';\n';
            qasm += 'sx $' + q + ';\n';
            qasm += 'rz(pi/2) $' + q + ';\n';
        }

        // Measure all qubits
        for (Integer i = 0; i < numQubits; i++) {
            qasm += 'meas[' + i + '] = measure $' + qubits[i] + ';\n';
        }

        return qasm;
    }

    /**
     * Build a Bell-test QRNG circuit for CHSH inequality verification.
     * Uses the coupling map to select physically connected qubit pairs.
     * @param numPairs Number of entangled pairs
     * @param couplingMap List of [q0, q1] pairs from the backend
     * @param readoutErrors Map of qubit index → readout error rate
     */
    public static String buildBellTestCircuit(
        Integer numPairs,
        List<List<Integer>> couplingMap,
        Map<Integer, Double> readoutErrors
    ) {
        if (numPairs == null || numPairs < 1 || numPairs > 63) {
            throw new QRNGException(
                'Number of Bell pairs must be between 1 and 63'
            );
        }
        if (couplingMap == null || couplingMap.isEmpty()) {
            throw new QRNGException(
                'Coupling map is required for Bell-test circuits. ' +
                'Could not retrieve backend topology.'
            );
        }

        // Select the best connected pairs by readout quality
        List<CoupledPair> bestPairs = selectBestPairs(
            numPairs,
            couplingMap,
            readoutErrors
        );

        Integer totalQubits = numPairs * 2;
        String qasm = 'OPENQASM 3.0;\n';
        qasm += 'include "stdgates.inc";\n';
        qasm += 'bit[' + totalQubits + '] meas;\n';

        for (Integer i = 0; i < numPairs; i++) {
            Integer qA = bestPairs[i].q0;
            Integer qB = bestPairs[i].q1;

            // Hadamard on qubit A: rz(π/2) → sx → rz(π/2)
            qasm += 'rz(pi/2) $' + qA + ';\n';
            qasm += 'sx $' + qA + ';\n';
            qasm += 'rz(pi/2) $' + qA + ';\n';

            // CNOT decomposed to native Heron r2 gates: H(b) · CZ(a,b) · H(b)
            qasm += 'rz(pi/2) $' + qB + ';\n';
            qasm += 'sx $' + qB + ';\n';
            qasm += 'rz(pi/2) $' + qB + ';\n';
            qasm += 'cz $' + qA + ', $' + qB + ';\n';
            qasm += 'rz(pi/2) $' + qB + ';\n';
            qasm += 'sx $' + qB + ';\n';
            qasm += 'rz(pi/2) $' + qB + ';\n';

            // Basis rotation on qubit B for CHSH measurement
            // Rotate by π/4 for optimal CHSH violation
            qasm += 'rz(pi/4) $' + qB + ';\n';
            qasm += 'sx $' + qB + ';\n';
            qasm += 'rz(pi/2) $' + qB + ';\n';
        }

        // Measure all qubits
        for (Integer i = 0; i < numPairs; i++) {
            Integer measIdx = i * 2;
            qasm +=
                'meas[' +
                measIdx +
                '] = measure $' +
                bestPairs[i].q0 +
                ';\n';
            qasm +=
                'meas[' +
                (measIdx + 1) +
                '] = measure $' +
                bestPairs[i].q1 +
                ';\n';
        }

        return qasm;
    }

    /**
     * Backward-compatible overload for tests without coupling map.
     */
    public static String buildBellTestCircuit(Integer numPairs) {
        // Default coupling: consecutive pairs (0,1), (2,3), ...
        List<List<Integer>> defaultMap = new List<List<Integer>>();
        for (Integer i = 0; i < numPairs * 2; i += 2) {
            defaultMap.add(new List<Integer>{ i, i + 1 });
        }
        return buildBellTestCircuit(numPairs, defaultMap, null);
    }

    /**
     * Select the best N qubits by readout error (lowest error first).
     * Falls back to sequential indices 0..N-1 when no calibration data.
     */
    @TestVisible
    private static List<Integer> selectBestQubits(
        Integer numQubits,
        Map<Integer, Double> readoutErrors
    ) {
        List<Integer> qubits = new List<Integer>();

        if (readoutErrors == null || readoutErrors.isEmpty()) {
            for (Integer i = 0; i < numQubits; i++) {
                qubits.add(i);
            }
            return qubits;
        }

        // Sort qubits by readout error ascending
        List<CoupledPair> scored = new List<CoupledPair>();
        for (Integer q : readoutErrors.keySet()) {
            scored.add(new CoupledPair(q, q, readoutErrors.get(q)));
        }
        scored.sort();

        for (Integer i = 0; i < Math.min(numQubits, scored.size()); i++) {
            qubits.add(scored[i].q0);
        }

        // Pad with sequential indices if not enough calibration data
        Integer nextQ = 0;
        while (qubits.size() < numQubits) {
            if (!qubits.contains(nextQ)) {
                qubits.add(nextQ);
            }
            nextQ++;
        }

        return qubits;
    }

    /**
     * Select the best N connected pairs from the coupling map.
     * Scores each pair by combined readout error; picks non-overlapping pairs.
     */
    @TestVisible
    private static List<CoupledPair> selectBestPairs(
        Integer numPairs,
        List<List<Integer>> couplingMap,
        Map<Integer, Double> readoutErrors
    ) {
        // Score all edges
        List<CoupledPair> allPairs = new List<CoupledPair>();
        for (List<Integer> edge : couplingMap) {
            Double score = 0.0;
            if (readoutErrors != null) {
                Double e0 = readoutErrors.containsKey(edge[0])
                    ? readoutErrors.get(edge[0])
                    : 0.5;
                Double e1 = readoutErrors.containsKey(edge[1])
                    ? readoutErrors.get(edge[1])
                    : 0.5;
                score = e0 + e1;
            }
            allPairs.add(new CoupledPair(edge[0], edge[1], score));
        }
        allPairs.sort();

        // Greedy selection: pick best pairs with no qubit reuse
        List<CoupledPair> selected = new List<CoupledPair>();
        Set<Integer> usedQubits = new Set<Integer>();

        for (CoupledPair pair : allPairs) {
            if (selected.size() >= numPairs) {
                break;
            }
            if (
                !usedQubits.contains(pair.q0) && !usedQubits.contains(pair.q1)
            ) {
                selected.add(pair);
                usedQubits.add(pair.q0);
                usedQubits.add(pair.q1);
            }
        }

        if (selected.size() < numPairs) {
            throw new QRNGException(
                'Not enough connected qubit pairs on this backend. ' +
                    'Need ' +
                    numPairs +
                    ' pairs but only found ' +
                    selected.size() +
                    ' non-overlapping connected pairs.'
            );
        }

        return selected;
    }

    /**
     * Calculate total random bits per execution
     */
    public static Integer calculateBitsPerExecution(
        Integer numQubits,
        Integer shots
    ) {
        return numQubits * shots;
    }
}
