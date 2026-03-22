/**
 * Tests for QRNGException custom exception class.
 * Validates all standard Exception construction patterns work correctly.
 */
@IsTest
private class QRNGException_Test {
    @IsTest
    static void testConstructWithMessage() {
        String msg = 'IBM Quantum backend ibm_brisbane is offline';

        Test.startTest();
        QRNGException ex = new QRNGException(msg);
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
        QRNGException ex = new QRNGException(
            'Job record creation failed',
            cause
        );
        Test.stopTest();

        System.assertEquals(
            'Job record creation failed',
            ex.getMessage(),
            'Exception message should match'
        );
        System.assertNotEquals(
            null,
            ex.getCause(),
            'Cause should be set'
        );
    }

    @IsTest
    static void testThrowAndCatch() {
        Boolean caught = false;
        String caughtMessage;

        Test.startTest();
        try {
            throw new QRNGException('Circuit submission timeout');
        } catch (QRNGException ex) {
            caught = true;
            caughtMessage = ex.getMessage();
        }
        Test.stopTest();

        System.assertEquals(true, caught, 'QRNGException should be catchable');
        System.assertEquals(
            'Circuit submission timeout',
            caughtMessage,
            'Caught message should match thrown message'
        );
    }

    @IsTest
    static void testIsInstanceOfQRNGException() {
        Exception ex = new QRNGException('test');

        System.assert(
            ex instanceof QRNGException,
            'Should be instanceof QRNGException'
        );
    }

    @IsTest
    static void testEmptyMessage() {
        QRNGException ex = new QRNGException('');

        System.assertEquals(
            '',
            ex.getMessage(),
            'Should handle empty message'
        );
    }

    @IsTest
    static void testChainedExceptions() {
        QRNGException cause = new QRNGException('Token expired');
        QRNGException wrapper = new QRNGException('Auth failed', cause);

        System.assertEquals('Auth failed', wrapper.getMessage());
        System.assertEquals('Token expired', wrapper.getCause().getMessage());
        System.assert(wrapper.getCause() instanceof QRNGException);
    }

    @IsTest
    static void testGetTypeName() {
        QRNGException ex = new QRNGException('test');

        // In managed package context, type name includes namespace prefix
        System.assert(
            ex.getTypeName().contains('QRNGException'),
            'Type name should contain QRNGException, got: ' + ex.getTypeName()
        );
    }

    @IsTest
    static void testStackTraceIsPopulated() {
        QRNGException ex;
        try {
            throw new QRNGException('stack trace test');
        } catch (QRNGException caught) {
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
            throw new QRNGException('Polymorphic catch');
        } catch (Exception ex) {
            caught = true;
            System.assert(
                ex instanceof QRNGException,
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
