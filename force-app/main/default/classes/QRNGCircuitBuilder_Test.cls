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
    static void testBuildBellTestCircuit() {
        String qasm = QRNGCircuitBuilder.buildBellTestCircuit(2);
        System.assert(
            qasm.contains('OPENQASM 3.0'),
            'Should contain OpenQASM header'
        );
        System.assert(
            qasm.contains('bit[4] meas'),
            'Should declare 4 measurement bits for 2 pairs'
        );
        System.assert(
            qasm.contains('ecr $0, $1'),
            'Should contain ECR gate for first pair'
        );
        System.assert(
            qasm.contains('ecr $2, $3'),
            'Should contain ECR gate for second pair'
        );
        System.assert(
            qasm.contains('rz(pi/4)'),
            'Should contain basis rotation'
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
