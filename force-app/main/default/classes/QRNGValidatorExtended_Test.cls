/**
 * Extended edge-case tests for QRNGValidator.
 * Covers boundary conditions, bias detection, and CHSH calculation corner cases
 * that the standard test class does not cover.
 */
@IsTest
private class QRNGValidatorExtended_Test {
    private static String generateTestBits(Integer length) {
        String bits = '';
        for (Integer i = 0; i < length; i++) {
            bits += Math.mod(Math.abs(Crypto.getRandomInteger()), 2) == 0
                ? '0'
                : '1';
        }
        return bits;
    }

    private static String generateBiasedBits(
        Integer length,
        Double biasProbability
    ) {
        String bits = '';
        for (Integer i = 0; i < length; i++) {
            Double r = Math.random();
            bits += (r < biasProbability) ? '1' : '0';
        }
        return bits;
    }

    // ── validate edge cases ──────────────────────────────────────

    @IsTest
    static void testValidateExactly20Bits() {
        String bits = '01010101010101010101';
        Map<String, Object> results = QRNGValidator.validate(bits);
        System.assertNotEquals(null, results.get('passed'));
        System.assertEquals(20, results.get('bitCount'));
    }

    @IsTest
    static void testValidate19BitsInsufficientReturnsError() {
        String bits = '0101010101010101010';
        Map<String, Object> results = QRNGValidator.validate(bits);
        System.assertEquals(false, results.get('passed'));
        System.assert(
            ((String) results.get('error')).contains('Insufficient'),
            'Should have insufficient bits error'
        );
    }

    @IsTest
    static void testValidateEmptyString() {
        Map<String, Object> results = QRNGValidator.validate('');
        System.assertEquals(false, results.get('passed'));
    }

    @IsTest
    static void testValidateReturnsOnesProportion() {
        String bits = generateTestBits(1000);
        Map<String, Object> results = QRNGValidator.validate(bits);
        Double proportion = (Double) results.get('onesProportion');
        System.assert(proportion >= 0.0, 'Proportion should be >= 0');
        System.assert(proportion <= 1.0, 'Proportion should be <= 1');
    }

    // ── frequencyTest edge cases ─────────────────────────────────

