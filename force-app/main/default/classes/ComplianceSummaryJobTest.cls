@IsTest
private class ComplianceSummaryJobTest {
    @TestSetup
    static void setup() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_summary_test',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 4,
            Num_Qubits__c = 4,
            Raw_Results__c = '0x69e3',
            Debiased_Results__c = '0x5',
            Submitted_At__c = DateTime.now().addMinutes(-10),
            Completed_At__c = DateTime.now()
        );
        insert job;

        String rawHash = FairnessCertificateService.computeSHA256('0x69e3');
        String debiasedHash = FairnessCertificateService.computeSHA256('0x5');
        Fairness_Certificate__c cert = new Fairness_Certificate__c(
            Quantum_Job__c = job.Id,
            External_Job_ID__c = 'job_summary_test',
            Backend__c = 'test_backend',
            Raw_Bitstring_Hash__c = rawHash,
            Debiased_Bitstring_Hash__c = debiasedHash,
            Status__c = 'Certified',
            Purpose__c = 'Summary test',
            Chain_Hash__c = rawHash,
            Chain_Position__c = 1
        );
        insert cert;
    }

    @IsTest
    static void testMonthlySummaryCreation() {
        Test.startTest();
        ComplianceSummaryJob summaryJob = new ComplianceSummaryJob();
        summaryJob.execute(null);
        Test.stopTest();

        List<Compliance_Event__c> events = [
            SELECT Event_Type__c, Severity__c, Detail__c, Detail_Hash__c
            FROM Compliance_Event__c
            WHERE Event_Type__c = 'MONTHLY_SUMMARY'
        ];
        System.assertEquals(
            1,
            events.size(),
            'Should create one MONTHLY_SUMMARY event'
        );

        Compliance_Event__c evt = events[0];
        System.assertEquals(
            'INFO',
            evt.Severity__c,
            'Summary severity should be INFO'
        );
        System.assertNotEquals(
            null,
            evt.Detail__c,
            'Summary should have detail JSON'
        );
        System.assertNotEquals(
            null,
            evt.Detail_Hash__c,
            'Summary should have detail hash'
        );

        // Verify the detail JSON contains expected keys
        Map<String, Object> detail = (Map<String, Object>) JSON.deserializeUntyped(
            evt.Detail__c
        );
        System.assert(
            detail.containsKey('month'),
            'Detail should contain month'
        );
        System.assert(
            detail.containsKey('totalJobs'),
            'Detail should contain totalJobs'
        );
        System.assert(
            detail.containsKey('totalCertificates'),
            'Detail should contain totalCertificates'
        );
        System.assert(
            detail.containsKey('totalAssignments'),
            'Detail should contain totalAssignments'
        );
        System.assert(
            detail.containsKey('tamperedCertificates'),
            'Detail should contain tamperedCertificates'
        );
        System.assert(
            detail.containsKey('anomalyEvents'),
            'Detail should contain anomalyEvents'
        );
        System.assert(
            detail.containsKey('chainIntact'),
            'Detail should contain chainIntact'
        );
        System.assertEquals(
            true,
            detail.get('chainIntact'),
            'Chain should be intact when no tampered certs'
        );
    }

    @IsTest
    static void testMonthlySummaryWithNoData() {
        // Delete all test data to simulate empty month
        delete [SELECT Id FROM Fairness_Certificate__c];
        delete [SELECT Id FROM Quantum_Job__c];

        Test.startTest();
        ComplianceSummaryJob summaryJob = new ComplianceSummaryJob();
        summaryJob.execute(null);
        Test.stopTest();

        List<Compliance_Event__c> events = [
            SELECT Detail__c
            FROM Compliance_Event__c
            WHERE Event_Type__c = 'MONTHLY_SUMMARY'
        ];
        System.assertEquals(
            1,
            events.size(),
            'Should still create summary even with no data'
        );

        Map<String, Object> detail = (Map<String, Object>) JSON.deserializeUntyped(
            events[0].Detail__c
        );
        System.assertEquals(
            0,
            detail.get('totalJobs'),
            'totalJobs should be 0'
        );
        System.assertEquals(
            0,
            detail.get('totalCertificates'),
            'totalCertificates should be 0'
        );
    }
}
