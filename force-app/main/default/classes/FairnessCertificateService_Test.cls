@IsTest
private class FairnessCertificateService_Test {
    @TestSetup
    static void setup() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_job_001',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Circuit_QASM__c = 'OPENQASM 3.0; bit[1] meas;',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Raw_Results__c = '0x69',
            Debiased_Results__c = '0x1',
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

    private static Quantum_Job__c makeJob(String extId, String rawResults) {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = extId,
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Circuit_QASM__c = 'OPENQASM 3.0; bit[1] meas;',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Raw_Results__c = rawResults,
            Debiased_Results__c = '0x1',
            Purpose__c = 'Chain test',
            Requested_By__c = UserInfo.getUserId()
        );
        insert job;
        return job;
    }

    @IsTest
    static void testChainedCertificatesVerify() {
        Quantum_Job__c job1 = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        Id cert1Id = FairnessCertificateService.createCertificate(
            job1.Id,
            '{"passed":true}',
            'Certified'
        );

        Quantum_Job__c job2 = makeJob('test_job_002', '0x77');
        Id cert2Id = FairnessCertificateService.createCertificate(
            job2.Id,
            '{"passed":true}',
            'Certified'
        );

        Fairness_Certificate__c cert1 = [
            SELECT Chain_Position__c, Chain_Hash__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert1Id
        ];
        Fairness_Certificate__c cert2 = [
            SELECT
                Chain_Position__c,
                Previous_Certificate__c,
                Previous_Certificate_Hash__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert2Id
        ];
        System.assertEquals(1, cert1.Chain_Position__c);
        System.assertEquals(2, cert2.Chain_Position__c);
        System.assertEquals(cert1Id, cert2.Previous_Certificate__c);
        System.assertEquals(
            cert1.Chain_Hash__c,
            cert2.Previous_Certificate_Hash__c
        );

        Map<String, Object> result = FairnessCertificateService.verifyCertificate(
            cert2Id
        );
        System.assertEquals(true, result.get('integrityVerified'));
        System.assertEquals(true, result.get('previousHashMatch'));
    }

    @IsTest
    static void testVerifyDetectsForgedPreviousHash() {
        Quantum_Job__c job1 = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        FairnessCertificateService.createCertificate(
            job1.Id,
            '{"passed":true}',
            'Certified'
        );

        Quantum_Job__c job2 = makeJob('test_job_forged', '0x77');
        Id cert2Id = FairnessCertificateService.createCertificate(
            job2.Id,
            '{"passed":true}',
            'Certified'
        );

        // Forge the predecessor hash AND recompute the chain hash so it is
        // self-consistent — the naive recompute-only check would pass this
        Fairness_Certificate__c cert2 = [
            SELECT
                Id,
                Raw_Bitstring_Hash__c,
                Debiased_Bitstring_Hash__c,
                Previous_Certificate_Hash__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert2Id
        ];
        String forged = FairnessCertificateService.computeSHA256(
            'forged-predecessor'
        );
        cert2.Previous_Certificate_Hash__c = forged;
        cert2.Chain_Hash__c = FairnessCertificateService.computeSHA256(
            cert2.Raw_Bitstring_Hash__c +
                cert2.Debiased_Bitstring_Hash__c +
                forged
        );
        update cert2;

        Map<String, Object> result = FairnessCertificateService.verifyCertificate(
            cert2Id
        );

        System.assertEquals(
            true,
            result.get('chainHashMatch'),
            'Forgery is self-consistent for the naive recompute'
        );
        System.assertEquals(
            false,
            result.get('previousHashMatch'),
            'Predecessor walk must expose the forged link'
        );
        System.assertEquals(false, result.get('integrityVerified'));

        Fairness_Certificate__c updated = [
            SELECT Tampered__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert2Id
        ];
        System.assertEquals(true, updated.Tampered__c);
    }

    @IsTest
    static void testRecertificationKeepsOriginalChainLink() {
        Quantum_Job__c job1 = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        Id cert1Id = FairnessCertificateService.createCertificate(
            job1.Id,
            '{"passed":true}',
            'Certified'
        );

        // A second certificate now occupies the chain tail
        Quantum_Job__c job2 = makeJob('test_job_tail', '0x77');
        Id cert2Id = FairnessCertificateService.createCertificate(
            job2.Id,
            '{"passed":true}',
            'Certified'
        );

        Fairness_Certificate__c before = [
            SELECT
                Previous_Certificate_Hash__c,
                Previous_Certificate__c,
                Chain_Position__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert1Id
        ];

        // Re-certify job1: must keep its original genesis link, not
        // re-link to cert2 at the tail
        Id recertId = FairnessCertificateService.createCertificate(
            job1.Id,
            '{"passed":true,"rerun":true}',
            'Certified'
        );
        System.assertEquals(cert1Id, recertId, 'Same certificate updated');

        Fairness_Certificate__c after = [
            SELECT
                Previous_Certificate_Hash__c,
                Previous_Certificate__c,
                Chain_Position__c,
                Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert1Id
        ];
        System.assertEquals(
            before.Previous_Certificate_Hash__c,
            after.Previous_Certificate_Hash__c,
            'Predecessor hash is immutable'
        );
        System.assertEquals(
            before.Chain_Position__c,
            after.Chain_Position__c,
            'Chain position is immutable'
        );
        System.assertEquals(
            before.Previous_Certificate__c,
            after.Previous_Certificate__c,
            'Predecessor lookup is immutable'
        );
        System.assert(
            after.Validation_Results__c.contains('rerun'),
            'Content fields are refreshed'
        );

        // The successor must still verify (job1 content was unchanged, so
        // cert1's chain hash recomputes to the same value)
        Map<String, Object> result = FairnessCertificateService.verifyCertificate(
            cert2Id
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
