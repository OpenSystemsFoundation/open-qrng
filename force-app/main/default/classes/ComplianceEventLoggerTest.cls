@IsTest
private class ComplianceEventLoggerTest {
    @TestSetup
    static void setup() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_compliance_test',
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
            External_Job_ID__c = 'job_compliance_test',
            Backend__c = 'test_backend',
            Raw_Bitstring_Hash__c = rawHash,
            Debiased_Bitstring_Hash__c = debiasedHash,
            Status__c = 'Certified',
            Purpose__c = 'Compliance test'
        );
        insert cert;
    }

    @IsTest
    static void testLogSingleEvent() {
        Fairness_Certificate__c cert = [
            SELECT Id
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c LIMIT 1];

        Map<String, Object> detail = new Map<String, Object>{
            'expectedHash' => 'abc123',
            'actualHash' => 'def456'
        };

        Test.startTest();
        ComplianceEventLogger.log(
            'TAMPER_DETECTED',
            'CRITICAL',
            cert.Id,
            job.Id,
            detail
        );
        Test.stopTest();

        List<Compliance_Event__c> events = [
            SELECT
                Event_Type__c,
                Severity__c,
                Actor__c,
                Related_Certificate__c,
                Related_Job__c,
                Detail__c,
                Detail_Hash__c
            FROM Compliance_Event__c
        ];
        System.assertEquals(1, events.size(), 'Should create one event');

        Compliance_Event__c evt = events[0];
        System.assertEquals(
            'TAMPER_DETECTED',
            evt.Event_Type__c,
            'Event type should match'
        );
        System.assertEquals(
            'CRITICAL',
            evt.Severity__c,
            'Severity should match'
        );
        System.assertEquals(
            UserInfo.getUserId(),
            evt.Actor__c,
            'Actor should be current user'
        );
        System.assertEquals(
            cert.Id,
            evt.Related_Certificate__c,
            'Related certificate should match'
        );
        System.assertEquals(
            job.Id,
            evt.Related_Job__c,
            'Related job should match'
        );
        System.assertNotEquals(
            null,
            evt.Detail__c,
            'Detail should be populated'
        );
        System.assertNotEquals(
            null,
            evt.Detail_Hash__c,
            'Detail hash should be computed'
        );
        System.assertEquals(
            64,
            evt.Detail_Hash__c.length(),
            'Detail hash should be 64-char SHA-256 hex'
        );
    }

    @IsTest
    static void testLogBulkEvents() {
        Fairness_Certificate__c cert = [
            SELECT Id
            FROM Fairness_Certificate__c
            LIMIT 1
        ];

        List<Compliance_Event__c> events = new List<Compliance_Event__c>();
        for (Integer i = 0; i < 3; i++) {
            Compliance_Event__c evt = new Compliance_Event__c();
            evt.Event_Type__c = 'CHAIN_GAP';
            evt.Severity__c = 'WARNING';
            evt.Related_Certificate__c = cert.Id;
            evt.Detail__c = '{"gap":' + i + '}';
            events.add(evt);
        }

        Test.startTest();
        ComplianceEventLogger.logBulk(events);
        Test.stopTest();

        List<Compliance_Event__c> inserted = [
            SELECT Id, Actor__c, Detail_Hash__c
            FROM Compliance_Event__c
        ];
        System.assertEquals(3, inserted.size(), 'Should insert all 3 events');

        for (Compliance_Event__c evt : inserted) {
            System.assertEquals(
                UserInfo.getUserId(),
                evt.Actor__c,
                'Actor should be auto-populated'
            );
            System.assertNotEquals(
                null,
                evt.Detail_Hash__c,
                'Detail hash should be auto-computed'
            );
        }
    }

    @IsTest
    static void testLogWithNullDetail() {
        Test.startTest();
        ComplianceEventLogger.log(
            'VALIDATION_FAILURE',
            'WARNING',
            null,
            null,
            null
        );
        Test.stopTest();

        List<Compliance_Event__c> events = [
            SELECT Event_Type__c, Detail__c, Detail_Hash__c
            FROM Compliance_Event__c
        ];
        System.assertEquals(1, events.size(), 'Should create one event');
        System.assertEquals(null, events[0].Detail__c, 'Detail should be null');
        System.assertEquals(
            null,
            events[0].Detail_Hash__c,
            'Detail hash should be null when no detail'
        );
    }
}
