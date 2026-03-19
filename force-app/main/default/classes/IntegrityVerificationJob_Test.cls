@IsTest
private class IntegrityVerificationJob_Test {
    @TestSetup
    static void setup() {
        // Create a job with known results
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_integrity_test',
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

        // Create a matching certificate with correct hashes
        String rawHash = FairnessCertificateService.computeSHA256('0x69e3');
        String debiasedHash = FairnessCertificateService.computeSHA256('0x5');
        Fairness_Certificate__c cert = new Fairness_Certificate__c(
            Quantum_Job__c = job.Id,
            External_Job_ID__c = 'job_integrity_test',
            Backend__c = 'test_backend',
            Raw_Bitstring_Hash__c = rawHash,
            Debiased_Bitstring_Hash__c = debiasedHash,
            Status__c = 'Certified',
            Purpose__c = 'Integrity test'
        );
        insert cert;
    }

    @IsTest
    static void testScheduleAndUnschedule() {
        Test.startTest();
        IntegrityVerificationJob.scheduleDefault();
        Test.stopTest();

        System.assertEquals(
            true,
            IntegrityVerificationJob.isScheduled(),
            'Job should be scheduled'
        );

        IntegrityVerificationJob.unschedule();
        System.assertEquals(
            false,
            IntegrityVerificationJob.isScheduled(),
            'Job should be unscheduled'
        );
    }

    @IsTest
    static void testSchedulableExecute() {
        Test.startTest();
        IntegrityVerificationJob ivj = new IntegrityVerificationJob();
        ivj.execute(null);
        Test.stopTest();

        System.assert(true, 'Schedulable execute completed without error');
    }

    @IsTest
    static void testGetCheckHourDefault() {
        System.assertEquals(
            2,
            IntegrityVerificationJob.getCheckHour(),
            'Default check hour should be 2'
        );
    }

    @IsTest
    static void testGetCheckHourFromSettings() {
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Integrity_Check_Hour__c = 5
        );
        upsert s;

