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
     *
     * CHSH requires 4 distinct measurement basis combinations per pair:
     *   Config 0: Alice 0,       Bob π/4      → E(a,b)
     *   Config 1: Alice 0,       Bob -π/4     → E(a,b')
     *   Config 2: Alice π/2,     Bob π/4      → E(a',b)
     *   Config 3: Alice π/2,     Bob -π/4     → E(a',b')
     * S = |E(a,b) + E(a,b') + E(a',b) - E(a',b')| > 2 proves quantum origin.
     *
     * Each pair is assigned one of the 4 configs via round-robin (mod 4).
     * Minimum 4 pairs required for a valid CHSH test (1 per basis config).
     *
     * @param numPairs Number of entangled pairs (minimum 4 for valid CHSH)
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

        return buildBellCircuitFromPairs(numPairs, bestPairs);
    }

    /**
     * Shared circuit builder: generates CHSH OpenQASM from pre-selected pairs.
     * Each pair gets one of 4 basis configs (round-robin) for valid CHSH measurement.
     */
    private static String buildBellCircuitFromPairs(
        Integer numPairs,
        List<CoupledPair> bestPairs
    ) {
        // CHSH basis angles for optimal Bell inequality violation.
        // For |Φ+⟩, correlation E(a,b) = cos(a - b) where a,b are Ry angles.
        // Optimal: a=0, a'=π/2, b=π/4, b'=-π/4 gives S = 2√2.
        //   E(0, π/4) = cos(-π/4) = 1/√2
        //   E(0, -π/4) = cos(π/4) = 1/√2
        //   E(π/2, π/4) = cos(π/4) = 1/√2
        //   E(π/2, -π/4) = cos(3π/4) = -1/√2
        //   S = |1/√2 + 1/√2 + 1/√2 - (-1/√2)| = 4/√2 = 2√2
        //
        // Angles are pre-computed as radians (Double) to emit clean decimal
        // literals in QASM. Symbolic expressions like rz(pi-(pi/4)) can be
        // mishandled by IBM's runtime QASM parser.
        List<Double> aliceAngles = new List<Double>{
            0.0,
            0.0,
            Math.PI / 2,
            Math.PI / 2
        };
        List<Double> bobAngles = new List<Double>{
            Math.PI / 4,
            -(Math.PI / 4),
            Math.PI / 4,
            -(Math.PI / 4)
        };

        Integer totalQubits = numPairs * 2;
        String qasm = 'OPENQASM 3.0;\n';
        qasm += 'include "stdgates.inc";\n';
        qasm += 'bit[' + totalQubits + '] meas;\n';

        for (Integer i = 0; i < numPairs; i++) {
            Integer qA = bestPairs[i].q0;
            Integer qB = bestPairs[i].q1;
            Integer basisConfig = Math.mod(i, 4);

            // --- Create Bell state |Φ+⟩ = (|00⟩ + |11⟩)/√2 ---

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

            // --- Apply CHSH measurement basis rotations ---
            // Ry(θ) decomposed into ISA native gates (rz, sx):
            //   Ry(θ) = Rz(-π/2) · SX · Rz(π - θ) · SX · Rz(-π/2)
            // This rotates the measurement basis by angle θ in the Z-X plane.

            // Alice's basis rotation (0 or π/2)
            Double aliceAngle = aliceAngles[basisConfig];
            if (Math.abs(aliceAngle) > 0.0000000001) {
                qasm += ryDecomposition(qA, aliceAngle);
            }

            // Bob's basis rotation (π/4 or -π/4)
            qasm += ryDecomposition(qB, bobAngles[basisConfig]);
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
     * Decompose Ry(theta) into ISA-native gates for IBM Heron r2.
     *
     * Verified against Qiskit transpiler output (optimization_level=2):
     *   Ry(theta) = SX . Rz(pi + theta) . SX . Rz(pi)
     *
     * All angles are emitted as pre-computed decimal literals.
     */
    private static String ryDecomposition(Integer qubit, Double theta) {
        String q = '$' + qubit;
        Double rzMiddle = Math.PI + theta;
        String qasm = '';
        qasm += 'sx ' + q + ';\n';
        qasm += 'rz(' + rzMiddle + ') ' + q + ';\n';
        qasm += 'sx ' + q + ';\n';
        qasm += 'rz(' + Math.PI + ') ' + q + ';\n';
        return qasm;
    }

    /**
     * Build a Bell-test circuit with full calibration data including gate errors.
     * @param gateErrors Map of "q0-q1" → CZ/ECR gate error rate
     */
    public static String buildBellTestCircuit(
        Integer numPairs,
        List<List<Integer>> couplingMap,
        Map<Integer, Double> readoutErrors,
        Map<String, Double> gateErrors
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

        // Select pairs with gate-fidelity-weighted scoring + crosstalk filtering
        List<CoupledPair> bestPairs = selectBestPairs(
            numPairs,
            couplingMap,
            readoutErrors,
            gateErrors
        );

        // Delegate to the circuit builder with selected pairs
        return buildBellCircuitFromPairs(numPairs, bestPairs);
    }

    /**
     * Backward-compatible overload for tests without coupling map.
     */
    public static String buildBellTestCircuit(Integer numPairs) {
        if (numPairs == null || numPairs < 1 || numPairs > 63) {
            throw new QRNGException(
                'Number of Bell test pairs must be between 1 and 63, got: ' + numPairs
            );
        }
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
     * Scores each pair by combined readout error + CZ gate error (weighted).
     * Applies crosstalk-aware filtering: selected pairs must not share
     * neighbors in the coupling map to avoid simultaneous CZ interference.
     */
    @TestVisible
    private static List<CoupledPair> selectBestPairs(
        Integer numPairs,
        List<List<Integer>> couplingMap,
        Map<Integer, Double> readoutErrors
    ) {
        return selectBestPairs(numPairs, couplingMap, readoutErrors, null);
    }

    /**
     * Select the best N connected pairs with full calibration data.
     * @param gateErrors Map of "q0-q1" → CZ/ECR gate error rate (optional)
     */
    @TestVisible
    private static List<CoupledPair> selectBestPairs(
        Integer numPairs,
        List<List<Integer>> couplingMap,
        Map<Integer, Double> readoutErrors,
        Map<String, Double> gateErrors
    ) {
        // Build adjacency map for crosstalk filtering
        Map<Integer, Set<Integer>> adjacency = new Map<Integer, Set<Integer>>();
        for (List<Integer> edge : couplingMap) {
            if (!adjacency.containsKey(edge[0])) {
                adjacency.put(edge[0], new Set<Integer>());
            }
            if (!adjacency.containsKey(edge[1])) {
                adjacency.put(edge[1], new Set<Integer>());
            }
            adjacency.get(edge[0]).add(edge[1]);
            adjacency.get(edge[1]).add(edge[0]);
        }

        // Score all edges: readout error (30% weight) + gate error (70% weight)
        List<CoupledPair> allPairs = new List<CoupledPair>();
        for (List<Integer> edge : couplingMap) {
            Double readoutScore = 0.0;
            if (readoutErrors != null) {
                Double e0 = readoutErrors.containsKey(edge[0])
                    ? readoutErrors.get(edge[0])
                    : 0.5;
                Double e1 = readoutErrors.containsKey(edge[1])
                    ? readoutErrors.get(edge[1])
                    : 0.5;
                readoutScore = e0 + e1;
            }

            Double gateScore = 0.0;
            if (gateErrors != null) {
                String key = edge[0] + '-' + edge[1];
                String reverseKey = edge[1] + '-' + edge[0];
                if (gateErrors.containsKey(key)) {
                    gateScore = gateErrors.get(key);
                } else if (gateErrors.containsKey(reverseKey)) {
                    gateScore = gateErrors.get(reverseKey);
                } else {
                    gateScore = 0.5; // Unknown gate error — penalize heavily
                }
            }

            // Weighted score: gate fidelity dominates for entanglement quality
            Double score = (gateErrors != null)
                ? 0.3 * readoutScore + 0.7 * gateScore
                : readoutScore;

            allPairs.add(new CoupledPair(edge[0], edge[1], score));
        }
        allPairs.sort();

        // Greedy selection with crosstalk-aware spacing:
        // No qubit reuse AND no selected pair's qubits may be neighbors
        // of another selected pair's qubits (prevents simultaneous CZ crosstalk)
        List<CoupledPair> selected = new List<CoupledPair>();
        Set<Integer> usedQubits = new Set<Integer>();
        Set<Integer> blockedQubits = new Set<Integer>(); // Neighbors of used qubits

        for (CoupledPair pair : allPairs) {
            if (selected.size() >= numPairs) {
                break;
            }
            if (
                !usedQubits.contains(pair.q0) &&
                !usedQubits.contains(pair.q1) &&
                !blockedQubits.contains(pair.q0) &&
                !blockedQubits.contains(pair.q1)
            ) {
                selected.add(pair);
                usedQubits.add(pair.q0);
                usedQubits.add(pair.q1);

                // Block neighbors to prevent crosstalk
                if (adjacency.containsKey(pair.q0)) {
                    blockedQubits.addAll(adjacency.get(pair.q0));
                }
                if (adjacency.containsKey(pair.q1)) {
                    blockedQubits.addAll(adjacency.get(pair.q1));
                }
                // Don't block the pair's own qubits (already in usedQubits)
                blockedQubits.remove(pair.q0);
                blockedQubits.remove(pair.q1);
            }
        }

        // If crosstalk filtering was too aggressive, fall back without it
        if (selected.size() < numPairs) {
            selected = new List<CoupledPair>();
            usedQubits = new Set<Integer>();

            for (CoupledPair pair : allPairs) {
                if (selected.size() >= numPairs) {
                    break;
                }
                if (
                    !usedQubits.contains(pair.q0) &&
                    !usedQubits.contains(pair.q1)
                ) {
                    selected.add(pair);
                    usedQubits.add(pair.q0);
                    usedQubits.add(pair.q1);
                }
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
     * Build 4 CHSH verification circuits for Estimator V2.
     * Each circuit creates |Φ+⟩ then applies Ry(-2θ_a) on Alice and
     * Ry(-2θ_b) on Bob to rotate the measurement basis. The Estimator
     * evaluates ⟨ZZ⟩ on each, giving the correlator E(a,b) directly.
     *
     * Optimal CHSH angles (Tsirelson bound):
     *   a = 0,    a' = π/4
     *   b = π/8,  b' = 3π/8
     *
     * For |Φ+⟩, E(θ_a, θ_b) = cos(2(θ_a − θ_b)).
     * S = E(a,b) − E(a,b') + E(a',b) + E(a',b') = 2√2
     *
     * No measurements — Estimator computes expectation values directly.
     *
     * @param qubitA Physical qubit index for Alice
     * @param qubitB Physical qubit index for Bob
     * @return List of 4 QASM circuits in order: (a,b), (a,b'), (a',b), (a',b')
     */
    public static List<String> buildCHSHVerificationCircuits(
        Integer qubitA,
        Integer qubitB
    ) {
        // Measurement angles
        Double a = 0.0;
        Double aPrime = Math.PI / 4;
        Double b = Math.PI / 8;
        Double bPrime = 3 * Math.PI / 8;

        // 4 CHSH setting combinations
        List<List<Double>> settings = new List<List<Double>>{
            new List<Double>{ a, b }, // E(a,b)
            new List<Double>{ a, bPrime }, // E(a,b')
            new List<Double>{ aPrime, b }, // E(a',b)
            new List<Double>{ aPrime, bPrime } // E(a',b')
        };

        List<String> circuits = new List<String>();
        for (List<Double> setting : settings) {
            circuits.add(
                buildCHSHSettingCircuit(qubitA, qubitB, setting[0], setting[1])
            );
        }
        return circuits;
    }

    /**
     * Build a single CHSH setting circuit: Bell state + measurement rotations.
     * Ry(-2θ) rotates qubit so that Z-basis measurement is equivalent to
     * measuring in the θ-rotated basis.
     */
    private static String buildCHSHSettingCircuit(
        Integer qubitA,
        Integer qubitB,
        Double thetaA,
        Double thetaB
    ) {
        String qA = '$' + qubitA;
        String qB = '$' + qubitB;

        String qasm = 'OPENQASM 3.0;\n';
        qasm += 'include "stdgates.inc";\n';

        // H on Alice: Rz(π/2) · SX · Rz(π/2)
        qasm += 'rz(pi/2) ' + qA + ';\n';
        qasm += 'sx ' + qA + ';\n';
        qasm += 'rz(pi/2) ' + qA + ';\n';

        // CNOT(Alice→Bob) = H(Bob) · CZ(Alice,Bob) · H(Bob)
        qasm += 'rz(pi/2) ' + qB + ';\n';
        qasm += 'sx ' + qB + ';\n';
        qasm += 'rz(pi/2) ' + qB + ';\n';
        qasm += 'cz ' + qA + ', ' + qB + ';\n';
        qasm += 'rz(pi/2) ' + qB + ';\n';
        qasm += 'sx ' + qB + ';\n';
        qasm += 'rz(pi/2) ' + qB + ';\n';

        // Measurement basis rotations: Ry(-2θ)
        // Skip if angle is 0 (no rotation needed)
        if (Math.abs(thetaA) > 0.0000000001) {
            qasm += ryDecomposition(qubitA, -2 * thetaA);
        }
        if (Math.abs(thetaB) > 0.0000000001) {
            qasm += ryDecomposition(qubitB, -2 * thetaB);
        }

        return qasm;
    }

    /**
     * Select the single best qubit pair for CHSH verification.
     * Returns the pair with lowest combined readout + gate error.
     */
    public static CoupledPair selectBestPair(
        List<List<Integer>> couplingMap,
        Map<Integer, Double> readoutErrors,
        Map<String, Double> gateErrors
    ) {
        List<CoupledPair> pairs = selectBestPairs(
            1,
            couplingMap,
            readoutErrors,
            gateErrors
        );
        return pairs[0];
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
