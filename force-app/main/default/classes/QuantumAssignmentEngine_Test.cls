@IsTest
private class QuantumAssignmentEngine_Test {
    private static final List<String> RECORDS_3 = new List<String>{
        '001000000000001',
        '001000000000002',
        '001000000000003'
    };
    private static final List<String> ASSIGNEES_2 = new List<String>{
        '005000000000001',
        '005000000000002'
    };
    private static final List<String> ASSIGNEES_5 = new List<String>{
        '005000000000001',
        '005000000000002',
        '005000000000003',
        '005000000000004',
        '005000000000005'
    };

    /**
     * Convert a value to a zero-padded binary string of the given width.
     */
    private static String toBits(Long value, Integer width) {
        String bits = '';
        Long v = value;
        while (v > 0) {
            bits = String.valueOf(Math.mod(v, 2)) + bits;
            v = v / 2;
        }
        while (bits.length() < width) {
            bits = '0' + bits;
        }
        return bits;
    }

    // ── assignUniform ───────────────────────────────────────────────

    @IsTest
    static void testAssignUniformRejectionSamplingExact() {
        // 5 assignees → 3-bit blocks; values >= 5 are rejected but consumed.
        // Draw 1: '101'=5 rejected, '010'=2 accepted → assignee index 2
        // Draw 2: '111'=7 rejected, '110'=6 rejected, '000'=0 → index 0
        // Draw 3: '011'=3 accepted → index 3
        String pool = '101' + '010' + '111' + '110' + '000' + '011';

        List<Quantum_Assignment__c> assignments = QuantumAssignmentEngine.assignUniform(
            RECORDS_3,
            ASSIGNEES_5,
            pool,
            null,
            null
        );

        System.assertEquals(3, assignments.size());
        System.assertEquals(ASSIGNEES_5[2], assignments[0].Assigned_To_ID__c);
        System.assertEquals(ASSIGNEES_5[0], assignments[1].Assigned_To_ID__c);
        System.assertEquals(ASSIGNEES_5[3], assignments[2].Assigned_To_ID__c);
        // Audit trail: consumed bits include rejected blocks
        System.assertEquals('101010', assignments[0].Random_Value__c);
        System.assertEquals('111110000', assignments[1].Random_Value__c);
        System.assertEquals('011', assignments[2].Random_Value__c);
        for (Integer i = 0; i < assignments.size(); i++) {
            System.assertEquals(i, assignments[i].Assignment_Index__c);
            System.assertEquals(
                RECORDS_3[i],
                assignments[i].Assigned_Record_ID__c
            );
        }
    }

