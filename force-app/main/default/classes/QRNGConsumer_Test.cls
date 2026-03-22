/**
 * Tests for the QRNGConsumer interface.
 * Uses a mock implementation to verify both callback methods
 * can be implemented and invoked correctly.
 */
@IsTest
private class QRNGConsumer_Test {
    /**
     * Mock implementation of QRNGConsumer that records callback invocations
     * for assertion in tests.
     */
    private class MockConsumer implements QRNGConsumer {
        public Id receivedCertificateId;
        public List<String> receivedBits;
        public Id receivedJobId;
        public String receivedError;
        public Boolean readyCalled = false;
        public Boolean failedCalled = false;

        public void onRandomnessReady(
            Id certificateId,
            List<String> randomBits
        ) {
            this.readyCalled = true;
            this.receivedCertificateId = certificateId;
            this.receivedBits = randomBits;
        }

        public void onRandomnessFailed(Id jobId, String errorMessage) {
            this.failedCalled = true;
            this.receivedJobId = jobId;
            this.receivedError = errorMessage;
        }
    }

    @IsTest
    static void testOnRandomnessReadyReceivesBitsAndCertificate() {
        MockConsumer consumer = new MockConsumer();
        // Use a syntactically valid fake Id (18-char, Account prefix for simplicity)
        Id fakeCertId = '001000000000001AAA';
        List<String> bits = new List<String>{
            '01101001',
            '11010010',
            '10110100'
        };

        Test.startTest();
        consumer.onRandomnessReady(fakeCertId, bits);
        Test.stopTest();

        System.assertEquals(
            true,
            consumer.readyCalled,
            'onRandomnessReady should have been called'
        );
        System.assertEquals(
            false,
            consumer.failedCalled,
            'onRandomnessFailed should not have been called'
        );
        System.assertEquals(
            fakeCertId,
            consumer.receivedCertificateId,
            'Certificate ID should match'
        );
        System.assertEquals(
            3,
            consumer.receivedBits.size(),
            'Should receive 3 bit strings'
        );
        System.assertEquals(
            '01101001',
            consumer.receivedBits[0],
            'First bit string should match'
        );
    }

    @IsTest
    static void testOnRandomnessReadyWithEmptyBits() {
        MockConsumer consumer = new MockConsumer();
        Id fakeCertId = '001000000000002AAA';
        List<String> emptyBits = new List<String>();

        Test.startTest();
        consumer.onRandomnessReady(fakeCertId, emptyBits);
        Test.stopTest();

        System.assertEquals(true, consumer.readyCalled);
        System.assertEquals(
            0,
            consumer.receivedBits.size(),
            'Should handle empty bit list'
        );
    }

    @IsTest
    static void testOnRandomnessReadyWithNullBits() {
        MockConsumer consumer = new MockConsumer();
        Id fakeCertId = '001000000000003AAA';

        Test.startTest();
        consumer.onRandomnessReady(fakeCertId, null);
        Test.stopTest();

        System.assertEquals(true, consumer.readyCalled);
        System.assertEquals(
            null,
            consumer.receivedBits,
            'Should handle null bit list'
        );
    }

    @IsTest
    static void testOnRandomnessFailedReceivesJobIdAndError() {
        MockConsumer consumer = new MockConsumer();
        Id fakeJobId = '001000000000004AAA';
        String errorMsg = 'IBM Quantum backend offline: ibm_brisbane';

        Test.startTest();
        consumer.onRandomnessFailed(fakeJobId, errorMsg);
        Test.stopTest();

        System.assertEquals(
            true,
            consumer.failedCalled,
            'onRandomnessFailed should have been called'
        );
        System.assertEquals(
            false,
            consumer.readyCalled,
            'onRandomnessReady should not have been called'
        );
        System.assertEquals(
            fakeJobId,
            consumer.receivedJobId,
            'Job ID should match'
        );
        System.assertEquals(
            errorMsg,
            consumer.receivedError,
            'Error message should match'
        );
    }

    @IsTest
    static void testOnRandomnessFailedWithNullError() {
        MockConsumer consumer = new MockConsumer();
        Id fakeJobId = '001000000000005AAA';

        Test.startTest();
        consumer.onRandomnessFailed(fakeJobId, null);
        Test.stopTest();

        System.assertEquals(true, consumer.failedCalled);
        System.assertEquals(
            null,
            consumer.receivedError,
            'Should handle null error message'
        );
    }

    @IsTest
    static void testConsumerCanBeReferencedPolymorphically() {
        QRNGConsumer consumer = new MockConsumer();
        Id fakeCertId = '001000000000006AAA';
        List<String> bits = new List<String>{ '10101010' };

        Test.startTest();
        consumer.onRandomnessReady(fakeCertId, bits);
        Test.stopTest();

        // Verify via cast that the mock received data
        MockConsumer mock = (MockConsumer) consumer;
        System.assertEquals(true, mock.readyCalled);
        System.assertEquals(fakeCertId, mock.receivedCertificateId);
    }

    @IsTest
    static void testBothCallbacksCanBeCalledSequentially() {
        MockConsumer consumer = new MockConsumer();
        Id fakeCertId = '001000000000007AAA';
        Id fakeJobId = '001000000000008AAA';

        Test.startTest();
        consumer.onRandomnessReady(fakeCertId, new List<String>{ '11110000' });
        consumer.onRandomnessFailed(fakeJobId, 'Timeout');
        Test.stopTest();

        System.assertEquals(
            true,
            consumer.readyCalled,
            'Both callbacks should be callable'
        );
        System.assertEquals(true, consumer.failedCalled);
        System.assertEquals(fakeJobId, consumer.receivedJobId);
        System.assertEquals('Timeout', consumer.receivedError);
    }
}
