/**
 * Parses IBM Sampler results and applies von Neumann debiasing.
 * Extracts raw bitstrings, concatenates into bit pool, removes hardware bias.
 */
public with sharing class QRNGResultParser {
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
            throw new QRNGException('No results found in IBM response');
        }

        Map<String, Object> firstResult = (Map<String, Object>) results[0];
        Map<String, Object> data = (Map<String, Object>) firstResult.get(
            'data'
        );

        if (data == null) {
            throw new QRNGException('No data found in IBM results');
        }

        Map<String, Object> meas = (Map<String, Object>) data.get('meas');
        if (meas == null) {
            throw new QRNGException('No measurement data found in IBM results');
        }

        List<Object> samples = (List<Object>) meas.get('samples');
        if (samples == null || samples.isEmpty()) {
            throw new QRNGException('No samples found in measurement data');
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
                throw new QRNGException(
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
     */
    public static String concatenateBitstrings(List<String> bitstrings) {
        String result = '';
        for (String bs : bitstrings) {
            result += bs;
        }
        return result;
    }

    /**
     * Apply von Neumann debiasing to correct for hardware bias.
     * Pairs of bits: 01 -> 0, 10 -> 1, 00/11 -> discard
     * This produces unbiased bits at the cost of ~75% data loss.
     */
    public static String vonNeumannDebias(String rawBits) {
        String debiased = '';

        for (Integer i = 0; i < rawBits.length() - 1; i += 2) {
            String bit1 = rawBits.substring(i, i + 1);
            String bit2 = rawBits.substring(i + 1, i + 2);

            if (bit1 == '0' && bit2 == '1') {
                debiased += '0';
            } else if (bit1 == '1' && bit2 == '0') {
                debiased += '1';
            }
            // 00 and 11 are discarded
        }

        return debiased;
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
            throw new QRNGException(
                'Not enough random bits available. Need ' +
                    (offset + numBits) +
                    ' but only have ' +
                    bitPool.length()
            );
        }
        return bitPool.substring(offset, offset + numBits);
    }
}
