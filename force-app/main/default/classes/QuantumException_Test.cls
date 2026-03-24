/**
 * Tests for QuantumException custom exception class.
 * Validates all standard Exception construction patterns work correctly.
 */
@IsTest
private class QuantumException_Test {
    @IsTest
    static void testConstructWithMessage() {
        String msg = 'IBM Quantum backend ibm_brisbane is offline';

        Test.startTest();
        QuantumException ex = new QuantumException(msg);
        Test.stopTest();

        System.assertEquals(
            msg,
            ex.getMessage(),
            'Exception message should match'
        );
    }

    @IsTest
    static void testConstructWithCause() {
        Exception cause = new DmlException();
        cause.setMessage('Insert failed');

        Test.startTest();
        QuantumException ex = new QuantumException(
            'Job record creation failed',
            cause
        );
        Test.stopTest();

        System.assertEquals(
            'Job record creation failed',
            ex.getMessage(),
            'Exception message should match'
        );
        System.assertNotEquals(null, ex.getCause(), 'Cause should be set');
    }

    @IsTest
    static void testThrowAndCatch() {
        Boolean caught = false;
        String caughtMessage;

        Test.startTest();
        try {
            throw new QuantumException('Circuit submission timeout');
        } catch (QuantumException ex) {
            caught = true;
            caughtMessage = ex.getMessage();
        }
        Test.stopTest();

        System.assertEquals(
            true,
            caught,
            'QuantumException should be catchable'
        );
        System.assertEquals(
            'Circuit submission timeout',
            caughtMessage,
            'Caught message should match thrown message'
        );
    }

    @IsTest
    static void testIsInstanceOfQuantumException() {
        Exception ex = new QuantumException('test');

        System.assert(
            ex instanceof QuantumException,
            'Should be instanceof QuantumException'
        );
    }

    @IsTest
    static void testEmptyMessage() {
        QuantumException ex = new QuantumException('');

        System.assertEquals('', ex.getMessage(), 'Should handle empty message');
    }

    @IsTest
    static void testChainedExceptions() {
        QuantumException cause = new QuantumException('Token expired');
        QuantumException wrapper = new QuantumException('Auth failed', cause);

        System.assertEquals('Auth failed', wrapper.getMessage());
        System.assertEquals('Token expired', wrapper.getCause().getMessage());
        System.assert(wrapper.getCause() instanceof QuantumException);
    }

    @IsTest
    static void testGetTypeName() {
        QuantumException ex = new QuantumException('test');

        // In managed package context, type name includes namespace prefix
        System.assert(
            ex.getTypeName().contains('QuantumException'),
            'Type name should contain QuantumException, got: ' +
            ex.getTypeName()
        );
    }

    @IsTest
    static void testStackTraceIsPopulated() {
        QuantumException ex;
        try {
            throw new QuantumException('stack trace test');
        } catch (QuantumException caught) {
            ex = caught;
        }

        System.assertNotEquals(
            null,
            ex.getStackTraceString(),
            'Stack trace should be populated after throw'
        );
    }

    @IsTest
    static void testCatchAsBaseException() {
        Boolean caught = false;

        try {
            throw new QuantumException('Polymorphic catch');
        } catch (Exception ex) {
            caught = true;
            System.assert(
                ex instanceof QuantumException,
                'Should be catchable as base Exception'
            );
        }

        System.assertEquals(
            true,
            caught,
            'Should be caught by base Exception handler'
        );
    }
}
