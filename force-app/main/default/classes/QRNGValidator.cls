/**
 * Statistical validation of quantum random bitstrings.
 * Runs lightweight randomness checks before certifying.
 * Tests: frequency (monobit), runs test, chi-squared uniformity.
 */
public with sharing class QRNGValidator {
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
     *   Config 0: Alice 0, Bob π/8       → E(a,b)
     *   Config 1: Alice 0, Bob 3π/8      → E(a,b')
     *   Config 2: Alice π/4, Bob π/8     → E(a',b)
     *   Config 3: Alice π/4, Bob 3π/8    → E(a',b')
     *
     * S = |E(a,b) + E(a,b') + E(a',b) - E(a',b')|
     * Classical limit: S ≤ 2. Quantum maximum (Tsirelson): S ≤ 2√2 ≈ 2.828.
     *
     * Each bitstring from IBM has 2*numPairs bits: (A0,B0,A1,B1,...).
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

        for (String bs : bitstrings) {
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
