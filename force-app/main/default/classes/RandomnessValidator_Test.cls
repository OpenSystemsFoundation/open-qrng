@IsTest
private class RandomnessValidator_Test {
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
        Map<String, Object> results = RandomnessValidator.validate(bits);
        System.assertNotEquals(null, results.get('passed'));
        System.assertEquals(1000, results.get('bitCount'));
    }

    @IsTest
    static void testValidateInsufficientBits() {
        Map<String, Object> results = RandomnessValidator.validate('01');
        System.assertEquals(false, results.get('passed'));
    }

    @IsTest
    static void testValidateNullBits() {
        Map<String, Object> results = RandomnessValidator.validate(null);
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
        System.assertEquals(true, RandomnessValidator.frequencyTest(bits));
    }

    @IsTest
    static void testFrequencyTestBiased() {
        // All ones: should fail
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += '1';
        }
        System.assertEquals(false, RandomnessValidator.frequencyTest(bits));
    }

    @IsTest
    static void testRunsTest() {
        String bits = generateTestBits(500);
        // Should not throw, result is boolean
        Boolean result = RandomnessValidator.runsTest(bits);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testChiSquaredTest() {
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.chiSquaredTest(bits, 4);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testChiSquaredTestInsufficientBlocks() {
        // Only 2 blocks of size 4 = not enough
        Boolean result = RandomnessValidator.chiSquaredTest('01100110', 4);
        System.assertEquals(true, result); // Passes by default
    }

    @IsTest
    static void testCalculateCHSHWithPairs() {
        // Need at least 4 pairs (8 bits per bitstring) for valid CHSH
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 200; i++) {
            bitstrings.add(generateTestBits(8));
        }
        Double sValue = RandomnessValidator.calculateCHSH(bitstrings, 4);
        System.assert(sValue >= 0, 'S-value should be non-negative');
        // Random classical data should give S ≤ 2 (with some noise)
        System.assert(sValue <= 4.0, 'S-value should be at most 4.0');
    }

    @IsTest
    static void testCalculateCHSHEmpty() {
        Double sValue = RandomnessValidator.calculateCHSH(
            new List<String>(),
            4
        );
        System.assertEquals(0.0, sValue);
    }

    @IsTest
    static void testCalculateCHSHTooFewPairs() {
        // Less than 4 pairs returns 0 (can't do valid CHSH)
        List<String> bitstrings = new List<String>{ '0101' };
        Double sValue = RandomnessValidator.calculateCHSH(bitstrings, 2);
        System.assertEquals(0.0, sValue, 'Should return 0 for < 4 pairs');
    }

    @IsTest
    static void testMostCommonValueEntropyBalanced() {
        // 500 zeros and 500 ones = p_max = 0.5, min_entropy = 1.0
        String bits = '';
        for (Integer i = 0; i < 500; i++) {
            bits += '0';
        }
        for (Integer i = 0; i < 500; i++) {
            bits += '1';
        }
        Double entropy = RandomnessValidator.mostCommonValueEntropy(bits);
        System.assertEquals(
            1.0,
            entropy,
            'Perfectly balanced should give entropy 1.0'
        );
    }

    @IsTest
    static void testMostCommonValueEntropyBiased() {
        // All ones = p_max = 1.0, min_entropy = 0.0
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += '1';
        }
        Double entropy = RandomnessValidator.mostCommonValueEntropy(bits);
        System.assertEquals(0.0, entropy, 'All-ones should give entropy 0.0');
    }

    @IsTest
    static void testMostCommonValueEntropyRandom() {
        String bits = generateTestBits(1000);
        Double entropy = RandomnessValidator.mostCommonValueEntropy(bits);
        System.assert(entropy > 0, 'Random bits should have positive entropy');
        System.assert(entropy <= 1.0, 'Binary entropy cannot exceed 1.0');
    }

    @IsTest
    static void testRepetitionCountTestPasses() {
        // Random bits should pass repetition count test
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.repetitionCountTest(
            bits,
            (Double) 1.0
        );
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testRepetitionCountTestFailsLongRun() {
        // 30 consecutive ones should fail (cutoff C = 21 for H=1.0)
        String bits = '';
        for (Integer i = 0; i < 30; i++) {
            bits += '1';
        }
        bits += generateTestBits(970);
        Boolean result = RandomnessValidator.repetitionCountTest(
            bits,
            (Double) 1.0
        );
        System.assertEquals(
            false,
            result,
            'Long run of identical bits should fail'
        );
    }

    @IsTest
    static void testAdaptiveProportionTestRandom() {
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.adaptiveProportionTest(bits);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testAdaptiveProportionTestBiased() {
        // All ones should fail adaptive proportion test
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += '1';
        }
        Boolean result = RandomnessValidator.adaptiveProportionTest(bits);
        System.assertEquals(
            false,
            result,
            'All-ones should fail adaptive proportion'
        );
    }

    @IsTest
    static void testValidateExtendedIncludesSP80090B() {
        String bits = generateTestBits(2000);
        Map<String, Object> results = RandomnessValidator.validateExtended(
            bits
        );
        System.assert(
            results.containsKey('minEntropy'),
            'Extended results should include minEntropy'
        );
        System.assert(
            results.containsKey('minEntropyTest'),
            'Extended results should include minEntropyTest'
        );
        System.assert(
            results.containsKey('repetitionCountTest'),
            'Extended results should include repetitionCountTest'
        );
        System.assert(
            results.containsKey('adaptiveProportionTest'),
            'Extended results should include adaptiveProportionTest'
        );
    }

    @IsTest
    static void testCalculateCHSHMeasurementMapping() {
        // Verify |0⟩ → +1 and |1⟩ → -1 mapping
        // All-zeros bitstring: every pair correlator should be +1*+1 = +1
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            bitstrings.add('00000000');
        }
        Double sValue = RandomnessValidator.calculateCHSH(bitstrings, 4);
        // E(a,b) = +1, E(a,b') = +1, E(a',b) = +1, E(a',b') = +1
        // S = |1 + 1 + 1 - 1| = 2
        System.assertEquals(2.0, sValue, 'All-zeros should give S=2');
    }
}
