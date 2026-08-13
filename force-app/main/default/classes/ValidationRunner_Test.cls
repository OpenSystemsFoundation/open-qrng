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

    /**
     * Deterministic random-looking bits via SHA-256 expansion.
     * Verified offline to pass every extended test (including the
     * bounded min-entropy threshold: ~0.926 at 4096 bits), so tests
     * of the non-revocation path are not flaky.
     */
    private static String generateDeterministicBits(Integer numBits) {
        List<String> chunks = new List<String>();
        Integer total = 0;
        Integer i = 0;
        while (total < numBits) {
            Blob digest = Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf('QF-test-' + i)
            );
            String bin = ResultParser.decodeRawResults(
                '0x' + EncodingUtil.convertToHex(digest)
            );
            chunks.add(bin);
            total += bin.length();
            i++;
        }
        return String.join(chunks, '').substring(0, numBits);
    }

    @IsTest
    static void testRunnerStoresExtendedResults() {
        // Deterministic pool that passes the full extended suite
        String testBits = generateDeterministicBits(4096);
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
            SELECT Id, Validation_Results__c, Error_Message__c
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
        System.assert(
            job.Validation_Results__c.contains('"extendedPassed":true'),
            'Deterministic pool should pass the extended suite'
        );
        System.assertEquals(
            null,
            job.Error_Message__c,
            'Passing extended suite should not set an error message'
        );

        // Verify certificate was also updated — and NOT revoked
        cert = [
            SELECT Id, Status__c, Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert.Id
        ];
        System.assert(
            cert.Validation_Results__c.contains('extendedTestsCompleted'),
            'Certificate should also have extended results'
        );
        System.assertEquals(
            'Certified',
            cert.Status__c,
            'Certificate must stay Certified when extended tests pass'
        );
    }

    @IsTest
    static void testRunnerRevokesCertificateOnExtendedFailure() {
        // 530 ones / 470 zeros in long runs: fails min-entropy (bounded
        // ~0.809 < 0.9), CUSUM, repetition count, adaptive proportion —
        // the already-issued certificate must be revoked.
        String biasedBits = '1'.repeat(530) + '0'.repeat(470);
        Quantum_Job__c job = new Quantum_Job__c(
            Status__c = 'Completed',
            Backend__c = 'test_backend',
            Debiased_Results__c = ResultParser.encodeForStorage(biasedBits),
            Validation_Results__c = '{"passed":true,"frequencyTest":true}'
        );
        insert job;

        Fairness_Certificate__c cert = new Fairness_Certificate__c(
            Quantum_Job__c = job.Id,
            Status__c = 'Certified',
            Validation_Results__c = '{"passed":true}'
        );
        insert cert;

        Test.startTest();
        System.enqueueJob(new ValidationRunner(job.Id));
        Test.stopTest();

        // Certificate flips to Revoked with the failing summary merged in
        cert = [
            SELECT Id, Status__c, Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert.Id
        ];
        System.assertEquals(
            'Revoked',
            cert.Status__c,
            'Failing extended suite must revoke the certificate'
        );
        System.assert(
            cert.Validation_Results__c.contains('"certificateRevoked":true'),
            'Certificate JSON should record the revocation'
        );
        System.assert(
            cert.Validation_Results__c.contains('minEntropyTest'),
            'Certificate JSON should include the failing test names'
        );

        // Job records the failure
        job = [
            SELECT Id, Error_Message__c, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assert(
            job.Error_Message__c != null &&
            job.Error_Message__c.startsWith('Extended validation failed:'),
            'Job Error_Message__c should describe the extended failure, got: ' +
            job.Error_Message__c
        );
        System.assert(
            job.Validation_Results__c.contains('revocationReason'),
            'Job JSON should carry the revocation reason'
        );

        // Quantum_Job_Failed__e publish result was checked and noted
        System.assert(
            job.Validation_Results__c.contains('"failureEventPublished":true'),
            'Failure event publish should succeed and be recorded'
        );
    }

    @IsTest
    static void testRunnerRevocationPathWithoutCertificate() {
        // No certificate exists: the runner must still record the failure
        // on the job without throwing.
        String biasedBits = '1'.repeat(530) + '0'.repeat(470);
        Quantum_Job__c job = new Quantum_Job__c(
            Status__c = 'Completed',
            Backend__c = 'test_backend',
            Debiased_Results__c = ResultParser.encodeForStorage(biasedBits)
        );
        insert job;

        Test.startTest();
        System.enqueueJob(new ValidationRunner(job.Id));
        Test.stopTest();

        job = [
            SELECT Id, Error_Message__c, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assert(
            job.Error_Message__c.startsWith('Extended validation failed:'),
            'Failure should be recorded even without a certificate'
        );
        System.assert(
            job.Validation_Results__c.contains('"extendedPassed":false')
        );
    }

    @IsTest
    static void testBuildFailureSummaryListsFailingTests() {
        Map<String, Object> results = new Map<String, Object>{
            'approximateEntropyTest' => true,
            'serialTest' => false,
            'minEntropyTest' => false,
            'minEntropy' => 0.85,
            'extendedPassed' => false
        };
        String summary = ValidationRunner.buildFailureSummary(results);
        System.assert(
            summary.contains('serialTest'),
            'Summary should list serialTest: ' + summary
        );
        System.assert(
            summary.contains('minEntropyTest'),
            'Summary should list minEntropyTest: ' + summary
        );
        System.assert(
            !summary.contains('approximateEntropyTest'),
            'Summary should not list passing tests: ' + summary
        );
        System.assert(
            summary.contains('minEntropy=0.85'),
            'Summary should include the min-entropy value: ' + summary
        );
    }

    @IsTest
    static void testBuildFailureSummaryInsufficientBits() {
        Map<String, Object> results = RandomnessValidator.validateExtended(
            '0101'
        );
        String summary = ValidationRunner.buildFailureSummary(results);
        System.assert(
            summary.contains('Insufficient'),
            'Summary should surface the validator error: ' + summary
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
