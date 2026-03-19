@IsTest
private class QRNGResultParser_Test {
    @IsTest
    static void testParseSamplerResultsBinary() {
        String json = '{"results":[{"data":{"meas":{"samples":["0110","1001","1110","0011"]}}}]}';
        List<String> bitstrings = QRNGResultParser.parseSamplerResults(json, 4);
        System.assertEquals(4, bitstrings.size());
        System.assertEquals('0110', bitstrings[0]);
        System.assertEquals('0011', bitstrings[3]);
    }

    @IsTest
    static void testParseSamplerResultsHex() {
        // IBM Sampler returns hex-encoded samples like "0xb6"
        String json = '{"results":[{"data":{"meas":{"samples":["0xb6","0x17","0x04"]}}}]}';
        List<String> bitstrings = QRNGResultParser.parseSamplerResults(json, 8);
        System.assertEquals(3, bitstrings.size());
        System.assertEquals('10110110', bitstrings[0]); // 0xb6
        System.assertEquals('00010111', bitstrings[1]); // 0x17
        System.assertEquals('00000100', bitstrings[2]); // 0x04
    }

    @IsTest
    static void testParseSamplerResultsNoResults() {
        try {
            QRNGResultParser.parseSamplerResults('{"results":[]}', 8);
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('No results'),
                'Should indicate no results'
            );
        }
    }

    @IsTest
    static void testHexToBinary() {
        // Test via hex samples
        System.assertEquals(
            '11111111',
            QRNGResultParser.hexToBinary('0xff', 8)
        );
        System.assertEquals(
            '00000000',
            QRNGResultParser.hexToBinary('0x00', 8)
        );
        System.assertEquals('00000001', QRNGResultParser.hexToBinary('0x1', 8));
        // 12-qubit hex
        System.assertEquals(
            '101010110110',
            QRNGResultParser.hexToBinary('0xab6', 12)
        );
    }

    @IsTest
    static void testHexToBinaryInvalidDigit() {
        try {
            QRNGResultParser.hexToBinary('0xzz', 8);
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('Invalid hex digit'),
                'Should indicate invalid hex'
            );
        }
    }

    @IsTest
    static void testConcatenateBitstrings() {
        List<String> bs = new List<String>{ '0110', '1001', '1110' };
        String result = QRNGResultParser.concatenateBitstrings(bs);
        System.assertEquals('011010011110', result);
    }

    @IsTest
    static void testVonNeumannDebias() {
        // 01 -> 0, 10 -> 1, 00 -> discard, 11 -> discard
        String raw = '01100011';
        String debiased = QRNGResultParser.vonNeumannDebias(raw);
        // Pairs: 01->0, 10->1, 00->discard, 11->discard
        System.assertEquals('01', debiased);
    }

    @IsTest
    static void testVonNeumannDebiasAllDiscard() {
        String raw = '00001111';
        String debiased = QRNGResultParser.vonNeumannDebias(raw);
        System.assertEquals('', debiased);
    }

    @IsTest
    static void testBitsToInteger() {
        System.assertEquals(0, QRNGResultParser.bitsToInteger('000'));
        System.assertEquals(7, QRNGResultParser.bitsToInteger('111'));
        System.assertEquals(5, QRNGResultParser.bitsToInteger('101'));
        System.assertEquals(1, QRNGResultParser.bitsToInteger('1'));
    }

    @IsTest
    static void testConsumeBits() {
        String pool = '0110100111100011';
        System.assertEquals('0110', QRNGResultParser.consumeBits(pool, 0, 4));
        System.assertEquals('1001', QRNGResultParser.consumeBits(pool, 4, 4));
    }

    @IsTest
    static void testParseEstimatorResult() {
        String json = '{"results":[{"data":{"evs":[2.45],"stds":[0.05]}}]}';
        Double result = QRNGResultParser.parseEstimatorResult(json);
        System.assertEquals(2.45, result, 'Should parse expectation value');
    }

    @IsTest
    static void testParseEstimatorResultNegative() {
        String json = '{"results":[{"data":{"evs":[-2.61],"stds":[0.03]}}]}';
        Double result = QRNGResultParser.parseEstimatorResult(json);
        System.assertEquals(
            -2.61,
            result,
            'Should parse negative expectation value'
        );
    }

    @IsTest
    static void testParseEstimatorStd() {
        String json = '{"results":[{"data":{"evs":[2.45],"stds":[0.05]}}]}';
        Double std = QRNGResultParser.parseEstimatorStd(json);
        System.assertEquals(0.05, std, 'Should parse standard deviation');
    }

    @IsTest
    static void testParseEstimatorResultScalar() {
        // IBM sometimes returns evs/stds as scalar instead of array
        String json = '{"results":[{"data":{"evs":2.45,"stds":0.05}}]}';
        Double result = QRNGResultParser.parseEstimatorResult(json);
        System.assertEquals(2.45, result, 'Should parse scalar evs');
        Double std = QRNGResultParser.parseEstimatorStd(json);
        System.assertEquals(0.05, std, 'Should parse scalar stds');
    }

    @IsTest
    static void testParseEstimatorResultNoResults() {
        try {
            QRNGResultParser.parseEstimatorResult('{"results":[]}');
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('No results'),
                'Should indicate no results'
            );
        }
    }

    @IsTest
    static void testConsumeBitsInsufficientBits() {
        try {
            QRNGResultParser.consumeBits('0110', 2, 4);
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('Not enough'),
                'Should indicate insufficient bits'
            );
        }
    }

    // ── binaryToHex ─────────────────────────────────────────────────

    @IsTest
    static void testBinaryToHex() {
        System.assertEquals('f', QRNGResultParser.binaryToHex('1111'));
        System.assertEquals('0', QRNGResultParser.binaryToHex('0000'));
        System.assertEquals('ff', QRNGResultParser.binaryToHex('11111111'));
        System.assertEquals('b6', QRNGResultParser.binaryToHex('10110110'));
    }

    @IsTest
    static void testBinaryToHexPadding() {
        // 1 bit → padded to 0001 → '1'
        System.assertEquals('1', QRNGResultParser.binaryToHex('1'));
        // 2 bits → padded to 0010 → '2'
        System.assertEquals('2', QRNGResultParser.binaryToHex('10'));
        // 3 bits → padded to 0101 → '5'
        System.assertEquals('5', QRNGResultParser.binaryToHex('101'));
        // 5 bits → padded to 00010001 → '11'
        System.assertEquals('11', QRNGResultParser.binaryToHex('10001'));
    }

    // ── encodeForStorage / decodeRawResults ─────────────────────────

    @IsTest
    static void testEncodeForStorage() {
        String encoded = QRNGResultParser.encodeForStorage('10110110');
        System.assertEquals(
            '0xb6',
            encoded,
            'Should encode as 0x-prefixed hex'
        );
    }

    @IsTest
    static void testDecodeRawResultsHex() {
        String decoded = QRNGResultParser.decodeRawResults('0xb6');
        System.assertEquals('10110110', decoded, 'Should decode hex to binary');
    }

    @IsTest
    static void testDecodeRawResultsLegacyBinary() {
        // Legacy format: raw binary string
        String decoded = QRNGResultParser.decodeRawResults('01100110');
        System.assertEquals('01100110', decoded, 'Should return binary as-is');
    }

    @IsTest
    static void testDecodeRawResultsNull() {
        System.assertEquals(
            null,
            QRNGResultParser.decodeRawResults(null),
            'Should return null for null input'
        );
    }

    @IsTest
    static void testDecodeRawResultsInvalidHex() {
        try {
            QRNGResultParser.decodeRawResults('0xzz');
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('Invalid hex digit'),
                'Should indicate invalid hex'
            );
        }
    }

    @IsTest
    static void testEncodeDecodeRoundTrip() {
        String original = '0110100111100011';
        String encoded = QRNGResultParser.encodeForStorage(original);
        String decoded = QRNGResultParser.decodeRawResults(encoded);
        System.assertEquals(
            original,
            decoded,
            'Round trip should preserve data'
        );
    }

    // ── generateFingerprint ─────────────────────────────────────────

    @IsTest
    static void testGenerateFingerprint() {
        String fp = QRNGResultParser.generateFingerprint('01100110');
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
        String fp1 = QRNGResultParser.generateFingerprint('01100110');
        String fp2 = QRNGResultParser.generateFingerprint('01100110');
        System.assertEquals(
            fp1,
            fp2,
            'Same input should produce same fingerprint'
        );
    }

    @IsTest
    static void testGenerateFingerprintDifferentInputs() {
        String fp1 = QRNGResultParser.generateFingerprint('01100110');
        String fp2 = QRNGResultParser.generateFingerprint('10011001');
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
        List<Double> evs = QRNGResultParser.parseAllEstimatorResults(json);
        System.assertEquals(3, evs.size());
        System.assertEquals(0.71, evs[0]);
        System.assertEquals(0.72, evs[1]);
        System.assertEquals(-0.69, evs[2]);
    }

    @IsTest
    static void testParseAllEstimatorResultsScalarEvs() {
        // evs as scalar instead of array
        String json = '{"results":[{"data":{"evs":2.45}}]}';
        List<Double> evs = QRNGResultParser.parseAllEstimatorResults(json);
        System.assertEquals(1, evs.size());
        System.assertEquals(2.45, evs[0]);
    }

    @IsTest
    static void testParseAllEstimatorResultsNoResults() {
        try {
            QRNGResultParser.parseAllEstimatorResults('{"results":[]}');
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No results'));
        }
    }

    @IsTest
    static void testParseAllEstimatorResultsNoData() {
        try {
            QRNGResultParser.parseAllEstimatorResults(
                '{"results":[{"metadata":{}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
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
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(json);
        System.assertEquals(2, stds.size());
        System.assertEquals(0.02, stds[0]);
        System.assertEquals(0.03, stds[1]);
    }

    @IsTest
    static void testParseAllEstimatorStdsNoStds() {
        String json = '{"results":[{"data":{"evs":[0.71]}}]}';
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(json);
        System.assertEquals(1, stds.size());
        System.assertEquals(null, stds[0]);
    }

    @IsTest
    static void testParseAllEstimatorStdsScalar() {
        String json = '{"results":[{"data":{"evs":2.45,"stds":0.05}}]}';
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(json);
        System.assertEquals(1, stds.size());
        System.assertEquals(0.05, stds[0]);
    }

    @IsTest
    static void testParseAllEstimatorStdsNoResults() {
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(
            '{"results":[]}'
        );
        System.assertEquals(0, stds.size());
    }

    @IsTest
    static void testParseAllEstimatorStdsNoData() {
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(
            '{"results":[{"metadata":{}}]}'
        );
        System.assertEquals(1, stds.size());
        System.assertEquals(null, stds[0]);
    }

    @IsTest
    static void testParseAllEstimatorStdsEmptyArray() {
        String json = '{"results":[{"data":{"evs":[0.71],"stds":[]}}]}';
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(json);
        System.assertEquals(1, stds.size());
        System.assertEquals(null, stds[0]);
    }

    // ── formatEstimatorSummary ──────────────────────────────────────

    @IsTest
    static void testFormatEstimatorSummaryPass() {
        String json = '{"results":[{"data":{"evs":[2.61],"stds":[0.04]},"metadata":{"shots":4096}}],"metadata":{"resilience":{"measure_mitigation":true,"zne_mitigation":false,"pec_mitigation":false},"twirling":{"enable_measure":true,"enable_gates":false,"strategy":"active"}}}';
        String summary = QRNGResultParser.formatEstimatorSummary(
            json,
            2.61,
            0.04
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
        String summary = QRNGResultParser.formatEstimatorSummary(
            json,
            1.5,
            0.1
        );
        System.assert(summary.contains('FAIL'), 'Should show FAIL');
    }

    @IsTest
    static void testFormatEstimatorSummaryNullStd() {
        String json = '{"results":[{"data":{"evs":[2.3]}}]}';
        String summary = QRNGResultParser.formatEstimatorSummary(
            json,
            2.3,
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
        String summary = QRNGResultParser.formatEstimatorSummary(
            'not json',
            2.5,
            0.05
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
            QRNGResultParser.parseSamplerResults(
                '{"results":[{"metadata":{}}]}',
                8
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No data'));
        }
    }

    @IsTest
    static void testParseSamplerResultsNoMeas() {
        try {
            QRNGResultParser.parseSamplerResults(
                '{"results":[{"data":{"other":"stuff"}}]}',
                8
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No measurement'));
        }
    }

    @IsTest
    static void testParseSamplerResultsNoSamples() {
        try {
            QRNGResultParser.parseSamplerResults(
                '{"results":[{"data":{"meas":{}}}]}',
                8
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No samples'));
        }
    }

    @IsTest
    static void testParseEstimatorResultNoData() {
        try {
            QRNGResultParser.parseEstimatorResult(
                '{"results":[{"metadata":{}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No data'));
        }
    }

    @IsTest
    static void testParseEstimatorResultNoEvs() {
        try {
            QRNGResultParser.parseEstimatorResult(
                '{"results":[{"data":{"stds":[0.05]}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No expectation'));
        }
    }

    @IsTest
    static void testParseEstimatorResultEmptyEvsArray() {
        try {
            QRNGResultParser.parseEstimatorResult(
                '{"results":[{"data":{"evs":[]}}]}'
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No expectation'));
        }
    }

    @IsTest
    static void testParseEstimatorStdNoResults() {
        Double std = QRNGResultParser.parseEstimatorStd('{"results":[]}');
        System.assertEquals(null, std);
    }

    @IsTest
    static void testParseEstimatorStdNoData() {
        Double std = QRNGResultParser.parseEstimatorStd(
            '{"results":[{"metadata":{}}]}'
        );
        System.assertEquals(null, std);
    }

    @IsTest
    static void testParseEstimatorStdNoStds() {
        Double std = QRNGResultParser.parseEstimatorStd(
            '{"results":[{"data":{"evs":[2.5]}}]}'
        );
        System.assertEquals(null, std);
    }

    @IsTest
    static void testParseEstimatorStdEmptyArray() {
        Double std = QRNGResultParser.parseEstimatorStd(
            '{"results":[{"data":{"evs":[2.5],"stds":[]}}]}'
        );
        System.assertEquals(null, std);
    }

    // ── vonNeumannDebias edge cases ─────────────────────────────────

    @IsTest
    static void testVonNeumannDebiasOddLength() {
        // Last bit is ignored (odd length → last bit has no pair)
        String raw = '010';
        String debiased = QRNGResultParser.vonNeumannDebias(raw);
        System.assertEquals('0', debiased);
    }

    @IsTest
    static void testVonNeumannDebiasEmpty() {
        System.assertEquals('', QRNGResultParser.vonNeumannDebias(''));
    }

    @IsTest
    static void testVonNeumannDebiasSingleBit() {
        System.assertEquals('', QRNGResultParser.vonNeumannDebias('1'));
    }

    // ── hexToBinary trimming ────────────────────────────────────────

    @IsTest
    static void testHexToBinaryTrimming() {
        // 0xff produces 8 bits, but we request only 4 qubits → trim to last 4
        String result = QRNGResultParser.hexToBinary('0xff', 4);
        System.assertEquals('1111', result);
        System.assertEquals(4, result.length());
    }

    @IsTest
    static void testHexToBinaryUpperCase() {
        System.assertEquals(
            '10101011',
            QRNGResultParser.hexToBinary('0XAB', 8)
        );
    }
}
