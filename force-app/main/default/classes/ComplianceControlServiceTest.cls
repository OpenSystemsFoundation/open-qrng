/**
 * Tests for ComplianceControlService.
 * Custom metadata records are available in tests without @TestSetup,
 * so these tests query the actual seed records deployed with the package.
 */
@IsTest
private class ComplianceControlServiceTest {
    @IsTest
    static void getControlsForFramework_returnsRecordsForKnownFramework() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getControlsForFramework(
            'ISO_27001'
        );

        System.assertNotEquals(
            0,
            results.size(),
            'Expected at least one ISO_27001 control mapping'
        );
        for (Compliance_Control__mdt ctrl : results) {
            System.assertEquals(
                'ISO_27001',
                ctrl.Framework__c,
                'All returned records should match the requested framework'
            );
        }
    }

    @IsTest
    static void getControlsForFramework_returnsEmptyForUnknownFramework() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getControlsForFramework(
            'NONEXISTENT_FRAMEWORK'
        );

        System.assertEquals(
            0,
            results.size(),
            'Unknown framework should return no records'
        );
    }

    @IsTest
    static void getFrameworksForControl_returnsRecordsForKnownControl() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getFrameworksForControl(
            'HASH_CHAIN'
        );

        System.assertNotEquals(
            0,
            results.size(),
            'Expected at least one framework mapping for HASH_CHAIN'
        );
        for (Compliance_Control__mdt ctrl : results) {
            System.assertEquals(
                'HASH_CHAIN',
                ctrl.Control_Key__c,
                'All returned records should match the requested control key'
            );
        }
    }

    @IsTest
    static void getFrameworksForControl_returnsEmptyForUnknownControl() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getFrameworksForControl(
            'NONEXISTENT_CONTROL'
        );

        System.assertEquals(
            0,
            results.size(),
            'Unknown control key should return no records'
        );
    }

    @IsTest
    static void getFullMatrix_returnsAllRecords() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getFullMatrix();

        System.assertNotEquals(
            0,
            results.size(),
            'Full matrix should return all seed records'
        );
    }

    @IsTest
    static void getFullMatrix_isSortedByControlKeyThenFramework() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getFullMatrix();

        String previousKey = '';
        String previousFramework = '';
        for (Compliance_Control__mdt ctrl : results) {
            if (ctrl.Control_Key__c == previousKey) {
                System.assert(
                    ctrl.Framework__c >= previousFramework,
                    'Records with same Control_Key__c should be sorted by Framework__c'
                );
            }
            previousKey = ctrl.Control_Key__c;
            previousFramework = ctrl.Framework__c;
        }
    }

    @IsTest
    static void allRecords_haveRequiredFieldsPopulated() {
        List<Compliance_Control__mdt> results = ComplianceControlService.getFullMatrix();

        for (Compliance_Control__mdt ctrl : results) {
            System.assertNotEquals(
                null,
                ctrl.Control_Key__c,
                'Control_Key__c should not be null'
            );
            System.assertNotEquals(
                null,
                ctrl.Framework__c,
                'Framework__c should not be null'
            );
            System.assertNotEquals(
                null,
                ctrl.Framework_Reference__c,
                'Framework_Reference__c should not be null'
            );
        }
    }
}
