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
}
