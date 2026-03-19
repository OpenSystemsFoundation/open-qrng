/**
 * Utility for logging compliance events (exceptions and anomalies only).
 * Normal operations are audited via fields on existing objects.
 * Governor budget: 1 DML per log call, 0 SOQL.
 */
public with sharing class ComplianceEventLogger {
    public static void log(
        String eventType,
        String severity,
        Id relatedCertId,
        Id relatedJobId,
        Map<String, Object> detail
    ) {
        Compliance_Event__c evt = new Compliance_Event__c();
        evt.Event_Type__c = eventType;
        evt.Severity__c = severity;
        evt.Actor__c = UserInfo.getUserId();
        evt.Related_Certificate__c = relatedCertId;
        evt.Related_Job__c = relatedJobId;

        if (detail != null && !detail.isEmpty()) {
            String detailJson = JSON.serialize(detail);
            evt.Detail__c = detailJson;
            evt.Detail_Hash__c = FairnessCertificateService.computeSHA256(
                detailJson
            );
        }

        insert evt;
    }

    public static void logBulk(List<Compliance_Event__c> events) {
        for (Compliance_Event__c evt : events) {
            if (evt.Detail__c != null && evt.Detail_Hash__c == null) {
                evt.Detail_Hash__c = FairnessCertificateService.computeSHA256(
                    evt.Detail__c
                );
            }
            if (evt.Actor__c == null) {
                evt.Actor__c = UserInfo.getUserId();
            }
        }
        insert events;
    }
}
