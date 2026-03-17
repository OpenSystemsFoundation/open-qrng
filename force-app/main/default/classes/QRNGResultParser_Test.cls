@IsTest
private class QRNGResultParser_Test {
    @IsTest
    static void testParseSamplerResults() {
        String json = '{"results":[{"data":{"meas":{"samples":["0110","1001","1110","0011"]}}}]}';
        List<String> bitstrings = QRNGResultParser.parseSamplerResults(json);
        System.assertEquals(4, bitstrings.size());
        System.assertEquals('0110', bitstrings[0]);
        System.assertEquals('0011', bitstrings[3]);
    }

    @IsTest
    static void testParseSamplerResultsNoResults() {
        try {
            QRNGResultParser.parseSamplerResults('{"results":[]}');
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('No results'),
                'Should indicate no results'
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