    @IsTest
    static void testAssignUniformPoolOfAllOnesExhausts() {
        // 5 assignees → every 3-bit block reads '111' = 7 >= 5, so every
        // block is rejected and the pool exhausts. The engine must throw,
        // never fall back to a biased pick.
        try {
            QuantumAssignmentEngine.assignUniform(
                RECORDS_3,
                ASSIGNEES_5,
                '111111111111',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('Insufficient random bits'),
                'Should report insufficient bits, got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testAssignUniformSingleAssigneeConsumesNoBits() {
        List<Quantum_Assignment__c> assignments = QuantumAssignmentEngine.assignUniform(
            RECORDS_3,
            new List<String>{ '005000000000009' },
            '',
            null,
            null
        );

        System.assertEquals(3, assignments.size());
        for (Quantum_Assignment__c a : assignments) {
            System.assertEquals('005000000000009', a.Assigned_To_ID__c);
            System.assertEquals('', a.Random_Value__c);
        }
    }

    @IsTest
    static void testAssignUniformTwoAssignees() {
        // 2 assignees → 1-bit blocks, never rejected
        List<Quantum_Assignment__c> assignments = QuantumAssignmentEngine.assignUniform(
            RECORDS_3,
            ASSIGNEES_2,
            '011',
            null,
            null
        );

        System.assertEquals(ASSIGNEES_2[0], assignments[0].Assigned_To_ID__c);
        System.assertEquals(ASSIGNEES_2[1], assignments[1].Assigned_To_ID__c);
        System.assertEquals(ASSIGNEES_2[1], assignments[2].Assigned_To_ID__c);
    }

    @IsTest
    static void testAssignUniformEmptyInputs() {
        try {
            QuantumAssignmentEngine.assignUniform(
                new List<String>(),
                ASSIGNEES_2,
                '0101',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No records'));
        }
        try {
            QuantumAssignmentEngine.assignUniform(
                RECORDS_3,
                new List<String>(),
                '0101',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('No assignees'));
        }
    }

    // ── assignWeighted ──────────────────────────────────────────────

    @IsTest
    static void testAssignWeightedIntegerBoundaries() {
        // Weights 70/30 → scaled 70,000,000 / 30,000,000, total 10^8,
        // block width ceil(log2(10^8)) = 27 bits. Strict '<' walk:
        //   v = 69,999,999 → index 0 (last value of first bucket)
        //   v = 70,000,000 → index 1 (first value of second bucket)
        //   v = 99,999,999 → index 1 (last value of second bucket)
        String pool =
            toBits(69999999, 27) +
            toBits(70000000, 27) +
            toBits(99999999, 27);

        List<Quantum_Assignment__c> assignments = QuantumAssignmentEngine.assignWeighted(
            RECORDS_3,
            ASSIGNEES_2,
            new List<Double>{ 70.0, 30.0 },
            pool,
            null,
            null
        );

        System.assertEquals(3, assignments.size());
        System.assertEquals(ASSIGNEES_2[0], assignments[0].Assigned_To_ID__c);
        System.assertEquals(ASSIGNEES_2[1], assignments[1].Assigned_To_ID__c);
        System.assertEquals(ASSIGNEES_2[1], assignments[2].Assigned_To_ID__c);
        System.assertEquals(
            toBits(69999999, 27),
            assignments[0].Random_Value__c
        );
    }

    @IsTest
    static void testAssignWeightedRejectionConsumesBits() {
        // First block 120,000,000 >= 10^8 is rejected; second block 5 → idx 0
        String rejected = toBits(120000000, 27);
        String accepted = toBits(5, 27);

        List<Quantum_Assignment__c> assignments = QuantumAssignmentEngine.assignWeighted(
            new List<String>{ RECORDS_3[0] },
            ASSIGNEES_2,
            new List<Double>{ 70.0, 30.0 },
            rejected + accepted,
            null,
            null
        );

        System.assertEquals(1, assignments.size());
        System.assertEquals(ASSIGNEES_2[0], assignments[0].Assigned_To_ID__c);
        System.assertEquals(
            rejected + accepted,
            assignments[0].Random_Value__c
        );
    }

    @IsTest
    static void testAssignWeightedPoolExhaustedThrows() {
        try {
            QuantumAssignmentEngine.assignWeighted(
                RECORDS_3,
                ASSIGNEES_2,
                new List<Double>{ 70.0, 30.0 },
                '0101',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('Insufficient random bits'),
                'Should report insufficient bits, got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testAssignWeightedInvalidWeights() {
        try {
            QuantumAssignmentEngine.assignWeighted(
                RECORDS_3,
                ASSIGNEES_2,
                new List<Double>{ 70.0 },
                '0101',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('match'));
        }
        try {
            QuantumAssignmentEngine.assignWeighted(
                RECORDS_3,
                ASSIGNEES_2,
                new List<Double>{ 70.0, -1.0 },
                '0101',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('positive'));
        }
    }

    // ── selectSubset ────────────────────────────────────────────────

    @IsTest
    static void testSelectSubsetExactShuffle() {
        // Records [A,B,C,D], sample 2. Fisher-Yates descending:
        //   i=3 (m=4, 2-bit): '10'=2 → j=2, swap → [A,B,D,C]
        //   i=2 (m=3, 2-bit): '11'=3 rejected, '01'=1 → j=1 → [A,D,B,C]
        //   i=1 (m=2, 1-bit): '1'=1 → j=1, self-swap → [A,D,B,C]
        List<String> records = new List<String>{ 'A', 'B', 'C', 'D' };
        String pool = '10' + '11' + '01' + '1';

        List<Quantum_Assignment__c> assignments = QuantumAssignmentEngine.selectSubset(
            records,
            2,
            pool,
            null,
            null
        );

        System.assertEquals(2, assignments.size());
        System.assertEquals('A', assignments[0].Assigned_Record_ID__c);
        System.assertEquals('D', assignments[1].Assigned_Record_ID__c);
        // A was never displaced; D was placed at position 1 by the
        // i=2 draw whose consumed bits were '1101' then re-confirmed by
        // the i=1 self-swap ('1')
        System.assertEquals('', assignments[0].Random_Value__c);
        System.assertEquals('1', assignments[1].Random_Value__c);
        System.assertEquals(null, assignments[0].Assigned_To_ID__c);
    }

    @IsTest
    static void testSelectSubsetDeterministic() {
        List<String> records = new List<String>{
            'R1',
            'R2',
            'R3',
            'R4',
            'R5',
            'R6'
        };
        String pool = '011010011100010101101001110001010110';

        List<Quantum_Assignment__c> first = QuantumAssignmentEngine.selectSubset(
            records,
            3,
            pool,
            null,
            null
        );
        List<Quantum_Assignment__c> second = QuantumAssignmentEngine.selectSubset(
            records,
            3,
            pool,
            null,
            null
        );

        System.assertEquals(first.size(), second.size());
        for (Integer i = 0; i < first.size(); i++) {
            System.assertEquals(
                first[i].Assigned_Record_ID__c,
                second[i].Assigned_Record_ID__c,
                'Same pool must produce the same subset'
            );
            System.assertEquals(
                first[i].Random_Value__c,
                second[i].Random_Value__c,
                'Same pool must produce the same audit bits'
            );
        }
    }

    @IsTest
    static void testSelectSubsetPoolExhaustedThrows() {
        // Every 2-bit block reads '11' = 3 >= m, rejected until exhaustion
        try {
            QuantumAssignmentEngine.selectSubset(
                new List<String>{ 'A', 'B', 'C', 'D' },
                2,
                '111111',
                null,
                null
            );
            System.assert(false, 'Should have thrown');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('Insufficient random bits'),
                'Should report insufficient bits, got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testSelectSubsetTooLarge() {
        try {
            QuantumAssignmentEngine.selectSubset(
                new List<String>{ '001000000000001' },
                5,
                '01101001',
                null,
                null
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(
                e.getMessage().contains('exceeds'),
                'Should mention size exceeds'
            );
        }
    }

    @IsTest
    static void testSelectSubsetInvalidSampleSize() {
        try {
            QuantumAssignmentEngine.selectSubset(
                new List<String>{ 'A', 'B' },
                0,
                '0101',
                null,
                null
            );
            System.assert(false, 'Should throw');
        } catch (QuantumException e) {
            System.assert(e.getMessage().contains('positive'));
        }
    }

    // ── helpers ─────────────────────────────────────────────────────

    @IsTest
    static void testCeilLog2() {
        System.assertEquals(1, QuantumAssignmentEngine.ceilLog2(1));
        System.assertEquals(1, QuantumAssignmentEngine.ceilLog2(2));
        System.assertEquals(2, QuantumAssignmentEngine.ceilLog2(3));
        System.assertEquals(2, QuantumAssignmentEngine.ceilLog2(4));
        System.assertEquals(3, QuantumAssignmentEngine.ceilLog2(5));
        System.assertEquals(3, QuantumAssignmentEngine.ceilLog2(8));
        System.assertEquals(4, QuantumAssignmentEngine.ceilLog2(9));
    }

    @IsTest
    static void testCeilLog2Long() {
        System.assertEquals(1, QuantumAssignmentEngine.ceilLog2Long(1));
        System.assertEquals(1, QuantumAssignmentEngine.ceilLog2Long(2));
        System.assertEquals(
            27,
            QuantumAssignmentEngine.ceilLog2Long(100000000)
        );
        System.assertEquals(26, QuantumAssignmentEngine.ceilLog2Long(67108864));
    }

    @IsTest
    static void testBitsToLong() {
        System.assertEquals((Long) 0, QuantumAssignmentEngine.bitsToLong('0'));
        System.assertEquals(
            (Long) 5,
            QuantumAssignmentEngine.bitsToLong('101')
        );
        System.assertEquals(
            (Long) 100000000,
            QuantumAssignmentEngine.bitsToLong(toBits(100000000, 27))
        );
    }
}
