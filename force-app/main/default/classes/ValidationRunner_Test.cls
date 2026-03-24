@IsTest
private class ValidationRunner_Test {
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
    static void testRunnerStoresExtendedResults() {
        String testBits = generateTestBits(2000);
        String encodedBits = ResultParser.encodeForStorage(testBits);

        Quantum_Job__c job = new Quantum_Job__c(
            Status__c = 'Completed',
            Backend__c = 'test_backend',
            Debiased_Results__c = encodedBits,
            Validation_Results__c = '{"passed":true,"frequencyTest":true}'
        );
        insert job;

        // Create a certificate for the job
        Fairness_Certificate__c cert = new Fairness_Certificate__c(
            Quantum_Job__c = job.Id,
            Status__c = 'Certified',
            Validation_Results__c = '{"passed":true}'
        );
        insert cert;

        Test.startTest();
        System.enqueueJob(new ValidationRunner(job.Id));
        Test.stopTest();

        // Verify job was updated with extended results
        job = [
            SELECT Id, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assert(
            job.Validation_Results__c.contains('extendedTestsCompleted'),
            'Should contain extended tests completed flag'
        );
        System.assert(
            job.Validation_Results__c.contains('approximateEntropyTest'),
            'Should contain approximate entropy result'
        );
        System.assert(
            job.Validation_Results__c.contains('serialTest'),
            'Should contain serial test result'
        );
        System.assert(
            job.Validation_Results__c.contains('cumulativeSumsTest'),
            'Should contain CUSUM result'
        );
        System.assert(
            job.Validation_Results__c.contains('longestRunOfOnesTest'),
            'Should contain longest run result'
        );

        // Verify certificate was also updated
        cert = [
            SELECT Id, Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert.Id
        ];
        System.assert(
            cert.Validation_Results__c.contains('extendedTestsCompleted'),
            'Certificate should also have extended results'
        );
    }

    @IsTest
    static void testRunnerHandlesNullBits() {
        Quantum_Job__c job = new Quantum_Job__c(
            Status__c = 'Completed',
            Backend__c = 'test_backend'
        );
        insert job;

        Test.startTest();
        System.enqueueJob(new ValidationRunner(job.Id));
        Test.stopTest();

        // Should not throw, should just return
        job = [
            SELECT Id, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            null,
            job.Validation_Results__c,
            'Should not update when no bits available'
        );
    }

    // Extended test unit tests
    @IsTest
    static void testApproximateEntropyTest() {
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.approximateEntropyTest(bits, 2);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testSerialTest() {
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.serialTest(bits, 3);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testCumulativeSumsTest() {
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.cumulativeSumsTest(bits);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testCumulativeSumsTestBiased() {
        // Heavily biased: should fail CUSUM (trending)
        String bits = '';
        for (Integer i = 0; i < 500; i++) {
            bits += '1';
        }
        for (Integer i = 0; i < 500; i++) {
            bits += '0';
        }
        Boolean result = RandomnessValidator.cumulativeSumsTest(bits);
        System.assertEquals(false, result, 'Biased drift should fail CUSUM');
    }

    @IsTest
    static void testLongestRunOfOnesTest() {
        String bits = generateTestBits(1000);
        Boolean result = RandomnessValidator.longestRunOfOnesTest(bits);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testValidateExtended() {
        String bits = generateTestBits(2000);
        Map<String, Object> results = RandomnessValidator.validateExtended(
            bits
        );
        System.assert(
            results.containsKey('extendedPassed'),
            'Should contain extendedPassed'
        );
        System.assert(
            results.containsKey('approximateEntropyTest'),
            'Should contain approx entropy'
        );
        System.assert(
            results.containsKey('serialTest'),
            'Should contain serial'
        );
        System.assert(
            results.containsKey('cumulativeSumsTest'),
            'Should contain CUSUM'
        );
        System.assert(
            results.containsKey('longestRunOfOnesTest'),
            'Should contain longest run'
        );
    }

    @IsTest
    static void testValidateExtendedInsufficientBits() {
        Map<String, Object> results = RandomnessValidator.validateExtended(
            '01010'
        );
        System.assertEquals(
            false,
            results.get('extendedPassed'),
            'Should fail with insufficient bits'
        );
    }

    @IsTest
    static void testShortBitstringsPassByDefault() {
        // Tests on very short bitstrings should pass by default
        System.assertEquals(
            true,
            RandomnessValidator.approximateEntropyTest('01010101', 2)
        );
        System.assertEquals(
            true,
            RandomnessValidator.serialTest('01010101', 3)
        );
        System.assertEquals(
            true,
            RandomnessValidator.cumulativeSumsTest('01010101')
        );
        System.assertEquals(
            true,
            RandomnessValidator.longestRunOfOnesTest('01010101')
        );
    }
}
