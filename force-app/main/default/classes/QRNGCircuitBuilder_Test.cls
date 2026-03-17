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
        System.assert(
            qasm.contains('cz $3, $4'),
            'Should use coupled pair (3,4) as second best'
        );
        System.assert(
            qasm.contains('rz(pi/4)'),
            'Should contain basis rotation'
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
