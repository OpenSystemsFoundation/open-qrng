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
    static void testCalculateCHSHTooFewPairsThrows() {
        // Fewer than 4 pairs cannot cover the 4 CHSH basis configs —
        // misconfigured Bell jobs must fail loudly, not silently score 0.
        List<String> bitstrings = new List<String>{ '0101' };
        try {
            RandomnessValidator.calculateCHSH(bitstrings, 2);
            System.assert(false, 'Should throw for < 4 pairs');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('at least 4 pairs'),
                'Should explain the 4-pair minimum: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testCalculateCHSHWithStatsTooFewPairsThrows() {
        try {
            RandomnessValidator.calculateCHSHWithStats(
                new List<String>{ '0101' },
                3
            );
            System.assert(false, 'Should throw for < 4 pairs');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('at least 4 pairs'));
        }
    }

    @IsTest
    static void testMostCommonValueEntropyBalanced() {
        // 500 zeros and 500 ones: p_hat = 0.5, but the SP 800-90B §6.3.1
        // confidence bound gives p_u = 0.5 + 2.576*sqrt(0.25/1000) ≈ 0.5407,
        // so min_entropy = -log2(0.5407) ≈ 0.887 (not 1.0 at this small n).
        String bits = '0'.repeat(500) + '1'.repeat(500);
        Double entropy = RandomnessValidator.mostCommonValueEntropy(bits);
        System.assert(
            Math.abs(entropy - 0.8870) < 0.001,
            'Balanced 1000 bits should give bounded entropy ~0.887, got ' +
            entropy
        );
    }

    @IsTest
    static void testMostCommonValueEntropyConfidenceBoundLargeN() {
        // Same balanced source at n=10000: bound shrinks with sqrt(n),
        // p_u ≈ 0.5129, entropy ≈ 0.963 — clears the 0.9 threshold.
        String bits = '0'.repeat(5000) + '1'.repeat(5000);
        Double entropy = RandomnessValidator.mostCommonValueEntropy(bits);
        System.assert(
            entropy >= 0.9,
            'Balanced 10000 bits should clear the 0.9 threshold, got ' + entropy
        );
    }

    @IsTest
    static void testMostCommonValueEntropyBoundFailsAt53Percent() {
        // n=1000, p_hat=0.53: p_u = 0.53 + 2.576*sqrt(0.53*0.47/1000)
        // ≈ 0.5707 → min_entropy ≈ 0.809 — must fail the 0.9 threshold.
        String bits = '1'.repeat(530) + '0'.repeat(470);
        Double entropy = RandomnessValidator.mostCommonValueEntropy(bits);
        System.assert(
            entropy < 0.9,
            'p_hat=0.53 at n=1000 must fail the 0.9 threshold, got ' + entropy
        );
        System.assert(
            Math.abs(entropy - 0.8093) < 0.001,
            'Bounded entropy should be ~0.809, got ' + entropy
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

    // ── chi-squared critical values (alpha = 0.01) ──────────────────

    @IsTest
    static void testChiSquaredBoundaryStatisticNowFails() {
        // 160 blocks of size 4 (df=15, expected 10 per category):
        //   '0000' x25 (+15), '0001' x0 (missing), '0010' x5 (-5),
        //   the other 13 values x10 each.
        // chi2 = 15^2/10 + 5^2/10 + 10 (zero-count correction) = 35.0,
        // which sits between the correct critical value (30.578) and the
        // old approximate one (3*df = 45). It must now FAIL.
        List<String> blocks = new List<String>();
        for (Integer i = 0; i < 25; i++) {
            blocks.add('0000');
        }
        for (Integer i = 0; i < 5; i++) {
            blocks.add('0010');
        }
        List<String> uniformValues = new List<String>{
            '0011',
            '0100',
            '0101',
            '0110',
            '0111',
            '1000',
            '1001',
            '1010',
            '1011',
            '1100',
            '1101',
            '1110',
            '1111'
        };
        for (String v : uniformValues) {
            for (Integer i = 0; i < 10; i++) {
                blocks.add(v);
            }
        }
        String bits = String.join(blocks, '');
        System.assertEquals(640, bits.length());
        System.assertEquals(
            false,
            RandomnessValidator.chiSquaredTest(bits, 4),
            'Statistic of 35.0 exceeds the df=15 critical value 30.578'
        );
    }

    @IsTest
    static void testChiSquaredUniformDistributionPasses() {
        // Perfectly uniform: each 4-bit value exactly 10 times → chi2 = 0
        List<String> blocks = new List<String>();
        for (Integer rep = 0; rep < 10; rep++) {
            for (Integer v = 0; v < 16; v++) {
                String block = '';
                Integer x = v;
                for (Integer b = 0; b < 4; b++) {
                    block = String.valueOf(Math.mod(x, 2)) + block;
                    x = x / 2;
                }
                blocks.add(block);
            }
        }
        System.assertEquals(
            true,
            RandomnessValidator.chiSquaredTest(String.join(blocks, ''), 4)
        );
    }

    @IsTest
    static void testWilsonHilfertyFallbackApproximation() {
        // Fallback for a df not in the lookup: df=15 approximation should
        // land close to the exact 30.578
        Double approx = RandomnessValidator.wilsonHilfertyCritical001(15);
        System.assert(
            Math.abs(approx - 30.578) < 1.0,
            'Wilson-Hilferty should approximate the exact value, got ' + approx
        );
    }

    // ── z-threshold at alpha = 0.01 (2.576, was 2.0) ────────────────

    @IsTest
    static void testFrequencyTestZBetweenOldAndNewThresholdPasses() {
        // 5110 ones / 10000 bits: z = 110/50 = 2.2 — failed at the old
        // 2.0 gate, passes at 2.576 (alpha = 0.01)
        String bits = '1'.repeat(5110) + '0'.repeat(4890);
        System.assertEquals(
            true,
            RandomnessValidator.frequencyTest(bits),
            'z=2.2 should pass the alpha=0.01 gate'
        );
    }

    @IsTest
    static void testFrequencyTestZAboveNewThresholdFails() {
        // 5150 ones / 10000 bits: z = 150/50 = 3.0 > 2.576 — still fails
        String bits = '1'.repeat(5150) + '0'.repeat(4850);
        System.assertEquals(
            false,
            RandomnessValidator.frequencyTest(bits),
            'z=3.0 should fail the alpha=0.01 gate'
        );
    }

    @IsTest
    static void testRunsTestZBetweenOldAndNewThresholdPasses() {
        // 1000 bits, 500 ones, 466 runs: expected runs = 501,
        // sd ≈ 15.80 → z ≈ 2.215 — failed at 2.0, passes at 2.576
        String bits = '1100'.repeat(232) + '1'.repeat(36) + '0'.repeat(36);
        System.assertEquals(
            true,
            RandomnessValidator.runsTest(bits),
            'z=2.215 should pass the alpha=0.01 gate'
        );
    }

    @IsTest
    static void testRunsTestZAboveNewThresholdFails() {
        // 1000 bits, 500 ones, 460 runs: z ≈ 2.594 > 2.576 — still fails
        String bits = '1100'.repeat(229) + '1'.repeat(42) + '0'.repeat(42);
        System.assertEquals(
            false,
            RandomnessValidator.runsTest(bits),
            'z=2.594 should fail the alpha=0.01 gate'
        );
    }

    // ── CHSH statistical margin ─────────────────────────────────────

    /**
     * Build sampler-style shots where each shot carries one pair per
     * CHSH basis config. plusCounts[c] = shots whose config-c correlator
     * is +1 (bits '00'); the rest are -1 (bits '01'). The logical
     * (A0,B0,A1,B1,...) string is reversed to IBM big-endian raw order.
     */
    private static List<String> buildChshShots(
        Integer numShots,
        List<Integer> plusCounts
    ) {
        List<String> shots = new List<String>();
        for (Integer i = 0; i < numShots; i++) {
            List<String> pairBits = new List<String>();
            for (Integer c = 0; c < 4; c++) {
                pairBits.add(i < plusCounts[c] ? '00' : '01');
            }
            shots.add(
                RandomnessValidator.reverseString(String.join(pairBits, ''))
            );
        }
        return shots;
    }

    @IsTest
    static void testCalculateCHSHWithStatsSmallSampleFails() {
        // 40 shots per correlator: E = [0.7, 0.7, 0.7, 0.05] → S = 2.05,
        // sigma_S ≈ 0.2514 → margin 0.05 << 2*sigma (0.503): must FAIL —
        // S barely above 2 with tiny n is statistically meaningless.
        List<String> shots = buildChshShots(
            40,
            new List<Integer>{ 34, 34, 34, 21 }
        );
        Map<String, Object> stats = RandomnessValidator.calculateCHSHWithStats(
            shots,
            4
        );
        Double sValue = (Double) stats.get('sValue');
        Double sigmaS = (Double) stats.get('sigmaS');
        Double margin = (Double) stats.get('margin');
        System.assert(
            Math.abs(sValue - 2.05) < 0.0001,
            'S should be 2.05, got ' + sValue
        );
        System.assert(
            Math.abs(sigmaS - 0.2514) < 0.001,
            'sigma_S should be ~0.2514, got ' + sigmaS
        );
        System.assert(Math.abs(margin - 0.05) < 0.0001);
        System.assertEquals(
            false,
            (Boolean) stats.get('bellTestPassed'),
            'S=2.05 with 40 samples/correlator lacks significance'
        );
        System.assertEquals(
            sValue,
            (Double) stats.get('chshSValue'),
            'chshSValue key should mirror sValue for certificate JSON'
        );
    }

    @IsTest
    static void testCalculateCHSHWithStatsLargeSamplePasses() {
        // 1024 shots per correlator: E = [0.6875, 0.6875, 0.6875, -0.6875]
        // → S = 2.75, sigma_S ≈ 0.0454 → margin 0.75 > 2*sigma (0.091): PASS
        List<String> shots = buildChshShots(
            1024,
            new List<Integer>{ 864, 864, 864, 160 }
        );
        Map<String, Object> stats = RandomnessValidator.calculateCHSHWithStats(
            shots,
            4
        );
        Double sValue = (Double) stats.get('sValue');
        Double sigmaS = (Double) stats.get('sigmaS');
        System.assert(
            Math.abs(sValue - 2.75) < 0.0001,
            'S should be 2.75, got ' + sValue
        );
        System.assert(
            Math.abs(sigmaS - 0.0454) < 0.001,
            'sigma_S should be ~0.0454, got ' + sigmaS
        );
        System.assertEquals(
            true,
            (Boolean) stats.get('bellTestPassed'),
            'S=2.75 at 1024 samples/correlator is significant'
        );
        Map<String, Object> correlators = (Map<String, Object>) stats.get(
            'correlators'
        );
        System.assertEquals(1024, (Integer) correlators.get('nAB'));
        System.assert(
            Math.abs((Double) correlators.get('eApBp') - (-0.6875)) < 0.0001
        );
    }

    @IsTest
    static void testCalculateCHSHWithStatsEmptyInput() {
        Map<String, Object> stats = RandomnessValidator.calculateCHSHWithStats(
            new List<String>(),
            4
        );
        System.assertEquals(0.0, (Double) stats.get('sValue'));
        System.assertEquals(null, stats.get('sigmaS'));
        System.assertEquals(false, (Boolean) stats.get('bellTestPassed'));
    }
}
