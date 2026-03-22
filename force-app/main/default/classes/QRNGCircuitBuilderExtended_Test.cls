/**
 * Extended edge-case tests for QRNGCircuitBuilder.
 * Covers boundary conditions, gate error scoring,
 * and verification circuit generation.
 */
@IsTest
private class QRNGCircuitBuilderExtended_Test {
    @IsTest
    static void testBuildStandardCircuitNullQubits() {
        try {
            QRNGCircuitBuilder.buildStandardCircuit(null);
            System.assert(false, 'Should throw for null qubits');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('between 1 and 127'));
        }
    }

    @IsTest
    static void testBuildStandardCircuitNegative() {
        try {
            QRNGCircuitBuilder.buildStandardCircuit(-1);
            System.assert(false, 'Should throw for negative qubits');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('between 1 and 127'));
        }
    }

    @IsTest
    static void testBuildStandardCircuitIncludesISAHeader() {
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(1);
        System.assert(qasm.contains('OPENQASM 3.0'));
        System.assert(qasm.contains('include "stdgates.inc"'));
    }

    @IsTest
    static void testBuildStandardCircuitISADecomposition() {
        // Each qubit should have rz(pi/2), sx, rz(pi/2) for H gate
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(2);
        Integer rzCount = 0;
        Integer sxCount = 0;
        for (String line : qasm.split('\n')) {
            if (line.startsWith('rz(pi/2)'))
                rzCount++;
            if (line.startsWith('sx '))
                sxCount++;
        }
        // 2 qubits * 2 rz per qubit = 4 rz gates
        System.assertEquals(
            4,
            rzCount,
            'Should have 4 rz(pi/2) gates for 2 qubits'
        );
        // 2 qubits * 1 sx per qubit = 2 sx gates
        System.assertEquals(2, sxCount, 'Should have 2 sx gates for 2 qubits');
    }

    @IsTest
    static void testBuildStandardCircuitReadoutErrorsSorted() {
        // Verify qubits are selected in order of readout error
        Map<Integer, Double> errors = new Map<Integer, Double>{
            50 => 0.001,
            100 => 0.002,
            0 => 0.999
        };
        String qasm = QRNGCircuitBuilder.buildStandardCircuit(2, errors);
        // Should pick qubit 50 (0.001) first, then qubit 100 (0.002)
        System.assert(qasm.contains('$50'), 'Should use best qubit 50');
        System.assert(
            qasm.contains('$100'),
            'Should use second best qubit 100'
        );
        System.assert(!qasm.contains('$0'), 'Should not use worst qubit 0');
    }

    @IsTest
    static void testBuildBellTestCircuitNullPairs() {
        try {
            QRNGCircuitBuilder.buildBellTestCircuit(null);
            System.assert(false, 'Should throw for null pairs');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('between 1 and 63'));
        }
    }

    @IsTest
    static void testBuildBellTestCircuit64Pairs() {
        try {
            QRNGCircuitBuilder.buildBellTestCircuit(64);
            System.assert(false, 'Should throw for 64 pairs');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('between 1 and 63'));
        }
    }

    @IsTest
    static void testBuildBellTestCircuitEmptyCouplingMap() {
        try {
            QRNGCircuitBuilder.buildBellTestCircuit(
                1,
                new List<List<Integer>>(),
                null
            );
            System.assert(false, 'Should throw for empty coupling map');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('Coupling map is required'));
        }
    }

    @IsTest
    static void testBuildBellTestCircuitMaxPairs() {
        // Build with 63 pairs using default overload
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(63);
        System.assert(
            qasm.contains('bit[126] meas'),
            'Should have 126 measurement bits'
        );
    }

    @IsTest
    static void testBuildBellTestCircuitSinglePair() {
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(1);
        System.assert(
            qasm.contains('cz $0, $1'),
            'Should have CZ gate on pair (0,1)'
        );
        System.assert(
            qasm.contains('bit[2] meas'),
            'Should have 2 measurement bits'
        );
    }

    @IsTest
    static void testBuildBellTestCircuitWithGateErrorsReverseKey() {
        // Gate error with reversed key (q1-q0 instead of q0-q1)
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 10, 11 }
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.01,
            1 => 0.01,
            10 => 0.01,
            11 => 0.01
        };
        Map<String, Double> gateErrors = new Map<String, Double>{
            '1-0' => 0.10, // reverse key
            '10-11' => 0.01 // normal key
        };
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            1,
            couplingMap,
            readoutErrors,
            gateErrors
        );
        // (10,11) should be preferred: 0.3*0.02 + 0.7*0.01 = 0.013
        // (0,1): 0.3*0.02 + 0.7*0.10 = 0.076
        System.assertEquals(
            10,
            pairs[0].q0,
            'Should pick pair with lower gate error'
        );
    }

    @IsTest
    static void testBuildBellTestCircuitMissingGateError() {
        // Missing gate error should penalize with 0.5
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 10, 11 }
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.01,
            1 => 0.01,
            10 => 0.01,
            11 => 0.01
        };
        Map<String, Double> gateErrors = new Map<String, Double>{
            '10-11' => 0.01
            // 0-1 is missing — should default to 0.5
        };
        List<QRNGCircuitBuilder.CoupledPair> pairs = QRNGCircuitBuilder.selectBestPairs(
            1,
            couplingMap,
            readoutErrors,
            gateErrors
        );
        // (10,11): 0.3*0.02 + 0.7*0.01 = 0.013
        // (0,1):   0.3*0.02 + 0.7*0.5  = 0.356
        System.assertEquals(
            10,
            pairs[0].q0,
            'Missing gate error should penalize'
        );
    }

    @IsTest
    static void testBuildCHSHVerificationCircuits4Circuits() {
        List<String> circuits = QRNGCircuitBuilder.buildCHSHVerificationCircuits(
            0,
            1
        );
        System.assertEquals(4, circuits.size());
        for (String qasm : circuits) {
            System.assert(qasm.contains('OPENQASM 3.0'));
            System.assert(qasm.contains('cz $0, $1'));
        }
    }

    @IsTest
    static void testBuildCHSHVerificationCircuitsNoMeasurements() {
        // Verification circuits should NOT have measure statements
        List<String> circuits = QRNGCircuitBuilder.buildCHSHVerificationCircuits(
            5,
            10
        );
        for (String qasm : circuits) {
            System.assert(
                !qasm.contains('measure'),
                'Verification circuits should not have measurements (Estimator evaluates ZZ)'
            );
        }
    }

    @IsTest
    static void testSelectBestPairReturnsLowestScore() {
        List<List<Integer>> couplingMap = new List<List<Integer>>{
            new List<Integer>{ 0, 1 },
            new List<Integer>{ 2, 3 },
            new List<Integer>{ 4, 5 }
        };
        Map<Integer, Double> readoutErrors = new Map<Integer, Double>{
            0 => 0.10,
            1 => 0.10,
            2 => 0.001,
            3 => 0.001,
            4 => 0.05,
            5 => 0.05
        };
        Map<String, Double> gateErrors = new Map<String, Double>{
            '0-1' => 0.10,
            '2-3' => 0.001,
            '4-5' => 0.05
        };
        QRNGCircuitBuilder.CoupledPair best = QRNGCircuitBuilder.selectBestPair(
            couplingMap,
            readoutErrors,
            gateErrors
        );
        System.assertEquals(
            2,
            best.q0,
            'Should select pair (2,3) with lowest error'
        );
        System.assertEquals(3, best.q1);
    }

    @IsTest
    static void testCalculateBitsPerExecutionBoundary() {
        System.assertEquals(
            1,
            QRNGCircuitBuilder.calculateBitsPerExecution(1, 1)
        );
        System.assertEquals(
            127 * 8192,
            QRNGCircuitBuilder.calculateBitsPerExecution(127, 8192)
        );
    }

    @IsTest
    static void testCoupledPairCompareToEdgeCases() {
        QRNGCircuitBuilder.CoupledPair zero = new QRNGCircuitBuilder.CoupledPair(
            0,
            1,
            (Double) 0.0
        );
        QRNGCircuitBuilder.CoupledPair alsoZero = new QRNGCircuitBuilder.CoupledPair(
            2,
            3,
            (Double) 0.0
        );
        QRNGCircuitBuilder.CoupledPair small = new QRNGCircuitBuilder.CoupledPair(
            4,
            5,
            (Double) 0.0001
        );

        System.assertEquals(
            0,
            zero.compareTo(alsoZero),
            'Equal scores should return 0'
        );
        System.assertEquals(
            -1,
            zero.compareTo(small),
            'Lower score should return -1'
        );
        System.assertEquals(
            1,
            small.compareTo(zero),
            'Higher score should return 1'
        );
    }
}
