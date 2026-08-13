/**
 * Parses IBM Sampler results and applies von Neumann debiasing.
 * Extracts raw bitstrings, concatenates into bit pool, removes hardware bias.
 */
public with sharing class ResultParser {
    private static final Map<String, String> HEX_TO_BIN = new Map<String, String>{
        '0' => '0000',
        '1' => '0001',
        '2' => '0010',
        '3' => '0011',
        '4' => '0100',
        '5' => '0101',
        '6' => '0110',
        '7' => '0111',
        '8' => '1000',
        '9' => '1001',
        'a' => '1010',
        'b' => '1011',
        'c' => '1100',
        'd' => '1101',
        'e' => '1110',
        'f' => '1111'
    };

    private static final Map<String, String> BIN_TO_HEX = new Map<String, String>{
        '0000' => '0',
        '0001' => '1',
        '0010' => '2',
        '0011' => '3',
        '0100' => '4',
        '0101' => '5',
        '0110' => '6',
        '0111' => '7',
        '1000' => '8',
        '1001' => '9',
        '1010' => 'a',
        '1011' => 'b',
        '1100' => 'c',
        '1101' => 'd',
        '1110' => 'e',
        '1111' => 'f'
    };

    /**
     * Parse IBM Sampler response JSON and extract bitstring samples.
     * Handles both binary ("0110") and hex ("0xb6") sample formats.
     * Expected format: {"results":[{"data":{"meas":{"samples":["0xb6","0x17",...]}}}]}
     */
    public static List<String> parseSamplerResults(
        String jsonResponse,
        Integer numQubits
    ) {
        List<String> bitstrings = new List<String>();

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            jsonResponse
        );
        List<Object> results = (List<Object>) response.get('results');

        if (results == null || results.isEmpty()) {
            throw new QuantumException('No results found in IBM response');
        }

        Map<String, Object> firstResult = (Map<String, Object>) results[0];
        Map<String, Object> data = (Map<String, Object>) firstResult.get(
            'data'
        );

        if (data == null) {
            throw new QuantumException('No data found in IBM results');
        }

        Map<String, Object> meas = (Map<String, Object>) data.get('meas');
        if (meas == null) {
            throw new QuantumException(
                'No measurement data found in IBM results'
            );
        }

        List<Object> samples = (List<Object>) meas.get('samples');
        if (samples == null || samples.isEmpty()) {
            throw new QuantumException('No samples found in measurement data');
        }

        for (Object sample : samples) {
            String sampleStr = (String) sample;
            if (sampleStr.startsWith('0x') || sampleStr.startsWith('0X')) {
                bitstrings.add(hexToBinary(sampleStr, numQubits));
            } else {
                bitstrings.add(sampleStr);
            }
        }

        return bitstrings;
    }

    /**
     * Convert a hex string (e.g. "0xb6") to a zero-padded binary string.
     */
    @TestVisible
    private static String hexToBinary(String hexStr, Integer numQubits) {
        String hex = hexStr.toLowerCase();
        if (hex.startsWith('0x')) {
            hex = hex.substring(2);
        }

        String binary = '';
        for (Integer i = 0; i < hex.length(); i++) {
            String digit = hex.substring(i, i + 1);
            String nibble = HEX_TO_BIN.get(digit);
            if (nibble == null) {
                throw new QuantumException(
                    'Invalid hex digit in sample: ' + digit
                );
            }
            binary += nibble;
        }

        // Zero-pad to numQubits width
        while (binary.length() < numQubits) {
            binary = '0' + binary;
        }

        // Trim leading bits if hex produced more than numQubits
        if (binary.length() > numQubits) {
            binary = binary.substring(binary.length() - numQubits);
        }

        return binary;
    }

    /**
     * Concatenate list of bitstrings into a single random bit pool.
     * The pool layout is shot-major: shot s occupies characters
     * [s*numQubits, (s+1)*numQubits). Within each shot string IBM's
     * big-endian convention applies (meas[0] is the RIGHTMOST char),
     * so a fixed character offset within every shot always maps to the
     * same physical qubit. vonNeumannDebias(bits, numQubits) relies on
     * this layout to de-interleave per-qubit streams.
     */
    public static String concatenateBitstrings(List<String> bitstrings) {
        return String.join(bitstrings, '');
    }

    /**
     * Apply von Neumann debiasing to correct for hardware bias.
     * Pairs of bits: 01 -> 0, 10 -> 1, 00/11 -> discard
     * This produces unbiased bits at the cost of ~75% data loss.
     *
     * BACKWARD-COMPATIBLE OVERLOAD: treats the whole pool as ONE stream
     * (safe default only when the pool really is a single i.i.d. stream).
     * For pools built by concatenateBitstrings from multi-qubit shots,
     * prefer vonNeumannDebias(rawBits, numQubits): pairing adjacent bits
     * of an interleaved pool pairs bits from DIFFERENT qubits, whose
     * biases do not cancel (and which are engineered to be correlated in
     * Bell-test mode).
     */
    public static String vonNeumannDebias(String rawBits) {
        return vonNeumannDebias(rawBits, 1);
    }

    /**
     * Per-qubit von Neumann debiasing.
     * De-interleaves the shot-major pool (see concatenateBitstrings) into
     * numQubits per-qubit streams — the bit at character offset o of shot s
     * lives at pool index s*numQubits + o, and offset o maps to the same
     * physical qubit in every shot (IBM big-endian: meas index
     * numQubits-1-o). Each stream is debiased against itself (adjacent
     * pairs within the stream, i.e. successive shots of the same qubit),
     * and the debiased streams are concatenated in offset order.
     *
     * Von Neumann's guarantee requires pairs of i.i.d. bits from the same
     * source; per-qubit pairing satisfies that, cross-qubit pairing does not.
     *
     * Trailing bits that do not form a complete shot are discarded.
     * numQubits == null or <= 1 falls back to single-stream behavior.
     */
    public static String vonNeumannDebias(String rawBits, Integer numQubits) {
        if (rawBits == null) {
            return '';
        }
        if (numQubits == null || numQubits <= 1) {
            return debiasSingleStream(rawBits);
        }

        Integer numShots = rawBits.length() / numQubits;
        List<String> debiasedStreams = new List<String>();
        for (Integer offset = 0; offset < numQubits; offset++) {
            List<String> streamChars = new List<String>();
            for (Integer s = 0; s < numShots; s++) {
                Integer idx = s * numQubits + offset;
                streamChars.add(rawBits.substring(idx, idx + 1));
            }
            debiasedStreams.add(
                debiasSingleStream(String.join(streamChars, ''))
            );
        }
        return String.join(debiasedStreams, '');
    }

    /**
     * Per-qubit von Neumann debiasing for BELL-TEST jobs.
     * In Bell mode qubits are measured in entangled pairs
     * (meas[0]=Alice0, meas[1]=Bob0, meas[2]=Alice1, ...), so the two bits
     * of a pair are engineered to be correlated: including both sides in
     * the randomness pool violates the i.i.d. assumption. This helper
     * keeps only the Alice-side qubits (even meas indices) — one
     * independent bit per entangled pair — then applies per-qubit
     * debiasing to those streams.
     *
     * Stored shot strings are IBM big-endian (meas[0] rightmost), so the
     * meas index of character offset o is numQubits-1-o. Streams are
     * concatenated in ascending character-offset order (deterministic for
     * audit replay).
     *
     * NOT yet wired into JobProcessor — integration point for Bell-test
     * jobs: replace vonNeumannDebias(rawBits, numQubits) with this method
     * when job.Use_Bell_Test__c == true.
     */
    public static String vonNeumannDebiasBellPairs(
        String rawBits,
        Integer numQubits
    ) {
        if (rawBits == null || numQubits == null || numQubits <= 1) {
            // Bell mode needs at least one (Alice, Bob) pair
            return '';
        }

        Integer numShots = rawBits.length() / numQubits;
        List<String> debiasedStreams = new List<String>();
        for (Integer offset = 0; offset < numQubits; offset++) {
            Integer measIndex = numQubits - 1 - offset;
            if (Math.mod(measIndex, 2) != 0) {
                continue; // Bob-side qubit — correlated with its Alice partner
            }
            List<String> streamChars = new List<String>();
            for (Integer s = 0; s < numShots; s++) {
                Integer idx = s * numQubits + offset;
                streamChars.add(rawBits.substring(idx, idx + 1));
            }
            debiasedStreams.add(
                debiasSingleStream(String.join(streamChars, ''))
            );
        }
        return String.join(debiasedStreams, '');
    }

    /**
     * Von Neumann debias a single i.i.d. bit stream: adjacent
     * non-overlapping pairs, 01 -> 0, 10 -> 1, 00/11 discarded.
     * O(n) via list building (no quadratic string concatenation).
     */
    private static String debiasSingleStream(String bits) {
        List<String> debiased = new List<String>();
        for (Integer i = 0; i < bits.length() - 1; i += 2) {
            String bit1 = bits.substring(i, i + 1);
            String bit2 = bits.substring(i + 1, i + 2);
            if (bit1 == '0' && bit2 == '1') {
                debiased.add('0');
            } else if (bit1 == '1' && bit2 == '0') {
                debiased.add('1');
            }
            // 00 and 11 are discarded
        }
        return String.join(debiased, '');
    }

    /**
     * Parse all expectation values from a multi-PUB Estimator V2 response.
     * Returns a list of Doubles, one per PUB in submission order.
     * Expected format: {"results":[{"data":{"evs":1.23}},{"data":{"evs":0.98}},...]}
     */
    public static List<Double> parseAllEstimatorResults(String jsonResponse) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            jsonResponse
        );
        List<Object> results = (List<Object>) response.get('results');
        if (results == null || results.isEmpty()) {
            throw new QuantumException(
                'No results found in Estimator response'
            );
        }

        List<Double> values = new List<Double>();
        for (Object resultObj : results) {
            Map<String, Object> result = (Map<String, Object>) resultObj;
            Map<String, Object> data = (Map<String, Object>) result.get('data');
            if (data == null) {
                throw new QuantumException('No data found in Estimator result');
            }
            Object evsRaw = data.get('evs');
            if (evsRaw instanceof List<Object>) {
                List<Object> evsList = (List<Object>) evsRaw;
                values.add(Double.valueOf(String.valueOf(evsList[0])));
            } else {
                values.add(Double.valueOf(String.valueOf(evsRaw)));
            }
        }
        return values;
    }

    /**
     * Parse all standard deviations from a multi-PUB Estimator V2 response.
     */
    public static List<Double> parseAllEstimatorStds(String jsonResponse) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            jsonResponse
        );
        List<Object> results = (List<Object>) response.get('results');
        if (results == null || results.isEmpty()) {
            return new List<Double>();
        }

        List<Double> stds = new List<Double>();
        for (Object resultObj : results) {
            Map<String, Object> result = (Map<String, Object>) resultObj;
            Map<String, Object> data = (Map<String, Object>) result.get('data');
            if (data == null) {
                stds.add(null);
                continue;
            }
            Object stdsRaw = data.get('stds');
            if (stdsRaw instanceof List<Object>) {
                List<Object> stdsList = (List<Object>) stdsRaw;
                stds.add(
                    stdsList.isEmpty()
                        ? null
                        : Double.valueOf(String.valueOf(stdsList[0]))
                );
            } else if (stdsRaw != null) {
                stds.add(Double.valueOf(String.valueOf(stdsRaw)));
            } else {
                stds.add(null);
            }
        }
        return stds;
    }

    /**
     * Parse IBM Estimator V2 response and extract first expectation value.
     * Expected format: {"results":[{"data":{"evs":[1.23],"stds":[0.05]}}]}
     */
    public static Double parseEstimatorResult(String jsonResponse) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            jsonResponse
        );
        List<Object> results = (List<Object>) response.get('results');

        if (results == null || results.isEmpty()) {
            throw new QuantumException(
                'No results found in Estimator response'
            );
        }

        Map<String, Object> firstResult = (Map<String, Object>) results[0];
        Map<String, Object> data = (Map<String, Object>) firstResult.get(
            'data'
        );

        if (data == null) {
            throw new QuantumException('No data found in Estimator results');
        }

        // IBM may return evs as a single value or an array
        Object evsRaw = data.get('evs');
        if (evsRaw == null) {
            throw new QuantumException(
                'No expectation values found in Estimator results'
            );
        }

        if (evsRaw instanceof List<Object>) {
            List<Object> evsList = (List<Object>) evsRaw;
            if (evsList.isEmpty()) {
                throw new QuantumException(
                    'No expectation values found in Estimator results'
                );
            }
            return Double.valueOf(String.valueOf(evsList[0]));
        }
        return Double.valueOf(String.valueOf(evsRaw));
    }

    /**
     * Parse IBM Estimator V2 response and extract standard deviation.
     */
    public static Double parseEstimatorStd(String jsonResponse) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            jsonResponse
        );
        List<Object> results = (List<Object>) response.get('results');

        if (results == null || results.isEmpty()) {
            return null;
        }

        Map<String, Object> firstResult = (Map<String, Object>) results[0];
        Map<String, Object> data = (Map<String, Object>) firstResult.get(
            'data'
        );
        if (data == null) {
            return null;
        }

        // IBM may return stds as a single value or an array
        Object stdsRaw = data.get('stds');
        if (stdsRaw == null) {
            return null;
        }

        if (stdsRaw instanceof List<Object>) {
            List<Object> stdsList = (List<Object>) stdsRaw;
            if (stdsList.isEmpty()) {
                return null;
            }
            return Double.valueOf(String.valueOf(stdsList[0]));
        }
        return Double.valueOf(String.valueOf(stdsRaw));
    }

    /**
     * Format IBM Estimator V2 response into a human-readable summary.
     * Extracts the key fields from the raw JSON and presents them clearly.
     */
    public static String formatEstimatorSummary(
        String resultsJson,
        Double sValue,
        Double std
    ) {
        String summary = '=== CHSH Bell Test Results ===\n\n';
        summary += 'S-Value:           ' + sValue + '\n';
        summary += 'Classical Bound:   2.0\n';
        summary += 'Quantum Maximum:   2.828 (2\u221A2)\n';
        summary +=
            'Result:            ' +
            (sValue > 2.0
                ? 'PASS - Quantum behavior confirmed'
                : 'FAIL - Below classical bound') +
            '\n';
        if (std != null) {
            summary += 'Std Deviation:     ' + std + '\n';
            Double sigmaRaw = (sValue - 2.0) / std;
            String sigmaStr = String.valueOf(
                Math.round(sigmaRaw * 10.0) / 10.0
            );
            summary += 'Sigma Above 2.0:   ' + sigmaStr + '\u03C3\n';
        }

        // Extract metadata from raw JSON
        try {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
                resultsJson
            );
            List<Object> results = (List<Object>) response.get('results');
            if (results != null && !results.isEmpty()) {
                Map<String, Object> firstResult = (Map<String, Object>) results[0];
                Map<String, Object> metadata = (Map<String, Object>) firstResult.get(
                    'metadata'
                );
                if (metadata != null) {
                    summary += '\n=== Execution ===\n\n';
                    if (metadata.containsKey('shots')) {
                        summary +=
                            'Shots:             ' +
                            metadata.get('shots') +
                            '\n';
                    }
                    if (metadata.containsKey('num_randomizations')) {
                        summary +=
                            'Randomizations:    ' +
                            metadata.get('num_randomizations') +
                            '\n';
                    }
                    if (metadata.containsKey('target_precision')) {
                        summary +=
                            'Target Precision:  ' +
                            metadata.get('target_precision') +
                            '\n';
                    }
                }
                Map<String, Object> data = (Map<String, Object>) firstResult.get(
                    'data'
                );
                if (
                    data != null && data.containsKey('ensemble_standard_error')
                ) {
                    summary +=
                        'Ensemble Std Err:  ' +
                        data.get('ensemble_standard_error') +
                        '\n';
                }
            }

            Map<String, Object> topMeta = (Map<String, Object>) response.get(
                'metadata'
            );
            if (topMeta != null) {
                summary += '\n=== Error Mitigation ===\n\n';
                Map<String, Object> resilience = (Map<String, Object>) topMeta.get(
                    'resilience'
                );
                if (resilience != null) {
                    summary +=
                        'Measure Mitigation:  ' +
                        resilience.get('measure_mitigation') +
                        '\n';
                    summary +=
                        'ZNE Mitigation:      ' +
                        resilience.get('zne_mitigation') +
                        '\n';
                    summary +=
                        'PEC Mitigation:      ' +
                        resilience.get('pec_mitigation') +
                        '\n';
                }
                Map<String, Object> twirling = (Map<String, Object>) topMeta.get(
                    'twirling'
                );
                if (twirling != null) {
                    summary += '\n=== Twirling ===\n\n';
                    summary +=
                        'Measure Twirling:    ' +
                        twirling.get('enable_measure') +
                        '\n';
                    summary +=
                        'Gate Twirling:       ' +
                        twirling.get('enable_gates') +
                        '\n';
                    summary +=
                        'Strategy:            ' +
                        twirling.get('strategy') +
                        '\n';
                }
            }
        } catch (Exception e) {
            summary +=
                '\n(Could not parse full metadata: ' +
                e.getMessage() +
                ')';
        }

        return summary;
    }

    /**
     * Convert a binary string to an integer value.
     * Used for assignment calculations.
     */
    public static Integer bitsToInteger(String bits) {
        Integer result = 0;
        for (Integer i = 0; i < bits.length(); i++) {
            result = result * 2;
            if (bits.substring(i, i + 1) == '1') {
                result += 1;
            }
        }
        return result;
    }

    /**
     * Consume N bits from the bit pool starting at the given offset.
     * Returns the consumed bits as a string.
     */
    public static String consumeBits(
        String bitPool,
        Integer offset,
        Integer numBits
    ) {
        if (offset + numBits > bitPool.length()) {
            throw new QuantumException(
                'Not enough random bits available. Need ' +
                    (offset + numBits) +
                    ' but only have ' +
                    bitPool.length()
            );
        }
        return bitPool.substring(offset, offset + numBits);
    }

    /**
     * Convert a binary string to compact hex representation.
     * Zero-pads to a multiple of 4 bits before conversion.
     */
    public static String binaryToHex(String bits) {
        Integer remainder = Math.mod(bits.length(), 4);
        if (remainder == 1) {
            bits = '000' + bits;
        } else if (remainder == 2) {
            bits = '00' + bits;
        } else if (remainder == 3) {
            bits = '0' + bits;
        }

        List<String> hexChars = new List<String>();
        for (Integer i = 0; i < bits.length(); i += 4) {
            String nibble = bits.substring(i, i + 4);
            hexChars.add(BIN_TO_HEX.get(nibble));
        }
        return String.join(hexChars, '');
    }

    /**
     * Encode raw bits for storage: prefix with '0x' and store as hex.
     * Fits 4x more data in the same LongTextArea field.
     */
    public static String encodeForStorage(String rawBits) {
        return '0x' + binaryToHex(rawBits);
    }

    /**
     * Decode stored raw results back to binary bitstring.
     * Handles both hex-encoded ('0x' prefix) and legacy binary formats.
     */
    public static String decodeRawResults(String stored) {
        if (stored == null) {
            return null;
        }
        if (stored.startsWith('0x')) {
            String hex = stored.substring(2).toLowerCase();
            List<String> binChars = new List<String>();
            for (Integer i = 0; i < hex.length(); i++) {
                String digit = hex.substring(i, i + 1);
                String nibble = HEX_TO_BIN.get(digit);
                if (nibble == null) {
                    throw new QuantumException(
                        'Invalid hex digit in stored results: ' + digit
                    );
                }
                binChars.add(nibble);
            }
            return String.join(binChars, '');
        }
        return stored;
    }

    /**
     * Generate a 128-bit binary fingerprint from a bitstring.
     * Uses SHA-256, takes first 128 bits, displays as 0s and 1s.
     * Always the same length regardless of input size — a quantum DNA sequence.
     */
    public static String generateFingerprint(String bits) {
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(bits));
        String hex = EncodingUtil.convertToHex(hash);
        // Take first 32 hex chars = 128 bits
        List<String> binChars = new List<String>();
        for (Integer i = 0; i < 32 && i < hex.length(); i++) {
            binChars.add(HEX_TO_BIN.get(hex.substring(i, i + 1)));
        }
        return String.join(binChars, '');
    }
}
