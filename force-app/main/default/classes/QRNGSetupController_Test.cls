@IsTest
private class QRNGSetupController_Test {
    /**
     * Shared mock for IBM Quantum API callouts used across controller tests.
     */
    private class MockIBMCallouts implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token-abc","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('resource-controller.cloud.ibm.com')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"resources":[{"name":"qiskit-instance","crn":"crn:v1:bluemix:public:quantum-computing:us-east:a/123:456::","state":"active"}]}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs') &&
                req.getMethod() == 'POST'
            ) {
                res.setStatusCode(200);
                res.setBody('{"id":"job_ctrl_123","backend":"test_backend"}');
            } else if (
                req.getEndpoint().contains('/v1/jobs/') &&
                req.getEndpoint().contains('/results')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"results":[{"data":{"meas":{"samples":["0110","1001","1110","0011"]}}}]}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_ctrl_123","status":"Completed","state":{"status":"Completed"}}'
                );
            } else if (
                req.getEndpoint().contains('/v1/backends/') &&
                req.getEndpoint().contains('/properties')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"qubits":[[{"name":"T1","value":200.5},{"name":"T2","value":150.3},{"name":"readout_error","value":0.02}]],' +
                        '"gates":[{"parameters":[{"name":"gate_error","value":0.001}]}],' +
                        '"last_update_date":"2026-03-15T10:00:00Z"}'
                );
            } else if (req.getEndpoint().contains('/v1/backends')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"devices":[{"name":"test_backend","status":"online","qubits":156}]}'
                );
            }
            return res;
        }
    }

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
        } catch (Exception e) {
            // AuraHandledException wraps the message — just verify it threw
            System.assert(true, 'Correctly threw for missing external job ID');
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

    @IsTest
    static void testGetBackendHealth() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        Map<String, Object> health = QRNGSetupController.getBackendHealth(
            'test_backend'
        );
        Test.stopTest();

        System.assertNotEquals(null, health, 'Health data should not be null');
        System.assertEquals(
            'test_backend',
            health.get('backendName'),
            'Should contain backend name'
        );
        System.assertEquals(
            1,
            health.get('qubitCount'),
            'Should have 1 qubit from mock'
        );
        System.assertNotEquals(
            null,
            health.get('avgT1'),
            'Should contain avgT1'
        );
        System.assertNotEquals(
            null,
            health.get('avgT2'),
            'Should contain avgT2'
        );
        System.assertNotEquals(
            null,
            health.get('avgReadoutError'),
            'Should contain avgReadoutError'
        );
        System.assertNotEquals(
            null,
            health.get('avgGateError'),
            'Should contain avgGateError'
        );
    }

    @IsTest
    static void testRefreshJobStatusWithExternalId() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_ctrl_123',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Test.startTest();
        Map<String, Object> result = QRNGSetupController.refreshJobStatus(
            job.Id
        );
        Test.stopTest();

        System.assertEquals(
            'Completed',
            result.get('status'),
            'Status should be Completed'
        );
        System.assertEquals(job.Id, result.get('jobId'), 'Job ID should match');

        // Verify job record was updated
        Quantum_Job__c updated = [
            SELECT Status__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Completed', updated.Status__c);
    }

    @IsTest
    static void testDiscoverInstances() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        List<Map<String, String>> instances = QRNGSetupController.discoverInstances();
        Test.stopTest();

        System.assertEquals(1, instances.size(), 'Should find one instance');
        System.assertEquals(
            'qiskit-instance',
            instances[0].get('name'),
            'Instance name should match'
        );
        System.assertNotEquals(
            null,
            instances[0].get('crn'),
            'CRN should not be null'
        );

        // Single instance should auto-save CRN to settings
        QRNG_Settings__c updated = QRNG_Settings__c.getOrgDefaults();
        System.assert(
            String.isNotBlank(updated.Instance_CRN__c),
            'CRN should be saved when single instance found'
        );
    }

    @IsTest
    static void testGetAvailableBackends() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        List<Map<String, Object>> backends = QRNGSetupController.getAvailableBackends();
        Test.stopTest();

        System.assertEquals(1, backends.size(), 'Should return one backend');
        System.assertEquals(
            'test_backend',
            backends[0].get('name'),
            'Backend name should match'
        );

        // Verify QRNG_Backend__c record was created
        List<QRNG_Backend__c> records = [
            SELECT Name, Status__c
            FROM QRNG_Backend__c
            WHERE Name = 'test_backend'
        ];
        System.assertEquals(
            1,
            records.size(),
            'Backend record should be created'
        );

        // Verify IBM provider was created
        List<QRNG_Provider__c> providers = [
            SELECT Name, Provider_Key__c
            FROM QRNG_Provider__c
            WHERE Provider_Key__c = 'ibm'
        ];
        System.assertEquals(
            1,
            providers.size(),
            'IBM provider should be created'
        );
    }

    @IsTest
    static void testNormalizeIBMStatusValues() {
        // Test refreshJobStatus with different IBM statuses by checking the
        // normalizeIBMStatus logic via refreshJobStatus path
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_ctrl_123',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Test.startTest();
        Map<String, Object> result = QRNGSetupController.refreshJobStatus(
            job.Id
        );
        Test.stopTest();

        // The mock returns "Completed" — verify normalization worked
        System.assertEquals('Completed', result.get('status'));
    }
}
