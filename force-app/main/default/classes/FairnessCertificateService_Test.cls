@IsTest
private class FairnessCertificateService_Test {
    @TestSetup
    static void setup() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_job_001',
            Backend__c = 'ibm_kingston',
            Status__c = 'Completed',
            Circuit_QASM__c = 'OPENQASM 3.0; bit[1] meas;',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Raw_Results__c = '01101001',
            Debiased_Results__c = '01',
            Purpose__c = 'Test purpose',
            Requested_By__c = UserInfo.getUserId()
        );
        insert job;
    }

    @IsTest
    static void testCreateCertificate() {
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        String validationJson = '{"passed":true,"frequencyTest":true,"runsTest":true}';

        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            validationJson,
            'Certified'
        );

        Fairness_Certificate__c cert = [
            SELECT Id, Status__c, External_Job_ID__c, Raw_Bitstring_Hash__c
            FROM Fairness_Certificate__c
            WHERE Id = :certId
        ];
        System.assertEquals('Certified', cert.Status__c);
        System.assertEquals('test_job_001', cert.External_Job_ID__c);
        System.assertNotEquals(null, cert.Raw_Bitstring_Hash__c);
    }

    @IsTest
    static void testUpdateAssignmentHash() {
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{}',
            'Certified'
        );

        FairnessCertificateService.updateAssignmentHash(
            certId,
            'test assignment data'
        );

        Fairness_Certificate__c cert = [
            SELECT Assignment_Hash__c
            FROM Fairness_Certificate__c
            WHERE Id = :certId
        ];
        System.assertNotEquals(null, cert.Assignment_Hash__c);
    }

    @IsTest
    static void testVerifyCertificate() {
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{}',
            'Certified'
        );

        Map<String, Object> result = FairnessCertificateService.verifyCertificate(
            certId
        );
        System.assertEquals(true, result.get('integrityVerified'));
    }

    @IsTest
    static void testComputeSHA256() {
        String hash1 = FairnessCertificateService.computeSHA256('hello');
        String hash2 = FairnessCertificateService.computeSHA256('hello');
        String hash3 = FairnessCertificateService.computeSHA256('world');

        System.assertEquals(
            hash1,
            hash2,
            'Same input should produce same hash'
        );
        System.assertNotEquals(
            hash1,
            hash3,
            'Different inputs should produce different hashes'
        );
        System.assertEquals(
            64,
            hash1.length(),
            'SHA-256 hex should be 64 chars'
        );
    }
}
