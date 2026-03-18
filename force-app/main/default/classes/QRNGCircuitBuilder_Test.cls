@IsTest
private class QRNGCircuitBuilder_Test {
    @IsTest
    static void testBuildStandardCircuit() {
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(3);
        System.assert(
            qasm.contains('OPENQASM 3.0'),
            'Should contain OpenQASM header'
        );
        System.assert(
            qasm.contains('bit[3] meas'),
            'Should declare 3 measurement bits'
        );
        System.assert(
            qasm.contains('rz(pi/2) $0'),
            'Should contain rz gate for qubit 0'
        );
        System.assert(
            qasm.contains('sx $0'),
            'Should contain sx gate for qubit 0'
        );
        System.assert(
            qasm.contains('meas[0] = measure $0'),
            'Should measure qubit 0'
        );
        System.assert(
            qasm.contains('meas[2] = measure $2'),
            'Should measure qubit 2'
        );
    }

    @IsTest
    static void testBuildStandardCircuitWithReadoutErrors() {
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.05,
            1 => 0.01,
            2 => 0.10,
            3 => 0.02,
            4 => 0.03
        };
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(3, readoutErrors);
        // Should pick qubits 1, 3, 4 (lowest error)
        System.assert(
            qasm.contains('measure $1'),
            'Should use qubit 1 (lowest error)'
        );
        System.assert(
            qasm.contains('measure $3'),
            'Should use qubit 3 (second lowest)'
        );
        System.assert(
            qasm.contains('measure $4'),
            'Should use qubit 4 (third lowest)'
        );
    }

    @IsTest
    static void testBuildStandardCircuitSingleQubit() {
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(1);
        System.assert(
            qasm.contains('bit[1] meas'),
            'Should declare 1 measurement bit'
        );
        System.assert(
            qasm.contains('meas[0] = measure $0'),
            'Should measure qubit 0'
        );
    }

    @IsTest
    static void testBuildStandardCircuitMaxQubits() {
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(127);
        System.assert(
            qasm.contains('bit[127] meas'),
            'Should declare 127 measurement bits'
        );
    }

    @IsTest
    static void testBuildStandardCircuitInvalidInput() {
        try {
            QRNGCircuitBuilder.buildStandardCircuit(0);
            System.assert(false, 'Should throw exception for 0 qubits');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('between 1 and 127'),
                'Should describe valid range'
            );
        }

        try {
            QRNGCircuitBuilder.buildStandardCircuit(128);
            System.assert(false, 'Should throw exception for 128 qubits');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('between 1 and 127'),
                'Should describe valid range'
            );
        }
    }

    @IsTest
    static void testBuildBellTestCircuitWithCouplingMap() {
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 14 },
            new List<Integer>{ 1, 2 },
            new List<Integer>{ 3, 4 },
            new List<Integer>{ 5, 6 }
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.05,
            1 => 0.01,
            2 => 0.02,
            3 => 0.03,
            4 => 0.04,
            5 => 0.10,
            6 => 0.10,
            14 => 0.06
        };
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(
            2,
            couplingMap,
            readoutErrors
        );
        System.assert(
            qasm.contains('OPENQASM 3.0'),
            'Should contain OpenQASM header'
        );
        System.assert(
            qasm.contains('bit[4] meas'),
            'Should declare 4 measurement bits for 2 pairs'
        );
        // Should pick (1,2) first (score 0.03), then (3,4) (score 0.07)
        System.assert(
            qasm.contains('cz $1, $2'),
            'Should use coupled pair (1,2) with best readout'
        );
    }

    @IsTest
    static void testBuildBellTestCircuitHas4BasisConfigs() {
        // Need at least 4 pairs to test all 4 CHSH basis configurations
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(4);

        // Ry(theta) = SX . Rz(pi+theta) . SX . Rz(pi)
        //   Bob pi/4  -> Rz(5pi/4) ~ rz(3.926...)
        //   Bob -pi/4 -> Rz(3pi/4) ~ rz(2.356...)
        //   Alice pi/2 -> Rz(3pi/2) ~ rz(4.712...)
        System.assert(
            qasm.contains('rz(3.926'),
            'Should contain Ry(pi/4) middle gate rz(5pi/4) as decimal'
        );
        System.assert(
            qasm.contains('rz(2.356'),
            'Should contain Ry(-pi/4) middle gate rz(3pi/4) as decimal'
        );
        System.assert(
            qasm.contains('rz(4.712'),
            'Should contain Ry(pi/2) middle gate rz(3pi/2) as decimal'
        );
        // All Ry decompositions end with rz(pi)
        System.assert(
            qasm.contains('rz(3.14159'),
            'Should contain rz(pi) from Ry decomposition'
        );
    }

    @IsTest
    static void testBuildBellTestCircuitDefaultOverload() {
        // Backward-compatible call without coupling map
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(2);
        System.assert(
            qasm.contains('cz $0, $1'),
            'Default should use consecutive pairs: (0,1)'
        );
        System.assert(
            qasm.contains('cz $2, $3'),
            'Default should use consecutive pairs: (2,3)'
        );
    }

    @IsTest
    static void testBuildBellTestCircuitInvalidInput() {
        try {
            QRNGCircuitBuilder.buildBellTestCircuit(0);
            System.assert(false, 'Should throw exception');
        } catch (QRNGException e) {
            System.assert(true, 'Exception thrown as expected');
        }
    }

    @IsTest
    static void testBuildBellTestCircuitNullCouplingMap() {
        try {
            QRNGCircuitBuilder.buildBellTestCircuit(1, null, null);
            System.assert(false, 'Should throw for null coupling map');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('Coupling map is required'),
                'Should indicate coupling map needed'
            );
        }
    }

    @IsTest
    static void testBuildBellTestCircuitNotEnoughPairs() {
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 }
        };
        try {
            QRNGCircuitBuilder.buildBellTestCircuit(3, couplingMap, null);
            System.assert(false, 'Should throw for insufficient pairs');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('Not enough connected qubit pairs'),
                'Should indicate insufficient pairs'
            );
        }
    }

    @IsTest
    static void testBuildBellTestCircuitWithGateErrors() {
        // 4 pairs, well-separated, with gate errors
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 10, 11 },
            new List<Integer>{ 20, 21 },
            new List<Integer>{ 30, 31 }
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.02,
            1 => 0.02,
            10 => 0.01,
            11 => 0.01,
            20 => 0.03,
            21 => 0.03,
            30 => 0.02,
            31 => 0.02
        };
        Map<String, Double> gateErrors = new Map<String, Double>{
            '0-1' => 0.05,
            '10-11' => 0.01, // best gate
            '20-21' => 0.08,
            '30-31' => 0.03
        };
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(
            2,
            couplingMap,
            readoutErrors,
            gateErrors
        );
        // Should prefer (10,11) with gate error 0.01 first
        System.assert(
            qasm.contains('cz $10, $11'),
            'Should use pair (10,11) with best gate fidelity'
        );
        System.assert(
            qasm.contains('cz $30, $31'),
            'Should use pair (30,31) as second best'
        );
    }

    @IsTest
    static void testSelectBestQubitsNullErrors() {
        // When readoutErrors is null, should return sequential 0..N-1
        List<Integer> qubits = QRNGCircuitBuilder.selectBestQubits(4, null);
        System.assertEquals(4, qubits.size());
        System.assertEquals(0, qubits[0]);
        System.assertEquals(1, qubits[1]);
        System.assertEquals(2, qubits[2]);
        System.assertEquals(3, qubits[3]);
    }

    @IsTest
    static void testSelectBestQubitsEmptyErrors() {
        // When readoutErrors is empty, should return sequential 0..N-1
        List<Integer> qubits = QRNGCircuitBuilder.selectBestQubits(
            3,
            new Map<Integer, Double>()
        );
        System.assertEquals(3, qubits.size());
        System.assertEquals(0, qubits[0]);
    }

    @IsTest
    static void testSelectBestQubitsSortsByError() {
        Map<Integer, Double> errors = new Map<Integer, Double>{
            10 => 0.05,
            20 => 0.01,
            30 => 0.03,
            40 => 0.02
        };
        List<Integer> qubits = QRNGCircuitBuilder.selectBestQubits(3, errors);
        System.assertEquals(3, qubits.size());
        // Should pick lowest error first: 20(0.01), 40(0.02), 30(0.03)
        System.assertEquals(20, qubits[0], 'Best qubit should be 20');
        System.assertEquals(40, qubits[1], 'Second best should be 40');
        System.assertEquals(30, qubits[2], 'Third best should be 30');
    }

    @IsTest
    static void testSelectBestQubitsPadsWhenInsufficientCalibration() {
        // Only 2 qubits with calibration but need 4
        Map<Integer, Double> errors = new Map<Integer, Double>{
            5 => 0.01,
            10 => 0.02
        };
        List<Integer> qubits = QRNGCircuitBuilder.selectBestQubits(4, errors);
        System.assertEquals(4, qubits.size(), 'Should pad to requested count');
        System.assertEquals(5, qubits[0], 'First should be calibrated qubit 5');
        System.assertEquals(
            10,
            qubits[1],
            'Second should be calibrated qubit 10'
        );
        // Remaining should be padded with sequential indices not already used
        System.assertEquals(0, qubits[2], 'Third should be padded with 0');
        System.assertEquals(1, qubits[3], 'Fourth should be padded with 1');
    }

    @IsTest
    static void testSelectBestPairsNoReadoutErrors() {
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 2, 3 },
            new List<Integer>{ 4, 5 }
        };
        // null readoutErrors — all scores should be 0.0
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            2,
            couplingMap,
            null
        );
        System.assertEquals(2, pairs.size(), 'Should select 2 pairs');
    }

    @IsTest
    static void testSelectBestPairsOverlappingQubits() {
        // Pairs share qubits — greedy selection should skip overlapping
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 }, // best score
            new List<Integer>{ 1, 2 }, // shares qubit 1 — skip
            new List<Integer>{ 3, 4 } // next best non-overlapping
        };
        Map<Integer, Double> errors = new Map<Integer, Double>{
            0 => 0.01,
            1 => 0.01,
            2 => 0.01,
            3 => 0.02,
            4 => 0.02
        };
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            2,
            couplingMap,
            errors
        );
        System.assertEquals(2, pairs.size());
        // First pair should be (0,1) with score 0.02
        System.assertEquals(0, pairs[0].q0);
        System.assertEquals(1, pairs[0].q1);
        // Second pair should be (3,4) — (1,2) is skipped due to overlap
        System.assertEquals(3, pairs[1].q0);
        System.assertEquals(4, pairs[1].q1);
    }

    @IsTest
    static void testSelectBestPairsMissingCalibration() {
        // Some qubits lack calibration — should default to 0.5
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 }, // 0.01 + 0.5 = 0.51
            new List<Integer>{ 2, 3 } // 0.02 + 0.02 = 0.04
        };
        Map<Integer, Double> errors = new Map<Integer, Double>{
            0 => 0.01,
            2 => 0.02,
            3 => 0.02
        };
        // qubit 1 missing — should default to 0.5
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            2,
            couplingMap,
            errors
        );
        System.assertEquals(2, pairs.size());
        // (2,3) should be first since 0.04 < 0.51
        System.assertEquals(2, pairs[0].q0, 'Best pair should be (2,3)');
        System.assertEquals(3, pairs[0].q1);
    }

    @IsTest
    static void testSelectBestPairsWithGateErrors() {
        // Test that gate errors are weighted more heavily (70%) than readout (30%)
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 }, // readout 0.02, gate 0.10
            new List<Integer>{ 10, 11 } // readout 0.05, gate 0.01
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.01,
            1 => 0.01, // readout sum = 0.02 (better)
            10 => 0.025,
            11 => 0.025 // readout sum = 0.05 (worse)
        };
        Map<String, Double> gateErrors = new Map<String, Double>{
            '0-1' => 0.10, // bad gate
            '10-11' => 0.01 // good gate
        };
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            1,
            couplingMap,
            readoutErrors,
            gateErrors
        );
        // (10,11): 0.3*0.05 + 0.7*0.01 = 0.022
        // (0,1):   0.3*0.02 + 0.7*0.10 = 0.076
        // So (10,11) should win despite worse readout
        System.assertEquals(
            10,
            pairs[0].q0,
            'Gate fidelity should dominate scoring'
        );
        System.assertEquals(11, pairs[0].q1);
    }

    @IsTest
    static void testSelectBestPairsCrosstalkFiltering() {
        // Heavy-hex-like topology: 0-1-2-3 chain
        // Pairs (0,1) and (1,2) overlap — already filtered.
        // Pairs (0,1) and (2,3) are neighbors (1 and 2 are adjacent) — crosstalk!
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 1, 2 },
            new List<Integer>{ 2, 3 },
            new List<Integer>{ 10, 11 } // isolated pair
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.01,
            1 => 0.01,
            2 => 0.01,
            3 => 0.01,
            10 => 0.02,
            11 => 0.02
        };
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            2,
            couplingMap,
            readoutErrors
        );
        System.assertEquals(2, pairs.size());
        // (0,1) is best. (2,3) would be next but qubit 2 is neighbor of qubit 1.
        // So second pair should be (10,11) which is isolated.
        System.assertEquals(0, pairs[0].q0, 'First pair should be (0,1)');
        System.assertEquals(
            10,
            pairs[1].q0,
            'Second pair should be isolated (10,11) due to crosstalk'
        );
    }

    @IsTest
    static void testSelectBestPairsCrosstalkFallback() {
        // Only adjacent pairs available — crosstalk filter too aggressive, should fall back
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 1, 2 },
            new List<Integer>{ 2, 3 }
        };
        // Need 2 pairs but all are neighbors — fallback to non-crosstalk mode
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            2,
            couplingMap,
            null
        );
        System.assertEquals(
            2,
            pairs.size(),
            'Should fall back and find 2 pairs'
        );
    }

    @IsTest
    static void testCoupledPairCompareTo() {
        QRNGCircuitBuilder.CoupledPair a = new QRNGCircuitBuilder.CoupledPair(
            0,
            1,
            (Double) 0.01
        );
        QRNGCircuitBuilder.CoupledPair b = new QRNGCircuitBuilder.CoupledPair(
            2,
            3,
            (Double) 0.05
        );
        QRNGCircuitBuilder.CoupledPair c = new QRNGCircuitBuilder.CoupledPair(
            4,
            5,
            (Double) 0.01
        );
        System.assertEquals(-1, a.compareTo(b), 'Lower score should be -1');
        System.assertEquals(1, b.compareTo(a), 'Higher score should be 1');
        System.assertEquals(0, a.compareTo(c), 'Equal score should be 0');
    }

    @IsTest
    static void testBuildCHSHVerificationCircuits() {
        List<String> circuits = QRNGCircuitBuilder.buildCHSHVerificationCircuits(
            5,
            10
        );
        System.assertEquals(
            4,
            circuits.size(),
            'Should return 4 CHSH setting circuits'
        );

        // Each circuit should have the Bell state on physical qubits
        for (String qasm : circuits) {
            System.assert(
                qasm.contains('OPENQASM 3.0'),
                'Should contain OpenQASM header'
            );
            System.assert(
                qasm.contains('rz(pi/2) $5'),
                'Should contain H gate on physical qubit 5'
            );
            System.assert(
                qasm.contains('cz $5, $10'),
                'Should contain cz gate between physical qubits'
            );
        }

        // First circuit E(a,b): a=0 (no Alice rotation), b=pi/8 (Bob Ry(-pi/4))
        // After the cz gate, no operations should appear on qubit 5 (Alice)
        String afterCz0 = circuits[0].substringAfter('cz $5, $10;');
        System.assert(
            !afterCz0.contains('sx $5'),
            'E(a,b) should not have Alice rotation after Bell state'
        );
        // Bob should have Ry(-pi/4): rz(pi + (-pi/4)) = rz(3pi/4) ≈ rz(2.356)
        System.assert(
            circuits[0].contains('rz(2.356'),
            'E(a,b) should have Bob Ry(-pi/4) with rz(3pi/4)'
        );

        // Third circuit E(a',b): has Alice rotation Ry(-pi/2)
        // After cz gate, Alice qubit 5 should have sx (from Ry decomposition)
        String afterCz2 = circuits[2].substringAfter('cz $5, $10;');
        System.assert(
            afterCz2.contains('sx $5'),
            'E(a\',b) should have Alice Ry(-pi/2) rotation'
        );
    }

    @IsTest
    static void testSelectBestPairSingle() {
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 2, 3 }
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.05,
            1 => 0.05,
            2 => 0.01,
            3 => 0.01
        };
        QRNGCircuitBuilder.CoupledPair pair = QRNGCircuitBuilder.selectBestPair(
            couplingMap,
            readoutErrors,
            null
        );
        System.assertEquals(2, pair.q0, 'Should select pair with lowest error');
        System.assertEquals(3, pair.q1);
    }

    @IsTest
    static void testCalculateBitsPerExecution() {
        System.assertEquals(
            8192,
            QRNGCircuitBuilder.calculateBitsPerExecution(8, 1024)
        );
        System.assertEquals(
            127,
            QRNGCircuitBuilder.calculateBitsPerExecution(127, 1)
        );
    }
}
