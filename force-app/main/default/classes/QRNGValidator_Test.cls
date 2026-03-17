@IsTest
private class QRNGValidator_Test {

    // Generate a pseudo-random bitstring for testing
    private static String generateTestBits(Integer length) {
        String bits = '';
        for (Integer i = 0; i < length; i++) {
            bits += Math.mod(Math.abs(Crypto.getRandomInteger()), 2) == 0 ? '0' : '1';
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
    static void testCalculateCHSH() {
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            bitstrings.add(generateTestBits(4));
        }
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 2);
        System.assert(sValue >= 0, 'S-value should be non-negative');
    }

    @IsTest
    static void testCalculateCHSHEmpty() {
        Double sValue = QRNGValidator.calculateCHSH(new List<String>(), 1);
        System.assertEquals(0.0, sValue);
    }
}