    @IsTest
    static void testFrequencyTestAllZeros() {
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += '0';
        }
        System.assertEquals(false, QRNGValidator.frequencyTest(bits));
    }

    @IsTest
    static void testFrequencyTestSlightBias() {
        // 55% ones on 1000 bits is about 3.16 sigma — should fail
        String bits = '';
        for (Integer i = 0; i < 450; i++) {
            bits += '0';
        }
        for (Integer i = 0; i < 550; i++) {
            bits += '1';
        }
        Boolean result = QRNGValidator.frequencyTest(bits);
        System.assertEquals(false, result, '55% bias on 1000 bits should fail');
    }

    @IsTest
    static void testFrequencyTestAlternating() {
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += Math.mod(i, 2) == 0 ? '0' : '1';
        }
        System.assertEquals(true, QRNGValidator.frequencyTest(bits));
    }

    // ── runsTest edge cases ──────────────────────────────────────

    @IsTest
    static void testRunsTestSingleBit() {
        System.assertEquals(false, QRNGValidator.runsTest('1'));
    }

    @IsTest
    static void testRunsTestTwoBits() {
        Boolean result = QRNGValidator.runsTest('01');
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testRunsTestAlternating() {
        // Alternating bits have max runs (499 for n=500) — z-score ≈22,
        // far exceeding threshold of 2.0, so this correctly fails as non-random
        String bits = '';
        for (Integer i = 0; i < 500; i++) {
            bits += Math.mod(i, 2) == 0 ? '0' : '1';
        }
        System.assertEquals(false, QRNGValidator.runsTest(bits));
    }

    @IsTest
    static void testRunsTestAllSameValues() {
        // All same values: frequency pre-test should make runs test return false
        String bits = '';
        for (Integer i = 0; i < 500; i++) {
            bits += '1';
        }
        System.assertEquals(false, QRNGValidator.runsTest(bits));
    }

    // ── chiSquaredTest edge cases ────────────────────────────────

    @IsTest
    static void testChiSquaredTestBlockSize1() {
        String bits = generateTestBits(100);
        Boolean result = QRNGValidator.chiSquaredTest(bits, 1);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testChiSquaredTestLargeBlockSize() {
        // Block size 8 with 1000 bits: 125 blocks, 256 categories
        String bits = generateTestBits(1000);
        Boolean result = QRNGValidator.chiSquaredTest(bits, 8);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testChiSquaredTestRepetitivePattern() {
        // Repeating 0000 pattern — should fail chi-squared
        String bits = '';
        for (Integer i = 0; i < 250; i++) {
            bits += '0000';
        }
        Boolean result = QRNGValidator.chiSquaredTest(bits, 4);
        System.assertEquals(false, result, 'Repetitive pattern should fail');
    }

    // ── calculateCHSH edge cases ─────────────────────────────────

    @IsTest
    static void testCalculateCHSHNull() {
        Double sValue = QRNGValidator.calculateCHSH(null, 4);
        System.assertEquals(0.0, sValue);
    }

    @IsTest
    static void testCalculateCHSHAllOnes() {
        // All-ones: each pair = (-1)*(-1) = +1
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            bitstrings.add('11111111');
        }
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 4);
        // E(a,b)=+1, E(a,b')=+1, E(a',b)=+1, E(a',b')=+1
        // S = |1+1+1-1| = 2
        System.assertEquals(2.0, sValue, 'All-ones should give S=2');
    }

    @IsTest
    static void testCalculateCHSHAntiCorrelated() {
        // All pairs anticorrelated: "01010101"
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            bitstrings.add('01010101');
        }
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 4);
        // Each pair: A=0→+1, B=1→-1, corr = -1
        // E(a,b)=-1, E(a,b')=-1, E(a',b)=-1, E(a',b')=-1
        // S = |-1 + -1 + -1 - (-1)| = |-2| = 2
        System.assertEquals(2.0, sValue, 'Anti-correlated should give S=2');
    }

    @IsTest
    static void testCalculateCHSHShortBitstring() {
        // Bitstring shorter than expected pairs
        List<String> bitstrings = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            bitstrings.add('01'); // Only 1 pair, but numPairs=4
        }
        Double sValue = QRNGValidator.calculateCHSH(bitstrings, 4);
        System.assert(sValue >= 0, 'Should handle short bitstrings gracefully');
    }

    @IsTest
    static void testReverseString() {
        System.assertEquals('dcba', QRNGValidator.reverseString('abcd'));
        System.assertEquals('a', QRNGValidator.reverseString('a'));
        System.assertEquals('', QRNGValidator.reverseString(''));
    }

    // ── validateExtended edge cases ──────────────────────────────

    @IsTest
    static void testValidateExtendedInsufficientBits() {
        Map<String, Object> results = QRNGValidator.validateExtended('0101010');
        System.assertEquals(false, results.get('extendedPassed'));
    }

    @IsTest
    static void testValidateExtendedNull() {
        Map<String, Object> results = QRNGValidator.validateExtended(null);
        System.assertEquals(false, results.get('extendedPassed'));
    }

    @IsTest
    static void testValidateExtendedRandomBits() {
        String bits = generateTestBits(2000);
        Map<String, Object> results = QRNGValidator.validateExtended(bits);
        System.assert(
            results.containsKey('approximateEntropyTest'),
            'Should have approx entropy result'
        );
        System.assert(
            results.containsKey('serialTest'),
            'Should have serial test result'
        );
        System.assert(
            results.containsKey('cumulativeSumsTest'),
            'Should have CUSUM result'
        );
        System.assert(
            results.containsKey('longestRunOfOnesTest'),
            'Should have longest run result'
        );
    }

    // ── approximateEntropyTest ───────────────────────────────────

    @IsTest
    static void testApproximateEntropyShortBits() {
        // < 100 bits: passes by default
        System.assertEquals(
            true,
            QRNGValidator.approximateEntropyTest('0110', 2)
        );
    }

    @IsTest
    static void testApproximateEntropyRandom() {
        String bits = generateTestBits(1000);
        Boolean result = QRNGValidator.approximateEntropyTest(bits, 2);
        System.assertNotEquals(null, result);
    }

    // ── serialTest ───────────────────────────────────────────────

    @IsTest
    static void testSerialTestShortBits() {
        System.assertEquals(true, QRNGValidator.serialTest('0110', 3));
    }

    @IsTest
    static void testSerialTestMEquals1() {
        String bits = generateTestBits(1000);
        Boolean result = QRNGValidator.serialTest(bits, 1);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testSerialTestMEquals0() {
        System.assertEquals(true, QRNGValidator.serialTest('01100110', 0));
    }

    // ── cumulativeSumsTest ───────────────────────────────────────

    @IsTest
    static void testCumulativeSumsShortBits() {
        System.assertEquals(true, QRNGValidator.cumulativeSumsTest('0110'));
    }

    @IsTest
    static void testCumulativeSumsDrifting() {
        // All ones: cumulative sum drifts monotonically
        String bits = '';
        for (Integer i = 0; i < 1000; i++) {
            bits += '1';
        }
        System.assertEquals(
            false,
            QRNGValidator.cumulativeSumsTest(bits),
            'All-ones should fail CUSUM'
        );
    }

    @IsTest
    static void testCumulativeSumsBalanced() {
        // Alternating pattern — minimal drift
        String bits = '';
        for (Integer i = 0; i < 500; i++) {
            bits += '01';
        }
        System.assertEquals(
            true,
            QRNGValidator.cumulativeSumsTest(bits),
            'Alternating should pass CUSUM'
        );
    }

    // ── longestRunOfOnesTest ─────────────────────────────────────

    @IsTest
    static void testLongestRunShortBits() {
        System.assertEquals(true, QRNGValidator.longestRunOfOnesTest('0110'));
    }

    @IsTest
    static void testLongestRunAllOnes() {
        String bits = '';
        for (Integer i = 0; i < 256; i++) {
            bits += '1';
        }
        Boolean result = QRNGValidator.longestRunOfOnesTest(bits);
        System.assertEquals(false, result, 'All-ones should fail longest run');
    }

    // ── mostCommonValueEntropy edge cases ────────────────────────

    @IsTest
    static void testMostCommonValueEntropyEmpty() {
        System.assertEquals(0.0, QRNGValidator.mostCommonValueEntropy(''));
    }

    @IsTest
    static void testMostCommonValueEntropySingleBit() {
        Double entropy = QRNGValidator.mostCommonValueEntropy('1');
        System.assertEquals(0.0, entropy, 'Single bit should have 0 entropy');
    }

    @IsTest
    static void testMostCommonValueEntropyTwoBitsBalanced() {
        Double entropy = QRNGValidator.mostCommonValueEntropy('01');
        System.assertEquals(
            1.0,
            entropy,
            'Balanced 2 bits should have entropy 1.0'
        );
    }

    // ── repetitionCountTest edge cases ───────────────────────────

    @IsTest
    static void testRepetitionCountSingleBit() {
        System.assertEquals(
            false,
            QRNGValidator.repetitionCountTest('1', (Double) 1.0)
        );
    }

    @IsTest
    static void testRepetitionCountZeroEntropy() {
        System.assertEquals(
            false,
            QRNGValidator.repetitionCountTest('0101', (Double) 0.0)
        );
    }

    @IsTest
    static void testRepetitionCountExactlyCutoff() {
        // For H=1.0, cutoff = 1 + ceil(20/1.0) = 21
        // 20 consecutive 1s should pass (run of 20 < cutoff 21)
        String bits = '';
        for (Integer i = 0; i < 20; i++) {
            bits += '1';
        }
        bits += '0' + generateTestBits(979);
        Boolean result = QRNGValidator.repetitionCountTest(bits, (Double) 1.0);
        System.assertEquals(
            true,
            result,
            'Run of 20 should pass (cutoff is 21)'
        );
    }

    // ── adaptiveProportionTest edge cases ────────────────────────

    @IsTest
    static void testAdaptiveProportionShortBits() {
        // < 512 bits: passes by default
        System.assertEquals(true, QRNGValidator.adaptiveProportionTest('0110'));
    }

    @IsTest
    static void testAdaptiveProportionAllZeros() {
        String bits = '';
        for (Integer i = 0; i < 1024; i++) {
            bits += '0';
        }
        System.assertEquals(
            false,
            QRNGValidator.adaptiveProportionTest(bits),
            'All-zeros should fail adaptive proportion'
        );
    }
}
