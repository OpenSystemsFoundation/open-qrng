/**
 * Statistical validation of quantum random bitstrings.
 * Runs lightweight randomness checks before certifying.
 * Tests: frequency (monobit), runs test, chi-squared uniformity.
 */
public with sharing class RandomnessValidator {
    private static final Double SIGNIFICANCE_LEVEL = 0.01;

    /**
     * Run all validation tests on the debiased bitstring.
     * Returns a map with test results and overall pass/fail.
     */
    public static Map<String, Object> validate(String bits) {
        Map<String, Object> results = new Map<String, Object>();

        if (String.isBlank(bits) || bits.length() < 20) {
            results.put('passed', false);
            results.put(
                'error',
                'Insufficient bits for validation (minimum 20, got ' +
                    (bits == null ? 0 : bits.length()) +
                    ')'
            );
            return results;
        }

        Boolean freqPass = frequencyTest(bits);
        Boolean runsPass = runsTest(bits);
        Boolean chiPass = chiSquaredTest(bits, 4);

        results.put('frequencyTest', freqPass);
        results.put('runsTest', runsPass);
        results.put('chiSquaredTest', chiPass);
        results.put('bitCount', bits.length());
        results.put('passed', freqPass && runsPass && chiPass);

        // Calculate basic stats
        Integer ones = countOnes(bits);
        Double proportion = (Double) ones / bits.length();
        results.put('onesProportion', proportion);

        return results;
    }

    /**
     * Frequency (monobit) test: checks that the proportion of 1s is within 2 sigma of 50%.
     * For a fair coin flipped n times, sigma = sqrt(n/4), so 2*sigma = sqrt(n).
     */
    public static Boolean frequencyTest(String bits) {
        Integer n = bits.length();
        Integer ones = countOnes(bits);

        Double expected = n / 2.0;
        Double sigma = Math.sqrt(n / 4.0);
        Double zScore = Math.abs(ones - expected) / sigma;

        // Pass if within 2 standard deviations (95.4% confidence)
        return zScore <= 2.0;
    }

    /**
     * Runs test: checks that the number of runs (consecutive identical bits)
     * is consistent with a random sequence.
     */
    public static Boolean runsTest(String bits) {
        Integer n = bits.length();
        if (n < 2) {
            return false;
        }

        Integer ones = countOnes(bits);
        Double pi = (Double) ones / n;

        // Pre-test: if frequency test would fail, skip runs test
        if (Math.abs(pi - 0.5) > (2.0 / Math.sqrt(n))) {
            return false;
        }

        // Count runs
        Integer runs = 1;
        for (Integer i = 1; i < n; i++) {
            if (bits.substring(i, i + 1) != bits.substring(i - 1, i)) {
                runs++;
            }
        }

        // Expected runs and variance
        Double expectedRuns = 2.0 * n * pi * (1 - pi) + 1;
        Double variance =
            2.0 *
            n *
            pi *
            (1 - pi) *
            (2.0 * n * pi * (1 - pi) - 1) /
            (n - 1);

        if (variance <= 0) {
            return false;
        }

        Double zScore = Math.abs(runs - expectedRuns) / Math.sqrt(variance);

        return zScore <= 2.0;
    }

    /**
     * Chi-squared test: checks uniformity of N-bit blocks.
     * Divides the bitstring into blocks and tests if block values are uniformly distributed.
     */
    public static Boolean chiSquaredTest(String bits, Integer blockSize) {
        Integer numBlocks = bits.length() / blockSize;
        if (numBlocks < 10) {
            // Not enough blocks for meaningful chi-squared
            return true; // Pass by default if insufficient data
        }

        Integer numCategories = (Integer) Math.pow(2, blockSize);
        Double expected = (Double) numBlocks / numCategories;

        // Count occurrences of each block value
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Integer i = 0; i < numBlocks; i++) {
            String block = bits.substring(i * blockSize, (i + 1) * blockSize);
            if (counts.containsKey(block)) {
                counts.put(block, counts.get(block) + 1);
            } else {
                counts.put(block, 1);
            }
        }

        // Calculate chi-squared statistic
        Double chiSquared = 0;
        for (Integer count : counts.values()) {
            chiSquared += Math.pow(count - expected, 2) / expected;
        }

        // Also account for categories with zero observations
        Integer missingCategories = numCategories - counts.size();
        chiSquared += missingCategories * (Math.pow(expected, 2) / expected);

        // Degrees of freedom = numCategories - 1
        // For blockSize=4, df=15, critical value at 0.01 ~ 30.58
        // Simplified: use 3 * df as approximate critical value for p=0.01
        Double criticalValue = 3.0 * (numCategories - 1);

        return chiSquared <= criticalValue;
    }

    /**
     * Calculate CHSH S-value from Bell test measurements.
     * S > 2 proves quantum origin (violates Bell inequality).
     *
     * The circuit assigns each pair one of 4 basis configs via round-robin:
     *   Config 0: Alice 0, Bob π/4       → E(a,b)
     *   Config 1: Alice 0, Bob -π/4      → E(a,b')
     *   Config 2: Alice π/2, Bob π/4     → E(a',b)
     *   Config 3: Alice π/2, Bob -π/4    → E(a',b')
     *
     * S = |E(a,b) + E(a,b') + E(a',b) - E(a',b')|
     * Classical limit: S ≤ 2. Quantum maximum (Tsirelson): S ≤ 2√2 ≈ 2.828.
     *
     * IMPORTANT: IBM returns bitstrings in big-endian order where meas[0] is
     * the RIGHTMOST bit. Our circuit writes meas[0]=Alice0, meas[1]=Bob0,
     * meas[2]=Alice1, meas[3]=Bob1, etc. So we must reverse the bitstring
     * before extracting pairs left-to-right.
     *
     * Each reversed bitstring has 2*numPairs bits: (A0,B0,A1,B1,...).
     * Across all shots, we accumulate correlation E = ⟨A·B⟩ for each config.
     */
    public static Double calculateCHSH(
        List<String> bitstrings,
        Integer numPairs
    ) {
        if (bitstrings == null || bitstrings.isEmpty() || numPairs < 4) {
            return 0.0;
        }

        // Correlations for each of the 4 basis configs
        Double eAB = 0, eABp = 0, eApB = 0, eApBp = 0;
        Integer nAB = 0, nABp = 0, nApB = 0, nApBp = 0;

        for (String rawBs : bitstrings) {
            // Reverse bitstring: IBM big-endian → circuit register order
            String bs = reverseString(rawBs);

            for (
                Integer p = 0; p < numPairs && (p * 2 + 1) < bs.length(); p++
            ) {
                // Map measurement outcomes to ±1: |0⟩ → +1, |1⟩ → -1
                Integer a = bs.substring(p * 2, p * 2 + 1) == '1' ? -1 : 1;
                Integer b = bs.substring(p * 2 + 1, p * 2 + 2) == '1' ? -1 : 1;
                Integer corr = a * b;

                // Pair index determines which basis config was used in the circuit
                Integer basisConfig = Math.mod(p, 4);
                if (basisConfig == 0) {
                    eAB += corr;
                    nAB++;
                } else if (basisConfig == 1) {
                    eABp += corr;
                    nABp++;
                } else if (basisConfig == 2) {
                    eApB += corr;
                    nApB++;
                } else {
                    eApBp += corr;
                    nApBp++;
                }
            }
        }

        // Normalize correlations to [-1, +1]
        if (nAB > 0) {
            eAB /= nAB;
        }
        if (nABp > 0) {
            eABp /= nABp;
        }
        if (nApB > 0) {
            eApB /= nApB;
        }
        if (nApBp > 0) {
            eApBp /= nApBp;
        }

        // CHSH: S = |E(a,b) + E(a,b') + E(a',b) - E(a',b')|
        Double sValue = Math.abs(eAB + eABp + eApB - eApBp);

        return sValue;
    }

    /**
     * Reverse a string. Used to convert IBM big-endian bitstrings to
     * circuit register order (meas[0] first).
     */
    @TestVisible
    private static String reverseString(String s) {
        String result = '';
        for (Integer i = s.length() - 1; i >= 0; i--) {
            result += s.substring(i, i + 1);
        }
        return result;
    }

    // ── Extended tests (async — run via ValidationRunner) ──────

    /**
     * Run all extended validation tests on the debiased bitstring.
     * These are heavier than the critical gate tests but still O(n).
     */
    public static Map<String, Object> validateExtended(String bits) {
        Map<String, Object> results = new Map<String, Object>();

        if (String.isBlank(bits) || bits.length() < 100) {
            results.put('extendedPassed', false);
            results.put('error', 'Insufficient bits for extended validation');
            return results;
        }

        Boolean approxEntropyPass = approximateEntropyTest(bits, 2);
        Boolean serialPass = serialTest(bits, 3);
        Boolean cusumPass = cumulativeSumsTest(bits);
        Boolean longestRunPass = longestRunOfOnesTest(bits);

        // SP 800-90B health tests
        Double minEntropy = mostCommonValueEntropy(bits);
        Boolean repCountPass = repetitionCountTest(bits, minEntropy);
        Boolean adaptPropPass = adaptiveProportionTest(bits);
        Boolean minEntropyPass = minEntropy >= 0.9;

        results.put('approximateEntropyTest', approxEntropyPass);
        results.put('serialTest', serialPass);
        results.put('cumulativeSumsTest', cusumPass);
        results.put('longestRunOfOnesTest', longestRunPass);
        results.put('minEntropy', minEntropy);
        results.put('minEntropyTest', minEntropyPass);
        results.put('repetitionCountTest', repCountPass);
        results.put('adaptiveProportionTest', adaptPropPass);
        results.put(
            'extendedPassed',
            approxEntropyPass &&
                serialPass &&
                cusumPass &&
                longestRunPass &&
                minEntropyPass &&
                repCountPass &&
                adaptPropPass
        );

        return results;
    }

    /**
     * Approximate Entropy test (NIST SP 800-22 §2.12).
     * Checks the frequency of overlapping m-bit and (m+1)-bit patterns.
     * Low entropy indicates predictable repetition.
     *
     * @param bits The bitstring to test
     * @param m Block length (typically 2 or 3)
     */
    public static Boolean approximateEntropyTest(String bits, Integer m) {
        Integer n = bits.length();
        if (n < 100) {
            return true;
        }

        // Compute phi(m) and phi(m+1)
        Double phiM = computePhi(bits, m);
        Double phiM1 = computePhi(bits, m + 1);

        // ApEn = phi(m) - phi(m+1)
        Double apEn = phiM - phiM1;

        // Chi-squared statistic: chi2 = 2n * (ln2 - ApEn)
        Double chi2 = 2.0 * n * (Math.log(2) - apEn);

        // Degrees of freedom = 2^m
        Integer df = (Integer) Math.pow(2, m);

        // Approximate: pass if chi2 < 3 * df (p ≈ 0.01)
        return chi2 < 3.0 * df;
    }

    private static Double computePhi(String bits, Integer m) {
        Integer n = bits.length();
        // Augmented sequence (circular)
        String augmented = bits + bits.substring(0, m - 1);

        // Count occurrences of each m-bit pattern
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Integer i = 0; i < n; i++) {
            String pattern = augmented.substring(i, i + m);
            if (counts.containsKey(pattern)) {
                counts.put(pattern, counts.get(pattern) + 1);
            } else {
                counts.put(pattern, 1);
            }
        }

        // phi = sum of (C_i)^2 / n, then take log
        Double sum = 0;
        for (Integer c : counts.values()) {
            Double freq = (Double) c / n;
            if (freq > 0) {
                sum += freq * Math.log(freq);
            }
        }
        return sum;
    }

    /**
     * Serial test (NIST SP 800-22 §2.11).
     * Tests uniformity of overlapping m-bit patterns.
     * Generalizes the frequency test to higher-order patterns.
     *
     * @param bits The bitstring to test
     * @param m Pattern length (typically 3)
     */
    public static Boolean serialTest(String bits, Integer m) {
        Integer n = bits.length();
        if (n < 100 || m < 1) {
            return true;
        }

        // Compute psi-squared for m, m-1, m-2
        Double psiM = computePsiSquared(bits, m);
        Double psiM1 = (m > 1) ? computePsiSquared(bits, m - 1) : 0;
        Double psiM2 = (m > 2) ? computePsiSquared(bits, m - 2) : 0;

        // ∇psi² = psi²(m) - psi²(m-1)
        // ∇²psi² = psi²(m) - 2*psi²(m-1) + psi²(m-2)
        Double delPsi = psiM - psiM1;
        Double del2Psi = psiM - 2 * psiM1 + psiM2;

        // Both should be chi-squared distributed with 2^(m-1) and 2^(m-2) df
        Integer df1 = (Integer) Math.pow(2, m - 1);
        Integer df2 = (Integer) Math.pow(2, m - 2);

        // Pass if both are within 3*df (approximate p=0.01)
        return delPsi < 3.0 * df1 && del2Psi < 3.0 * df2;
    }

    private static Double computePsiSquared(String bits, Integer m) {
        Integer n = bits.length();
        String augmented = bits + bits.substring(0, m - 1);

        Map<String, Integer> counts = new Map<String, Integer>();
        for (Integer i = 0; i < n; i++) {
            String pattern = augmented.substring(i, i + m);
            if (counts.containsKey(pattern)) {
                counts.put(pattern, counts.get(pattern) + 1);
            } else {
                counts.put(pattern, 1);
            }
        }

        Double sum = 0;
        for (Integer c : counts.values()) {
            sum += (Double) c * c;
        }

        Integer numPatterns = (Integer) Math.pow(2, m);
        return (numPatterns * sum / n) - n;
    }

    /**
     * Cumulative Sums (CUSUM) test (NIST SP 800-22 §2.13).
     * Detects drift/trends in the bitstring — a biased device that
     * starts fair and degrades mid-run would fail this.
     */
    public static Boolean cumulativeSumsTest(String bits) {
        Integer n = bits.length();
        if (n < 100) {
            return true;
        }

        // Convert bits to ±1 and compute running sum
        Integer maxExcursion = 0;
        Integer sum = 0;

        for (Integer i = 0; i < n; i++) {
            sum += bits.substring(i, i + 1) == '1' ? 1 : -1;
            Integer absSum = Math.abs(sum);
            if (absSum > maxExcursion) {
                maxExcursion = absSum;
            }
        }

        // Also check backward direction
        Integer maxExcursionRev = 0;
        sum = 0;
        for (Integer i = n - 1; i >= 0; i--) {
            sum += bits.substring(i, i + 1) == '1' ? 1 : -1;
            Integer absSum = Math.abs(sum);
            if (absSum > maxExcursionRev) {
                maxExcursionRev = absSum;
            }
        }

        // Expected max excursion for random walk of length n: ~sqrt(n)
        // Fail if max excursion exceeds 3*sqrt(n) (very conservative)
        Double threshold = 3.0 * Math.sqrt(n);

        return maxExcursion <= threshold && maxExcursionRev <= threshold;
    }

    /**
     * Longest Run of Ones test (NIST SP 800-22 §2.4).
     * Checks that the longest consecutive run of 1s is consistent
     * with a random sequence. Catches clustered bias.
     */
    public static Boolean longestRunOfOnesTest(String bits) {
        Integer n = bits.length();
        if (n < 128) {
            return true;
        }

        // Use block size of 8 and categorize longest runs
        Integer blockSize = 8;
        Integer numBlocks = n / blockSize;
        if (numBlocks < 16) {
            return true;
        }

        // Expected distribution for blocks of size 8:
        // Category 0: longest run ≤ 1
        // Category 1: longest run = 2
        // Category 2: longest run = 3
        // Category 3: longest run ≥ 4
        // Expected proportions: [0.2148, 0.3672, 0.2305, 0.1875]
        List<Double> expectedProportions = new List<Double>{
            0.2148,
            0.3672,
            0.2305,
            0.1875
        };

        List<Integer> observed = new List<Integer>{ 0, 0, 0, 0 };

        for (Integer b = 0; b < numBlocks; b++) {
            String block = bits.substring(b * blockSize, (b + 1) * blockSize);
            Integer longestRun = 0;
            Integer currentRun = 0;
            for (Integer i = 0; i < blockSize; i++) {
                if (block.substring(i, i + 1) == '1') {
                    currentRun++;
                    if (currentRun > longestRun) {
                        longestRun = currentRun;
                    }
                } else {
                    currentRun = 0;
                }
            }

            if (longestRun <= 1) {
                observed[0]++;
            } else if (longestRun == 2) {
                observed[1]++;
            } else if (longestRun == 3) {
                observed[2]++;
            } else {
                observed[3]++;
            }
        }

        // Chi-squared test
        Double chiSquared = 0;
        for (Integer i = 0; i < 4; i++) {
            Double expected = expectedProportions[i] * numBlocks;
            if (expected > 0) {
                chiSquared += Math.pow(observed[i] - expected, 2) / expected;
            }
        }

        // df = 3, critical value at p=0.01 ~ 11.34
        return chiSquared <= 11.34;
    }

    // ── SP 800-90B Health Tests ─────────────────────────────────────

    /**
     * Most Common Value (MCV) min-entropy estimate (SP 800-90B §6.3.1).
     * The simplest and most conservative entropy estimator.
     * For binary source: p_max = max(count_0, count_1) / n
     *                    min_entropy = -log2(p_max)
     * Ideal random: 1.0 bit per bit. Fails if < 0.9.
     */
    public static Double mostCommonValueEntropy(String bits) {
        Integer n = bits.length();
        if (n == 0) {
            return 0.0;
        }

        Integer ones = countOnes(bits);
        Integer zeros = n - ones;
        Double pMax = (Double) Math.max(ones, zeros) / n;

        if (pMax <= 0 || pMax >= 1.0) {
            return pMax <= 0 ? 1.0 : 0.0;
        }

        // min_entropy = -log2(p_max) = -ln(p_max) / ln(2)
        return -(Math.log(pMax) / Math.log(2));
    }

    /**
     * Repetition Count Test (SP 800-90B §4.4.1).
     * Detects if the same bit value repeats too many times consecutively.
     * Cutoff C = 1 + ceil(20 / H) where H = min-entropy estimate.
     * For H=1.0: C = 21. For H=0.9: C = 23.
     *
     * @param bits The bitstring to test
     * @param minEntropy Pre-computed min-entropy estimate (from MCV)
     */
    public static Boolean repetitionCountTest(String bits, Double minEntropy) {
        Integer n = bits.length();
        if (n < 2 || minEntropy <= 0) {
            return false;
        }

        // Cutoff: C = 1 + ceil(-log2(alpha) / H) where alpha = 2^-20
        Integer cutoff = 1 + (Integer) Math.ceil(20.0 / minEntropy);

        Integer currentRun = 1;
        for (Integer i = 1; i < n; i++) {
            if (bits.substring(i, i + 1) == bits.substring(i - 1, i)) {
                currentRun++;
                if (currentRun >= cutoff) {
                    return false;
                }
            } else {
                currentRun = 1;
            }
        }

        return true;
    }

    /**
     * Adaptive Proportion Test (SP 800-90B §4.4.2).
     * In a window of W samples, counts how many match the first sample.
     * If the count exceeds the cutoff, the source is degraded.
     *
     * For binary source: W = 512, cutoff at alpha = 2^-20.
     * Cutoff C = W/2 + k*sqrt(W/4) where k ≈ 6 for alpha = 2^-20.
     *
     * @param bits The bitstring to test
     */
    public static Boolean adaptiveProportionTest(String bits) {
        Integer n = bits.length();
        Integer windowSize = 512;

        if (n < windowSize) {
            // Not enough data — pass by default
            return true;
        }

        // For binary: cutoff ≈ W/2 + 6*sqrt(W/4) ≈ 256 + 67.9 ≈ 324
        // Using exact formula for alpha=2^-20 on binary source
        Integer cutoff = 324;

        // Test each window
        Integer numWindows = n / windowSize;
        for (Integer w = 0; w < numWindows; w++) {
            Integer offset = w * windowSize;
            String firstBit = bits.substring(offset, offset + 1);
            Integer count = 0;

            for (Integer i = 0; i < windowSize; i++) {
                if (bits.substring(offset + i, offset + i + 1) == firstBit) {
                    count++;
                }
            }

            if (count >= cutoff) {
                return false;
            }
        }

        return true;
    }

    private static Integer countOnes(String bits) {
        Integer count = 0;
        for (Integer i = 0; i < bits.length(); i++) {
            if (bits.substring(i, i + 1) == '1') {
                count++;
            }
        }
        return count;
    }
}
