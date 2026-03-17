@IsTest
private class QRNGSetupController_Test {
    @IsTest
    static void testGetSettings() {
        Map<String, Object> settings = QRNGSetupController.getSettings();
        System.assertNotEquals(null, settings);
        System.assertEquals(false, settings.get('hasApiKey'));
    }

    @IsTest
    static void testSaveSettings() {
        QRNGSetupController.saveSettings(
            'test-key',
            'crn:v1:bluemix:public:quantum-computing:us-east:a/123:456::',
            'test_backend',
            2048,
            true,
            true,
            10
        );

        QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
        System.assertEquals('test-key', settings.IBM_API_Key__c);
        System.assertEquals(
            'crn:v1:bluemix:public:quantum-computing:us-east:a/123:456::',
            settings.Instance_CRN__c
        );
        System.assertEquals('test_backend', settings.Default_Backend__c);
        System.assertEquals(2048, settings.Default_Shots__c);
        System.assertEquals(true, settings.Use_Bell_Test__c);
        System.assertEquals(true, settings.Use_Least_Busy__c);
        System.assertEquals(10, settings.Poll_Interval_Minutes__c);
    }

    @IsTest
    static void testTestConnection() {
        Map<String, Object> result = QRNGSetupController.testConnection();
        System.assertEquals(false, result.get('connected'));
    }

    @IsTest
    static void testGetRecentJobs() {
        List<Quantum_Job__c> jobs = QRNGSetupController.getRecentJobs();
        System.assertNotEquals(null, jobs);
    }

    @IsTest
    static void testGetUsageStats() {
        Map<String, Object> stats = QRNGSetupController.getUsageStats();
        System.assertEquals(0, stats.get('totalJobs'));
    }

    @IsTest
    static void testGetJobDetails() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_details',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Quantum_Job__c result = QRNGSetupController.getJobDetails(job.Id);
        System.assertEquals('test_details', result.External_Job_ID__c);
    }

    @IsTest
    static void testGetAuditTrail() {
        List<Fairness_Certificate__c> trail = QRNGSetupController.getAuditTrail();
        System.assertNotEquals(null, trail);
    }

    @IsTest
    static void testGetAllBackendHealthEmpty() {
        List<QRNGSetupController.BackendHealthDTO> health = QRNGSetupController.getAllBackendHealth();
        System.assertNotEquals(null, health);
        System.assertEquals(0, health.size());
    }

    @IsTest
    static void testGetAllBackendHealthWithData() {
        QRNG_Provider__c provider = new QRNG_Provider__c(
            Name = 'Test Provider',
            Provider_Key__c = 'test',
            Is_Active__c = true
        );
        insert provider;

        QRNG_Backend__c backend = new QRNG_Backend__c(
            Name = 'test_backend_1',
            Backend_Key__c = 'test:test_backend_1',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 127,
            Queue_Length__c = 5,
            Avg_T1_us__c = 200.5,
            Avg_T2_us__c = 150.3,
            Median_Gate_Error__c = 0.001,
            Median_Readout_Error__c = 0.02
        );
        insert backend;

        List<QRNGSetupController.BackendHealthDTO> health = QRNGSetupController.getAllBackendHealth();
        System.assertEquals(1, health.size());
        System.assertEquals('test_backend_1', health[0].name);
        System.assertEquals('online', health[0].status);
        System.assertEquals(127, health[0].qubits);
    }

    @IsTest
    static void testGetSettingsWithSavedData() {
        QRNGSetupController.saveSettings(
            'key',
            'crn:test',
            'test_backend',
            4096,
            false,
            true,
            10
        );

        Map<String, Object> settings = QRNGSetupController.getSettings();
        System.assertEquals(true, settings.get('hasApiKey'));
        System.assertEquals(true, settings.get('hasCRN'));
        System.assertEquals(true, settings.get('useLeastBusy'));
        System.assertEquals(10.0, settings.get('pollIntervalMinutes'));
    }

    @IsTest
    static void testRefreshJobStatusNoExternalId() {
        Quantum_Job__c job = new Quantum_Job__c(
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        try {
            QRNGSetupController.refreshJobStatus(job.Id);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('external job ID'),
                'Should mention missing external job ID'
            );
        }
    }

    @IsTest
    static void testGetCertificateByJobId() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_cert_job',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Fairness_Certificate__c cert = QRNGSetupController.getCertificateByJobId(
            job.Id
        );
        System.assertEquals(null, cert);
    }

    @IsTest
    static void testGetAssignments() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_assign_job',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        List<QRNG_Assignment__c> assignments = QRNGSetupController.getAssignments(
            job.Id
        );
        System.assertNotEquals(null, assignments);
        System.assertEquals(0, assignments.size());
    }
}
