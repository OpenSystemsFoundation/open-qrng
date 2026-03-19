/**
 * Service for querying compliance control-to-framework mappings.
 * Reads from Compliance_Control__mdt custom metadata.
 * No DML, no callouts, no governor limit concerns.
 */
public with sharing class ComplianceControlService {
    public static List<Compliance_Control__mdt> getControlsForFramework(
        String framework
    ) {
        return [
            SELECT
                Control_Key__c,
                Framework__c,
                Framework_Reference__c,
                Control_Description__c,
                Evidence_Type__c
            FROM Compliance_Control__mdt
            WHERE Framework__c = :framework
            ORDER BY Control_Key__c
        ];
    }

    public static List<Compliance_Control__mdt> getFrameworksForControl(
        String controlKey
    ) {
        return [
            SELECT
                Control_Key__c,
                Framework__c,
                Framework_Reference__c,
                Control_Description__c,
                Evidence_Type__c
            FROM Compliance_Control__mdt
            WHERE Control_Key__c = :controlKey
            ORDER BY Framework__c
        ];
    }

    public static List<Compliance_Control__mdt> getFullMatrix() {
        return [
            SELECT
                Control_Key__c,
                Framework__c,
                Framework_Reference__c,
                Control_Description__c,
                Evidence_Type__c
            FROM Compliance_Control__mdt
            ORDER BY Control_Key__c, Framework__c
        ];
    }
}
