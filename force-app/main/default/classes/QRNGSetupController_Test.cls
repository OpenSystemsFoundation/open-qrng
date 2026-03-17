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
}
