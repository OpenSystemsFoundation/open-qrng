/**
 * Monthly compliance summary job.
 * Creates one MONTHLY_SUMMARY event record with aggregate statistics.
 * Scheduled to run on the 1st of each month.
 * Governor budget: ~5 SOQL, 1 DML.
 */
public with sharing class ComplianceSummaryJob implements Schedulable {
    public void execute(SchedulableContext ctx) {
        // Calculate previous month date range
        Date today = Date.today();
        Date firstOfThisMonth = Date.newInstance(
            today.year(),
            today.month(),
            1
        );
        Date firstOfLastMonth = firstOfThisMonth.addMonths(-1);
        DateTime startDT = DateTime.newInstance(
            firstOfLastMonth,
            Time.newInstance(0, 0, 0, 0)
        );
        DateTime endDT = DateTime.newInstance(
            firstOfThisMonth,
            Time.newInstance(0, 0, 0, 0)
        );

        // Aggregate queries
        Integer certCount = [
            SELECT COUNT()
            FROM Fairness_Certificate__c
            WHERE CreatedDate >= :startDT AND CreatedDate < :endDT
        ];
        Integer jobCount = [
            SELECT COUNT()
            FROM Quantum_Job__c
            WHERE CreatedDate >= :startDT AND CreatedDate < :endDT
        ];
        Integer assignmentCount = [
            SELECT COUNT()
            FROM QRNG_Assignment__c
            WHERE CreatedDate >= :startDT AND CreatedDate < :endDT
        ];
        Integer tamperedCount = [
            SELECT COUNT()
            FROM Fairness_Certificate__c
            WHERE
                Tampered__c = TRUE
                AND CreatedDate >= :startDT
                AND CreatedDate < :endDT
        ];
        Integer anomalyCount = [
            SELECT COUNT()
            FROM Compliance_Event__c
            WHERE
                CreatedDate >= :startDT
                AND CreatedDate < :endDT
                AND Event_Type__c != 'MONTHLY_SUMMARY'
        ];

        // Check chain integrity
        List<Fairness_Certificate__c> chainHead = [
            SELECT Chain_Hash__c, Chain_Position__c
            FROM Fairness_Certificate__c
            WHERE Chain_Hash__c != NULL
            ORDER BY Chain_Position__c DESC
            LIMIT 1
        ];

        Map<String, Object> summary = new Map<String, Object>{
            'month' => firstOfLastMonth.format(),
            'totalJobs' => jobCount,
            'totalCertificates' => certCount,
            'totalAssignments' => assignmentCount,
            'tamperedCertificates' => tamperedCount,
            'anomalyEvents' => anomalyCount,
            'chainIntact' => tamperedCount == 0,
            'chainHeadPosition' => !chainHead.isEmpty()
                ? chainHead[0].Chain_Position__c
                : 0,
            'chainHeadHash' => !chainHead.isEmpty()
                ? chainHead[0].Chain_Hash__c
                : null
        };

        ComplianceEventLogger.log(
            'MONTHLY_SUMMARY',
            'INFO',
            null,
            null,
            summary
        );
    }
}