        System.assertEquals(
            5,
            IntegrityVerificationJob.getCheckHour(),
            'Should read hour from settings'
        );
    }

    @IsTest
    static void testWorkerPassesValidCertificate() {
        IntegrityVerificationJob.IntegrityVerificationWorker worker = new IntegrityVerificationJob.IntegrityVerificationWorker(
            null
        );

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Fairness_Certificate__c cert = [
            SELECT Tampered__c, Last_Integrity_Check__c
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        System.assertEquals(
            false,
            cert.Tampered__c,
            'Valid certificate should not be marked tampered'
        );
        System.assertNotEquals(
            null,
            cert.Last_Integrity_Check__c,
            'Last integrity check should be set'
        );
    }

    @IsTest
    static void testWorkerDetectsTamperedRawResults() {
        // Tamper with the job's raw results
        Quantum_Job__c job = [
            SELECT Id
            FROM Quantum_Job__c
            LIMIT 1
        ];
        job.Raw_Results__c = 'TAMPERED_DATA';
        update job;

        IntegrityVerificationJob.IntegrityVerificationWorker worker = new IntegrityVerificationJob.IntegrityVerificationWorker(
            null
        );

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Fairness_Certificate__c cert = [
            SELECT Tampered__c
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        System.assertEquals(
            true,
            cert.Tampered__c,
            'Certificate should be marked tampered when raw results changed'
        );
    }

    @IsTest
    static void testWorkerDetectsTamperedDebiasedResults() {
        // Tamper with debiased results
        Quantum_Job__c job = [
            SELECT Id
            FROM Quantum_Job__c
            LIMIT 1
        ];
        job.Debiased_Results__c = 'TAMPERED';
        update job;

        IntegrityVerificationJob.IntegrityVerificationWorker worker = new IntegrityVerificationJob.IntegrityVerificationWorker(
            null
        );

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        Fairness_Certificate__c cert = [
            SELECT Tampered__c
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        System.assertEquals(
            true,
            cert.Tampered__c,
            'Certificate should be marked tampered when debiased results changed'
        );
    }

    @IsTest
    static void testWorkerClearsTamperedOnReVerify() {
        // First mark as tampered
        Fairness_Certificate__c cert = [
            SELECT Id
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        cert.Tampered__c = true;
        update cert;

        // Run worker — hashes still match, should clear tampered
        IntegrityVerificationJob.IntegrityVerificationWorker worker = new IntegrityVerificationJob.IntegrityVerificationWorker(
            null
        );

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        cert = [
            SELECT Tampered__c
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        System.assertEquals(
            false,
            cert.Tampered__c,
            'Tampered flag should be cleared when hashes match again'
        );
    }

    @IsTest
    static void testWorkerWithNoCertificates() {
        // Delete all certificates
        delete [SELECT Id FROM Fairness_Certificate__c];

        IntegrityVerificationJob.IntegrityVerificationWorker worker = new IntegrityVerificationJob.IntegrityVerificationWorker(
            null
        );

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        System.assert(true, 'Worker should handle empty set without error');
    }

    @IsTest
    static void testVerifyCertificateSetsTampered() {
        // Tamper with raw results
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c LIMIT 1];
        job.Raw_Results__c = 'MANIPULATED';
        update job;

        Fairness_Certificate__c cert = [
            SELECT Id
            FROM Fairness_Certificate__c
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Object> result = FairnessCertificateService.verifyCertificate(
            cert.Id
        );
        Test.stopTest();

        System.assertEquals(
            false,
            (Boolean) result.get('integrityVerified'),
            'Should detect tampering'
        );
        System.assertEquals(
            false,
            (Boolean) result.get('rawHashMatch'),
            'Raw hash should not match'
        );

        cert = [
            SELECT Tampered__c, Last_Integrity_Check__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert.Id
        ];
        System.assertEquals(
            true,
            cert.Tampered__c,
            'Verify should set Tampered__c = true'
        );
        System.assertNotEquals(
            null,
            cert.Last_Integrity_Check__c,
            'Should set last check timestamp'
        );
    }

    @IsTest
    static void testVerifyCertificateClearsTampered() {
        // Pre-mark as tampered but data is still valid
        Fairness_Certificate__c cert = [
            SELECT Id
            FROM Fairness_Certificate__c
            LIMIT 1
        ];
        cert.Tampered__c = true;
        update cert;

        Test.startTest();
        Map<String, Object> result = FairnessCertificateService.verifyCertificate(
            cert.Id
        );
        Test.stopTest();

        System.assertEquals(
            true,
            (Boolean) result.get('integrityVerified'),
            'Should verify clean'
        );

        cert = [
            SELECT Tampered__c
            FROM Fairness_Certificate__c
            WHERE Id = :cert.Id
        ];
        System.assertEquals(
            false,
            cert.Tampered__c,
            'Verify should clear Tampered__c when hashes match'
        );
    }

    @IsTest
    static void testCreateCertificateUpdatesExisting() {
        Quantum_Job__c job = [SELECT Id FROM Quantum_Job__c LIMIT 1];

        // First cert already exists from setup
        Integer countBefore = [SELECT COUNT() FROM Fairness_Certificate__c];

        Test.startTest();
        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{"passed":true}',
            'Certified'
        );
        Test.stopTest();

        Integer countAfter = [SELECT COUNT() FROM Fairness_Certificate__c];
        System.assertEquals(
            countBefore,
            countAfter,
            'Should update existing cert, not create a new one'
        );

        Fairness_Certificate__c cert = [
            SELECT Tampered__c, Status__c
            FROM Fairness_Certificate__c
            WHERE Id = :certId
        ];
        System.assertEquals(false, cert.Tampered__c, 'Should reset tampered');
        System.assertEquals('Certified', cert.Status__c);
    }

    @IsTest
    static void testControllerStartStop() {
        Test.startTest();
        QRNGSetupController.startIntegrityCheck();
        Test.stopTest();

        System.assertEquals(
            true,
            IntegrityVerificationJob.isScheduled(),
            'Should be scheduled after start'
        );

        QRNGSetupController.stopIntegrityCheck();
        System.assertEquals(
            false,
            IntegrityVerificationJob.isScheduled(),
            'Should be unscheduled after stop'
        );
    }
}
