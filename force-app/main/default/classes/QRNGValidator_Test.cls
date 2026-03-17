@IsTest
private class QRNGValidator_Test {
    // Generate a pseudo-random bitstring for testing
    private static String generateTestBits(Integer length) {
        String bits = '';
        for (Integer i = 0; i < length; i++) {
            bits += Math.mod(Math.abs(Crypto.getRandomInteger()), 2) == 0
                ? '0'
                : '1';
        }
        return bits;
    }

    @IsTest
    static void testValidateGoodBits() {
        String bits = generateTestBits(1000);
        Map<String, Object> results = QRNGValidator.validate(bits);
        System.assertNotEquals(null, results.get('passed'));
        System.assertEquals(1000, results.get('bitCount'));
    }

    @IsTest
    static void testValidateInsufficientBits() {
        Map<String, Object> results = QRNGValidator.validate('01');
        System.assertEquals(false, results.get('passed'));
    }

    @IsTest
    static void testValidateNullBits() {
        Map<String, Object> results = QRNGValidator.validate(null);
        System.assertEquals(false, results.get('passed'));
    }

    @IsTest
    static void testFrequencyTestBalanced() {
        // Perfectly balanced: should pass
        String bits = '';
        for (Integer i = 0; i < 500; i++) {
            bits += '0';
        }
        for (Integer i = 0; i < 500; i++) {
            bits += '1';
        }
        System.assertEquals(true, QRNGValidator.frequencyTest(bits));
    }

    @IsTest
    static void testFrequencyTestBiased() {
        // All ones: should fail
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += '1';
        }
        System.assertEquals(false, QRNGValidator.frequencyTest(bits));
    }

    @IsTest
    static void testRunsTest() {
        String bits = generateTestBits(500);
        // Should not throw, result is boolean
        Boolean result = QRNGValidator.runsTest(bits);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testChiSquaredTest() {
        String bits = generateTestBits(1000);
        Boolean result = QRNGValidator.chiSquaredTest(bits, 4);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testChiSquaredTestInsufficientBlocks() {
        // Only 2 blocks of size 4 = not enough
        Boolean result = QRNGValidator.chiSquaredTest('01100110', 4);
        System.assertEquals(true, result); // Passes by default
    }

    @IsTest
    static void testCalculateCHSHWithPairs() {
        // Need at least 4 pairs (8 bits per bitstring) for valid CHSH
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 200; i++) {
            bitstrings.add(generateTestBits(8));
        }
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 4);
        System.assert(sValue >= 0, 'S-value should be non-negative');
        // Random classical data should give S ≤ 2 (with some noise)
        System.assert(sValue <= 4.0, 'S-value should be at most 4.0');
    }

    @IsTest
    static void testCalculateCHSHEmpty() {
        Double sValue = QRNGValidator.calculateCHSH(new List<String>(), 4);
        System.assertEquals(0.0, sValue);
    }

    @IsTest
    static void testCalculateCHSHTooFewPairs() {
        // Less than 4 pairs returns 0 (can't do valid CHSH)
        List<String> bitstrings = new List<String>{ '0101' };
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 2);
        System.assertEquals(0.0, sValue, 'Should return 0 for < 4 pairs');
    }

    @IsTest
    static void testCalculateCHSHMeasurementMapping() {
        // Verify |0⟩ → +1 and |1⟩ → -1 mapping
        // All-zeros bitstring: every pair correlator should be +1*+1 = +1
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            bitstrings.add('00000000');
        }
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 4);
        // E(a,b) = +1, E(a,b') = +1, E(a',b) = +1, E(a',b') = +1
        // S = |1 + 1 + 1 - 1| = 2
        System.assertEquals(2.0, sValue, 'All-zeros should give S=2');
    }
}
