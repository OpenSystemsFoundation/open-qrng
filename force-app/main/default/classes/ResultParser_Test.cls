@IsTest
private class ResultParser_Test {
    @IsTest
    static void testParseSamplerResultsBinary() {
        String json = '{"results":[{"data":{"meas":{"samples":["0110","1001","1110","0011"]}}}]}';
        List<String> bitstrings = ResultParser.parseSamplerResults(json, 4);
        System.assertEquals(4, bitstrings.size());
        System.assertEquals('0110', bitstrings[0]);
        System.assertEquals('0011', bitstrings[3]);
    }

    @IsTest
    static void testParseSamplerResultsHex() {
        // IBM Sampler returns hex-encoded samples like "0xb6"
        String json = '{"results":[{"data":{"meas":{"samples":["0xb6","0x17","0x04"]}}}]}';
        List<String> bitstrings = ResultParser.parseSamplerResults(json, 8);
        System.assertEquals(3, bitstrings.size());
        System.assertEquals('10110110', bitstrings[0]); // 0xb6
        System.assertEquals('00010111', bitstrings[1]); // 0x17
        System.assertEquals('00000100', bitstrings[2]); // 0x04
    }

    @IsTest
    static void testParseSamplerResultsNoResults() {
        try {
            ResultParser.parseSamplerResults('{"results":[]}', 8);
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('No results'),
                'Should indicate no results'
            );
        }
    }

    @IsTest
    static void testHexToBinary() {
        // Test via hex samples
        System.assertEquals('11111111', ResultParser.hexToBinary('0xff', 8));
        System.assertEquals('00000000', ResultParser.hexToBinary('0x00', 8));
        System.assertEquals('00000001', ResultParser.hexToBinary('0x1', 8));
        // 12-qubit hex
        System.assertEquals(
            '101010110110',
            ResultParser.hexToBinary('0xab6', 12)
        );
    }

    @IsTest
    static void testHexToBinaryInvalidDigit() {
        try {
            ResultParser.hexToBinary('0xzz', 8);
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('Invalid hex digit'),
                'Should indicate invalid hex'
            );
        }
    }

    @IsTest
    static void testConcatenateBitstrings() {
        List<String> bs = new List<String>{ '0110', '1001', '1110' };
        String result = ResultParser.concatenateBitstrings(bs);
        System.assertEquals('011010011110', result);
    }

    @IsTest
    static void testVonNeumannDebias() {
        // 01 -> 0, 10 -> 1, 00 -> discard, 11 -> discard
        String raw = '01100011';
        String debiased = ResultParser.vonNeumannDebias(raw);
        // Pairs: 01->0, 10->1, 00->discard, 11->discard
        System.assertEquals('01', debiased);
    }

    @IsTest
    static void testVonNeumannDebiasAllDiscard() {
        String raw = '00001111';
        String debiased = ResultParser.vonNeumannDebias(raw);
        System.assertEquals('', debiased);
    }

    @IsTest
    static void testBitsToInteger() {
        System.assertEquals(0, ResultParser.bitsToInteger('000'));
        System.assertEquals(7, ResultParser.bitsToInteger('111'));
        System.assertEquals(5, ResultParser.bitsToInteger('101'));
        System.assertEquals(1, ResultParser.bitsToInteger('1'));
    }

    @IsTest
    static void testConsumeBits() {
        String pool = '0110100111100011';
        System.assertEquals('0110', ResultParser.consumeBits(pool, 0, 4));
        System.assertEquals('1001', ResultParser.consumeBits(pool, 4, 4));
    }

    @IsTest
    static void testParseEstimatorResult() {
        String json = '{"results":[{"data":{"evs":[2.45],"stds":[0.05]}}]}';
        Double result = ResultParser.parseEstimatorResult(json);
        System.assertEquals(2.45, result, 'Should parse expectation value');
    }

    @IsTest
    static void testParseEstimatorResultNegative() {
        String json = '{"results":[{"data":{"evs":[-2.61],"stds":[0.03]}}]}';
        Double result = ResultParser.parseEstimatorResult(json);
        System.assertEquals(
            -2.61,
            result,
            'Should parse negative expectation value'
        );
    }

    @IsTest
    static void testParseEstimatorStd() {
        String json = '{"results":[{"data":{"evs":[2.45],"stds":[0.05]}}]}';
        Double std = ResultParser.parseEstimatorStd(json);
        System.assertEquals(0.05, std, 'Should parse standard deviation');
    }

    @IsTest
    static void testParseEstimatorResultScalar() {
        // IBM sometimes returns evs/stds as scalar instead of array
        String json = '{"results":[{"data":{"evs":2.45,"stds":0.05}}]}';
        Double result = ResultParser.parseEstimatorResult(json);
        System.assertEquals(2.45, result, 'Should parse scalar evs');
        Double std = ResultParser.parseEstimatorStd(json);
        System.assertEquals(0.05, std, 'Should parse scalar stds');
    }

    @IsTest
    static void testParseEstimatorResultNoResults() {
        try {
            ResultParser.parseEstimatorResult('{"results":[]}');
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('No results'),
                'Should indicate no results'
            );
        }
    }

    @IsTest
    static void testConsumeBitsInsufficientBits() {
        try {
            ResultParser.consumeBits('0110', 2, 4);
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('Not enough'),
                'Should indicate insufficient bits'
            );
        }
    }

    // ── binaryToHex ─────────────────────────────────────────────────

    @IsTest
    static void testBinaryToHex() {
        System.assertEquals('f', ResultParser.binaryToHex('1111'));
        System.assertEquals('0', ResultParser.binaryToHex('0000'));
        System.assertEquals('ff', ResultParser.binaryToHex('11111111'));
        System.assertEquals('b6', ResultParser.binaryToHex('10110110'));
    }

    @IsTest
    static void testBinaryToHexPadding() {
        // 1 bit → padded to 0001 → '1'
        System.assertEquals('1', ResultParser.binaryToHex('1'));
        // 2 bits → padded to 0010 → '2'
        System.assertEquals('2', ResultParser.binaryToHex('10'));
        // 3 bits → padded to 0101 → '5'
        System.assertEquals('5', ResultParser.binaryToHex('101'));
        // 5 bits → padded to 00010001 → '11'
        System.assertEquals('11', ResultParser.binaryToHex('10001'));
    }

    // ── encodeForStorage / decodeRawResults ─────────────────────────

    @IsTest
    static void testEncodeForStorage() {
        String encoded = ResultParser.encodeForStorage('10110110');
        System.assertEquals(
            '0xb6',
            encoded,
            'Should encode as 0x-prefixed hex'
        );
    }

    @IsTest
    static void testDecodeRawResultsHex() {
        String decoded = ResultParser.decodeRawResults('0xb6');
        System.assertEquals('10110110', decoded, 'Should decode hex to binary');
    }

    @IsTest
    static void testDecodeRawResultsLegacyBinary() {
        // Legacy format: raw binary string
        String decoded = ResultParser.decodeRawResults('01100110');
        System.assertEquals('01100110', decoded, 'Should return binary as-is');
    }

    @IsTest
    static void testDecodeRawResultsNull() {
        System.assertEquals(
            null,
            ResultParser.decodeRawResults(null),
            'Should return null for null input'
        );
    }

    @IsTest
    static void testDecodeRawResultsInvalidHex() {
        try {
            ResultParser.decodeRawResults('0xzz');
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('Invalid hex digit'),
                'Should indicate invalid hex'
            );
        }
    }

    @IsTest
    static void testEncodeDecodeRoundTrip() {
        String original = '0110100111100011';
        String encoded = ResultParser.encodeForStorage(original);
        String decoded = ResultParser.decodeRawResults(encoded);
        System.assertEquals(
            original,
            decoded,
            'Round trip should preserve data'
        );
    }

    // ── generateFingerprint ─────────────────────────────────────────

    @IsTest
    static void testGenerateFingerprint() {
        String fp = ResultParser.generateFingerprint('01100110');
        System.assertNotEquals(null, fp, 'Fingerprint should not be null');
        System.assertEquals(128, fp.length(), 'Fingerprint should be 128 bits');
        // Only 0s and 1s
        for (Integer i = 0; i < fp.length(); i++) {
            String ch = fp.substring(i, i + 1);
            System.assert(
                ch == '0' || ch == '1',
                'Fingerprint should contain only 0s and 1s'
            );
        }
    }

    @IsTest
    static void testGenerateFingerprintDeterministic() {
        String fp1 = ResultParser.generateFingerprint('01100110');
        String fp2 = ResultParser.generateFingerprint('01100110');
        System.assertEquals(
            fp1,
            fp2,
            'Same input should produce same fingerprint'
        );
    }

    @IsTest
    static void testGenerateFingerprintDifferentInputs() {
        String fp1 = ResultParser.generateFingerprint('01100110');
        String fp2 = ResultParser.generateFingerprint('10011001');
        System.assertNotEquals(
            fp1,
            fp2,
            'Different inputs should produce different fingerprints'
        );
    }

    // ── parseAllEstimatorResults ────────────────────────────────────

    @IsTest
    static void testParseAllEstimatorResultsMultiPub() {
        String json =
            '{"results":[' +
            '{"data":{"evs":[0.71]}},' +
            '{"data":{"evs":[0.72]}},' +
            '{"data":{"evs":[-0.69]}}' +
            ']}';
        List<Double> evs = ResultParser.parseAllEstimatorResults(json);
        System.assertEquals(3, evs.size());
        System.assertEquals(0.71, evs[0]);
        System.assertEquals(0.72, evs[1]);
        System.assertEquals(-0.69, evs[2]);
    }

    @IsTest
    static void testParseAllEstimatorResultsScalarEvs() {
        // evs as scalar instead of array
        String json = '{"results":[{"data":{"evs":2.45}}]}';
        List<Double> evs = ResultParser.parseAllEstimatorResults(json);
        System.assertEquals(1, evs.size());
        System.assertEquals(2.45, evs[0]);
    }

    @IsTest
    static void testParseAllEstimatorResultsNoResults() {
        try {
            ResultParser.parseAllEstimatorResults('{"results":[]}');
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No results'));
        }
    }

    @IsTest
    static void testParseAllEstimatorResultsNoData() {
        try {
            ResultParser.parseAllEstimatorResults(
                '{"results":[{"metadata":{}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No data'));
        }
    }

    // ── parseAllEstimatorStds ───────────────────────────────────────

    @IsTest
    static void testParseAllEstimatorStdsMultiPub() {
        String json =
            '{"results":[' +
            '{"data":{"evs":[0.71],"stds":[0.02]}},' +
            '{"data":{"evs":[0.72],"stds":[0.03]}}' +
            ']}';
        List<Double> stds = ResultParser.parseAllEstimatorStds(json);
        System.assertEquals(2, stds.size());
        System.assertEquals(0.02, stds[0]);
        System.assertEquals(0.03, stds[1]);
    }

    @IsTest
    static void testParseAllEstimatorStdsNoStds() {
        String json = '{"results":[{"data":{"evs":[0.71]}}]}';
        List<Double> stds = ResultParser.parseAllEstimatorStds(json);
        System.assertEquals(1, stds.size());
        System.assertEquals(null, stds[0]);
    }

    @IsTest
    static void testParseAllEstimatorStdsScalar() {
        String json = '{"results":[{"data":{"evs":2.45,"stds":0.05}}]}';
        List<Double> stds = ResultParser.parseAllEstimatorStds(json);
        System.assertEquals(1, stds.size());
        System.assertEquals(0.05, stds[0]);
    }

    @IsTest
    static void testParseAllEstimatorStdsNoResults() {
        List<Double> stds = ResultParser.parseAllEstimatorStds(
            '{"results":[]}'
        );
        System.assertEquals(0, stds.size());
    }

    @IsTest
    static void testParseAllEstimatorStdsNoData() {
        List<Double> stds = ResultParser.parseAllEstimatorStds(
            '{"results":[{"metadata":{}}]}'
        );
        System.assertEquals(1, stds.size());
        System.assertEquals(null, stds[0]);
    }

    @IsTest
    static void testParseAllEstimatorStdsEmptyArray() {
        String json = '{"results":[{"data":{"evs":[0.71],"stds":[]}}]}';
        List<Double> stds = ResultParser.parseAllEstimatorStds(json);
        System.assertEquals(1, stds.size());
        System.assertEquals(null, stds[0]);
    }

    // ── formatEstimatorSummary ──────────────────────────────────────

    @IsTest
    static void testFormatEstimatorSummaryPass() {
        String json = '{"results":[{"data":{"evs":[2.61],"stds":[0.04]},"metadata":{"shots":4096}}],"metadata":{"resilience":{"measure_mitigation":true,"zne_mitigation":false,"pec_mitigation":false},"twirling":{"enable_measure":true,"enable_gates":false,"strategy":"active"}}}';
        String summary = ResultParser.formatEstimatorSummary(
            json,
            (Double) 2.61,
            (Double) 0.04
        );
        System.assert(summary.contains('PASS'), 'Should show PASS');
        System.assert(summary.contains('2.61'), 'Should contain S-value');
        System.assert(
            summary.contains('Std Deviation'),
            'Should contain std dev'
        );
        System.assert(summary.contains('4096'), 'Should contain shots');
        System.assert(
            summary.contains('Measure Mitigation'),
            'Should contain resilience info'
        );
        System.assert(
            summary.contains('Measure Twirling'),
            'Should contain twirling info'
        );
    }

    @IsTest
    static void testFormatEstimatorSummaryFail() {
        String json = '{"results":[{"data":{"evs":[1.5],"stds":[0.1]}}]}';
        String summary = ResultParser.formatEstimatorSummary(
            json,
            (Double) 1.5,
            (Double) 0.1
        );
        System.assert(summary.contains('FAIL'), 'Should show FAIL');
    }

    @IsTest
    static void testFormatEstimatorSummaryNullStd() {
        String json = '{"results":[{"data":{"evs":[2.3]}}]}';
        String summary = ResultParser.formatEstimatorSummary(
            json,
            (Double) 2.3,
            null
        );
        System.assert(
            !summary.contains('Std Deviation'),
            'Should not show std when null'
        );
    }

    @IsTest
    static void testFormatEstimatorSummaryMalformedJson() {
        // Should not throw — gracefully handles parse errors
        String summary = ResultParser.formatEstimatorSummary(
            'not json',
            (Double) 2.5,
            (Double) 0.05
        );
        System.assert(
            summary.contains('Could not parse'),
            'Should indicate parse error'
        );
    }

    // ── parseSamplerResults edge cases ──────────────────────────────

    @IsTest
    static void testParseSamplerResultsNoData() {
        try {
            ResultParser.parseSamplerResults(
                '{"results":[{"metadata":{}}]}',
                8
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No data'));
        }
    }

    @IsTest
    static void testParseSamplerResultsNoMeas() {
        try {
            ResultParser.parseSamplerResults(
                '{"results":[{"data":{"other":"stuff"}}]}',
                8
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No measurement'));
        }
    }

    @IsTest
    static void testParseSamplerResultsNoSamples() {
        try {
            ResultParser.parseSamplerResults(
                '{"results":[{"data":{"meas":{}}}]}',
                8
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No samples'));
        }
    }

    @IsTest
    static void testParseEstimatorResultNoData() {
        try {
            ResultParser.parseEstimatorResult('{"results":[{"metadata":{}}]}');
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No data'));
        }
    }

    @IsTest
    static void testParseEstimatorResultNoEvs() {
        try {
            ResultParser.parseEstimatorResult(
                '{"results":[{"data":{"stds":[0.05]}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No expectation'));
        }
    }

    @IsTest
    static void testParseEstimatorResultEmptyEvsArray() {
        try {
            ResultParser.parseEstimatorResult(
                '{"results":[{"data":{"evs":[]}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No expectation'));
        }
    }

    @IsTest
    static void testParseEstimatorStdNoResults() {
        Double std = ResultParser.parseEstimatorStd('{"results":[]}');
        System.assertEquals(null, std);
    }

    @IsTest
    static void testParseEstimatorStdNoData() {
        Double std = ResultParser.parseEstimatorStd(
            '{"results":[{"metadata":{}}]}'
        );
        System.assertEquals(null, std);
    }

    @IsTest
    static void testParseEstimatorStdNoStds() {
        Double std = ResultParser.parseEstimatorStd(
            '{"results":[{"data":{"evs":[2.5]}}]}'
        );
        System.assertEquals(null, std);
    }

    @IsTest
    static void testParseEstimatorStdEmptyArray() {
        Double std = ResultParser.parseEstimatorStd(
            '{"results":[{"data":{"evs":[2.5],"stds":[]}}]}'
        );
        System.assertEquals(null, std);
    }

    // ── vonNeumannDebias edge cases ─────────────────────────────────

    @IsTest
    static void testVonNeumannDebiasOddLength() {
        // Last bit is ignored (odd length → last bit has no pair)
        String raw = '010';
        String debiased = ResultParser.vonNeumannDebias(raw);
        System.assertEquals('0', debiased);
    }

    @IsTest
    static void testVonNeumannDebiasEmpty() {
        System.assertEquals('', ResultParser.vonNeumannDebias(''));
    }

    @IsTest
    static void testVonNeumannDebiasSingleBit() {
        System.assertEquals('', ResultParser.vonNeumannDebias('1'));
    }

    @IsTest
    static void testVonNeumannDebiasNullInput() {
        System.assertEquals('', ResultParser.vonNeumannDebias(null));
        System.assertEquals('', ResultParser.vonNeumannDebias(null, 4));
    }

    // ── per-qubit vonNeumannDebias ──────────────────────────────────

    @IsTest
    static void testVonNeumannDebiasPerQubitDeinterleaves() {
        // 10 two-qubit shots; pool is shot-major so adjacent bits belong
        // to DIFFERENT qubits.
        List<String> shots = new List<String>{
            '01',
            '01',
            '11',
            '00',
            '10',
            '10',
            '00',
            '11',
            '01',
            '10'
        };
        String pool = ResultParser.concatenateBitstrings(shots);
        System.assertEquals('01011100101000110110', pool);

        // Legacy single-stream pairing (cross-qubit pairs)
        System.assertEquals('001101', ResultParser.vonNeumannDebias(pool));

        // Per-qubit: stream offset 0 = '0010110101' -> '100',
        //            stream offset 1 = '1110000110' -> '101'
        System.assertEquals(
            '100101',
            ResultParser.vonNeumannDebias(pool, 2),
            'Per-qubit debias should pair each qubit stream against itself'
        );
    }

    @IsTest
    static void testVonNeumannDebiasPerQubitCorrectsOppositeBias() {
        // Qubit A biased 60/40 toward 1, qubit B biased 40/60 (B = NOT A).
        // Every cross-qubit pair is then 01 or 10, so the OLD algorithm
        // never discards anything and simply emits qubit A's biased
        // stream verbatim. The per-qubit algorithm debiases each stream
        // against itself and the output is exactly balanced.
        String streamA = '11011011011110101000'; // 12 ones / 8 zeros (60%)
        String streamB = '00100100100001010111'; // 8 ones / 12 zeros (40%)
        List<String> shots = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            shots.add(
                streamA.substring(i, i + 1) + streamB.substring(i, i + 1)
            );
        }
        String pool = ResultParser.concatenateBitstrings(shots);
        System.assertEquals('1010011010011010011010101001100110010101', pool);

        // Old algorithm: output IS the biased qubit-A stream (60% ones)
        String oldOutput = ResultParser.vonNeumannDebias(pool);
        System.assertEquals(
            '11011011011110101000',
            oldOutput,
            'Cross-qubit pairing passes qubit A bias straight through'
        );
        System.assertEquals(
            12,
            countOnes(oldOutput),
            'Old output is still 60% ones — not debiased'
        );

        // New algorithm: balanced output
        String newOutput = ResultParser.vonNeumannDebias(pool, 2);
        System.assertEquals(
            '010111101000',
            newOutput,
            'Per-qubit debias output should match per-stream expectation'
        );
        System.assertEquals(
            6,
            countOnes(newOutput),
            'New output should be exactly 50% ones'
        );
        System.assertEquals(12, newOutput.length());
    }

    @IsTest
    static void testVonNeumannDebiasNumQubitsOneMatchesLegacy() {
        String raw = '01100011';
        System.assertEquals(
            ResultParser.vonNeumannDebias(raw),
            ResultParser.vonNeumannDebias(raw, 1)
        );
        System.assertEquals(
            ResultParser.vonNeumannDebias(raw),
            ResultParser.vonNeumannDebias(raw, null),
            'null numQubits should fall back to single-stream behavior'
        );
    }

    @IsTest
    static void testVonNeumannDebiasPerQubitTrailingPartialShot() {
        // 5 bits with numQubits=2: only 2 complete shots, trailing bit dropped
        // stream offset 0 = '01' -> '0', stream offset 1 = '10' -> '1'
        System.assertEquals('01', ResultParser.vonNeumannDebias('01101', 2));
    }

    // ── vonNeumannDebiasBellPairs ───────────────────────────────────

    @IsTest
    static void testVonNeumannDebiasBellPairsKeepsAliceOnly() {
        // numQubits=2: stored shots are big-endian, so offset 1 is meas[0]
        // (Alice) and offset 0 is meas[1] (Bob). Only the Alice stream may
        // enter the randomness pool — Bob is engineered to be correlated.
        List<String> shots = new List<String>{ '10', '01', '11', '00' };
        String pool = ResultParser.concatenateBitstrings(shots);
        // Alice stream (offset 1): '0110' -> pairs 01->0, 10->1 -> '01'
        // Bob stream (offset 0): '1010' would add '11' — must be excluded
        System.assertEquals(
            '01',
            ResultParser.vonNeumannDebiasBellPairs(pool, 2),
            'Bell debias should use only Alice-side (even meas index) qubits'
        );
        // Sanity: the non-Bell per-qubit debias includes Bob's stream too
        System.assertEquals('1101', ResultParser.vonNeumannDebias(pool, 2));
    }

    @IsTest
    static void testVonNeumannDebiasBellPairsInvalidInput() {
        System.assertEquals(
            '',
            ResultParser.vonNeumannDebiasBellPairs(null, 2)
        );
        System.assertEquals(
            '',
            ResultParser.vonNeumannDebiasBellPairs('0101', null)
        );
        System.assertEquals(
            '',
            ResultParser.vonNeumannDebiasBellPairs('0101', 1),
            'Bell mode requires at least one (Alice, Bob) pair'
        );
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

    // ── hexToBinary trimming ────────────────────────────────────────

    @IsTest
    static void testHexToBinaryTrimming() {
        // 0xff produces 8 bits, but we request only 4 qubits → trim to last 4
        String result = ResultParser.hexToBinary('0xff', 4);
        System.assertEquals('1111', result);
        System.assertEquals(4, result.length());
    }

    @IsTest
    static void testHexToBinaryUpperCase() {
        System.assertEquals('10101011', ResultParser.hexToBinary('0XAB', 8));
    }
}
