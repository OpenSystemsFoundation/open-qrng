@IsTest
private class SetupController_Test {
    private static final String QF_ADMIN_USERNAME_PREFIX = 'qf.admin.';

    /**
     * Create a QuantumFair admin test user (System Administrator profile plus
     * the QuantumFair_Admin and QuantumFair_User permission sets). The
     * controller reads WITH USER_MODE / stripInaccessible, and object and field
     * access comes only from those permission sets, so tests that read through
     * the controller run as this user. Running them as whoever runs the tests
     * made them pass only where that user already held the permission sets
     * (a dev scratch org) and fail in a package build org.
     */
    @TestSetup
    static void createQuantumFairAdmin() {
        Profile admin = [
            SELECT Id
            FROM Profile
            WHERE PermissionsModifyAllData = TRUE AND UserType = 'Standard'
            ORDER BY CreatedDate
            LIMIT 1
        ];
        User u = new User(
            Alias = 'qfadmin',
            Email = 'qf.admin@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'QuantumFair Admin',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = admin.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = QF_ADMIN_USERNAME_PREFIX +
                DateTime.now().getTime() +
                '@example.com.qrngtest'
        );
        insert u;
        List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>();
        for (PermissionSet ps : [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN ('QuantumFair_Admin', 'QuantumFair_User')
        ]) {
            grants.add(
                new PermissionSetAssignment(
                    AssigneeId = u.Id,
                    PermissionSetId = ps.Id
                )
            );
        }
        insert grants;
    }

    private static User qfAdmin() {
        String prefix = QF_ADMIN_USERNAME_PREFIX + '%';
        return [SELECT Id FROM User WHERE Username LIKE :prefix LIMIT 1];
    }

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
                req.getEndpoint().contains('/configuration')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"coupling_map":[[0,1],[1,0],[1,2],[2,1]],"num_qubits":156}'
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
        Map<String, Object> settings = SetupController.getSettings();
        System.assertNotEquals(null, settings);
        System.assertEquals(false, settings.get('hasApiKey'));
    }

    /**
     * Create a user with no QuantumFair permissions (Standard User profile:
     * no custom-object CRUD, no custom-field FLS, no custom permission).
     * User DML is wrapped in runAs to avoid mixed-DML with test data.
     */
    private static User createRestrictedUser() {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User u = new User(
            Alias = 'qfrstr',
            Email = 'qf.restricted@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Restricted',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'qf.restricted.' +
                DateTime.now().getTime() +
                '@example.com.qrngtest'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    @IsTest
    static void testSaveSettings() {
        SetupController.adminOverrideForTests = true;
        SetupController.saveSettings(
            'test-key',
            'crn:v1:bluemix:public:quantum-computing:us-east:a/123:456::',
            'test_backend',
            2048,
            true,
            true,
            10,
            null
        );

        Quantum_Settings__c settings = Quantum_Settings__c.getOrgDefaults();
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
        Map<String, Object> result = SetupController.testConnection();
        System.assertEquals(false, result.get('connected'));
    }

    @IsTest
    static void testGetRecentJobs() {
        List<SetupController.JobSummaryDTO> jobs = SetupController.getRecentJobs();
        System.assertNotEquals(null, jobs);
    }

    @IsTest
    static void testGetUsageStats() {
        System.runAs(qfAdmin()) {
            Map<String, Object> stats = SetupController.getUsageStats();
            System.assertEquals(0, stats.get('totalJobs'));
        }
    }

    @IsTest
    static void testGetJobDetails() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_details',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            insert job;

            Quantum_Job__c result = SetupController.getJobDetails(job.Id);
            System.assertEquals('test_details', result.External_Job_ID__c);
        }
    }

    @IsTest
    static void testGetAuditTrailDTO() {
        List<SetupController.AuditTrailDTO> trail = SetupController.getAuditTrailDTO();
        System.assertNotEquals(null, trail);
    }

    @IsTest
    static void testGetAllBackendHealthEmpty() {
        List<SetupController.BackendHealthDTO> health = SetupController.getAllBackendHealth();
        System.assertNotEquals(null, health);
        System.assertEquals(0, health.size());
    }

    @IsTest
    static void testGetAllBackendHealthWithData() {
        System.runAs(qfAdmin()) {
            Quantum_Provider__c provider = new Quantum_Provider__c(
                Name = 'Test Provider',
                Provider_Key__c = 'test',
                Is_Active__c = true
            );
            insert provider;

            Quantum_Backend__c backend = new Quantum_Backend__c(
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

            List<SetupController.BackendHealthDTO> health = SetupController.getAllBackendHealth();
            System.assertEquals(1, health.size());
            System.assertEquals('test_backend_1', health[0].name);
            System.assertEquals('online', health[0].status);
            System.assertEquals(127, health[0].qubits);
        }
    }

    @IsTest
    static void testGetSettingsWithSavedData() {
        SetupController.adminOverrideForTests = true;
        SetupController.saveSettings(
            'key',
            'crn:test',
            'test_backend',
            4096,
            false,
            true,
            10,
            'compliance@test.com'
        );

        Map<String, Object> settings = SetupController.getSettings();
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
            SetupController.refreshJobStatus(job.Id);
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

        Fairness_Certificate__c cert = SetupController.getCertificateByJobId(
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

        List<Quantum_Assignment__c> assignments = SetupController.getAssignments(
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
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        Map<String, Object> health = SetupController.getBackendHealth(
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
        Quantum_Settings__c s = new Quantum_Settings__c(
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
        Map<String, Object> result = SetupController.refreshJobStatus(job.Id);
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
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-api-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        SetupController.adminOverrideForTests = true;
        Test.startTest();
        List<Map<String, String>> instances = SetupController.discoverInstances();
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
        Quantum_Settings__c updated = Quantum_Settings__c.getOrgDefaults();
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
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        SetupController.adminOverrideForTests = true;
        Test.startTest();
        List<Map<String, Object>> backends = SetupController.getAvailableBackends();
        Test.stopTest();

        System.assertEquals(1, backends.size(), 'Should return one backend');
        System.assertEquals(
            'test_backend',
            backends[0].get('name'),
            'Backend name should match'
        );

        // Verify Quantum_Backend__c record was created
        List<Quantum_Backend__c> records = [
            SELECT Name, Status__c
            FROM Quantum_Backend__c
            WHERE Name = 'test_backend'
        ];
        System.assertEquals(
            1,
            records.size(),
            'Backend record should be created'
        );

        // Verify IBM provider was created
        List<Quantum_Provider__c> providers = [
            SELECT Name, Provider_Key__c
            FROM Quantum_Provider__c
            WHERE Provider_Key__c = 'ibm'
        ];
        System.assertEquals(
            1,
            providers.size(),
            'IBM provider should be created'
        );
    }

    @IsTest
    static void testGetJobStatusDTO() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_dto_job',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 2048,
                Num_Qubits__c = 8,
                Purpose__c = 'DTO test',
                Use_Bell_Test__c = true,
                Submitted_At__c = DateTime.now().addMinutes(-5),
                Completed_At__c = DateTime.now(),
                Execution_Time_ms__c = 3000,
                Queue_Time_ms__c = 1500,
                Poll_Count__c = 3,
                Raw_Results__c = '0x66',
                Debiased_Results__c = '0x6'
            );
            insert job;

            SetupController.JobStatusDTO dto = SetupController.getJobStatusDTO(
                job.Id
            );
            System.assertEquals('Completed', dto.status);
            System.assertEquals('test_dto_job', dto.externalJobId);
            System.assertEquals('test_backend', dto.backend);
            System.assertEquals(2048, dto.shots);
            System.assertEquals(8, dto.numQubits);
            System.assertEquals('DTO test', dto.purpose);
            System.assertEquals(true, dto.useBellTest);
            System.assertEquals(3, dto.pollCount);
            System.assertEquals(3000, dto.executionTimeMs);
            System.assertEquals(1500, dto.queueTimeMs);
            System.assertEquals('0x66', dto.rawResults);
            System.assertEquals('0x6', dto.debiasedResults);
        }
    }

    @IsTest
    static void testGetJobStatusDTONullNumerics() {
        System.runAs(qfAdmin()) {
            // Test with null numeric fields to cover null-safe casting
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_dto_null',
                Backend__c = 'test_backend',
                Status__c = 'Submitted'
            );
            insert job;

            SetupController.JobStatusDTO dto = SetupController.getJobStatusDTO(
                job.Id
            );
            System.assertEquals('Submitted', dto.status);
            System.assertEquals(null, dto.shots);
            System.assertEquals(null, dto.numQubits);
            System.assertEquals(0, dto.pollCount);
        }
    }

    @IsTest
    static void testGetCertificateDTO() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_cert_dto',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Raw_Results__c = '0x66',
                Debiased_Results__c = '0x6',
                Purpose__c = 'Cert DTO test',
                Requested_By__c = UserInfo.getUserId()
            );
            insert job;

            Id certId = FairnessCertificateService.createCertificate(
                job.Id,
                '{"passed":true}',
                'Certified'
            );

            SetupController.CertificateDTO dto = SetupController.getCertificateDTO(
                certId
            );
            System.assertNotEquals(null, dto.name, 'Name should be set');
            System.assertEquals(
                'test_cert_dto',
                dto.externalJobId,
                'External job ID should match'
            );
            System.assertEquals('test_backend', dto.backend);
            System.assertNotEquals(
                null,
                dto.rawBitstringHash,
                'Raw hash should be set'
            );
            System.assertNotEquals(
                null,
                dto.debiasedBitstringHash,
                'Debiased hash should be set'
            );
            System.assertEquals('Certified', dto.status);
            System.assertEquals(job.Id, dto.quantumJobId);
            System.assertEquals(false, dto.tampered);
            System.assertEquals('Cert DTO test', dto.purpose);
        }
    }

    @IsTest
    static void testGetAuditTrailDTOWithData() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_audit_dto',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Raw_Results__c = '0x66',
                Debiased_Results__c = '0x6',
                Purpose__c = 'Audit trail test',
                Requested_By__c = UserInfo.getUserId()
            );
            insert job;

            FairnessCertificateService.createCertificate(
                job.Id,
                '{"passed":true}',
                'Certified'
            );

            List<SetupController.AuditTrailDTO> trail = SetupController.getAuditTrailDTO();
            System.assertEquals(
                1,
                trail.size(),
                'Should return one audit entry'
            );
            System.assertEquals('test_audit_dto', trail[0].externalJobId);
            System.assertEquals('test_backend', trail[0].backend);
            System.assertEquals('Certified', trail[0].status);
            System.assertEquals('Audit trail test', trail[0].purpose);
            System.assertEquals(false, trail[0].tampered);
            System.assertNotEquals(null, trail[0].recordId);
            System.assertEquals(job.Id, trail[0].quantumJobId);
        }
    }

    /**
     * Mock that returns a Failed status to exercise buildVerboseError.
     */
    private class MockFailedJobStatus implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token-abc","token_type":"Bearer","expires_in":3600}'
                );
            } else if (req.getEndpoint().contains('/v1/jobs/')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"id":"job_fail_123","status":"Failed",' +
                        '"state":{"status":"Failed","reason":"Calibration expired","reason_code":8020},' +
                        '"error":{"code":1234,"message":"Hardware fault","solution":"Retry later","more_info":"https://ibm.com/help"}}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testRefreshJobStatusFailedWithVerboseError() {
        Test.setMock(HttpCalloutMock.class, new MockFailedJobStatus());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_fail_123',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Test.startTest();
        Map<String, Object> result = SetupController.refreshJobStatus(job.Id);
        Test.stopTest();

        System.assertEquals(
            'Failed',
            result.get('status'),
            'Status should be Failed'
        );

        // Verify verbose error was saved
        Quantum_Job__c updated = [
            SELECT Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assert(
            updated.Error_Message__c.contains('Hardware fault'),
            'Error should contain IBM error message'
        );
        System.assert(
            updated.Error_Message__c.contains('1234'),
            'Error should contain error code'
        );
        System.assert(
            updated.Error_Message__c.contains('Retry later'),
            'Error should contain solution'
        );
        System.assert(
            updated.Error_Message__c.contains('Calibration expired'),
            'Error should contain reason'
        );
    }

    @IsTest
    static void testVerifyBackendQuantum() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Provider__c provider = new Quantum_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        Quantum_Backend__c backend = new Quantum_Backend__c(
            Name = 'test_backend',
            Backend_Key__c = 'ibm:test_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 156
        );
        insert backend;

        SetupController.adminOverrideForTests = true;
        Test.startTest();
        Id jobId = SetupController.verifyBackendQuantum('test_backend');
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Should return a job ID');

        Quantum_Job__c job = [
            SELECT Program_Id__c, Backend__c, Purpose__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
        ];
        System.assertEquals(
            'estimator',
            job.Program_Id__c,
            'Job should use estimator program'
        );
        System.assertEquals('test_backend', job.Backend__c);
        System.assert(
            job.Purpose__c.contains('CHSH'),
            'Purpose should mention CHSH verification'
        );
    }

    @IsTest
    static void testGetAllBackendHealthWithCHSHData() {
        System.runAs(qfAdmin()) {
            Quantum_Provider__c provider = new Quantum_Provider__c(
                Name = 'Test Provider',
                Provider_Key__c = 'test',
                Is_Active__c = true
            );
            insert provider;

            Quantum_Backend__c backend = new Quantum_Backend__c(
                Name = 'verified_backend',
                Backend_Key__c = 'test:verified_backend',
                Provider__c = provider.Id,
                Status__c = 'online',
                Num_Qubits__c = 127,
                CHSH_S_Value__c = 2.61,
                CHSH_Verified_At__c = DateTime.now()
            );
            insert backend;

            List<SetupController.BackendHealthDTO> health = SetupController.getAllBackendHealth();
            System.assertEquals(1, health.size());
            System.assertEquals(2.61, health[0].chshSValue);
            System.assertNotEquals(null, health[0].chshVerifiedAt);
            System.assertEquals(true, health[0].quantumVerified);
        }
    }

    @IsTest
    static void testGetCertificateDTOWithBackendVerification() {
        System.runAs(qfAdmin()) {
            Quantum_Provider__c provider = new Quantum_Provider__c(
                Name = 'IBM',
                Provider_Key__c = 'ibm',
                Is_Active__c = true
            );
            insert provider;

            Quantum_Backend__c backend = new Quantum_Backend__c(
                Name = 'verified_backend',
                Backend_Key__c = 'ibm:verified_backend',
                Provider__c = provider.Id,
                Status__c = 'online',
                Num_Qubits__c = 127,
                CHSH_S_Value__c = 2.55,
                CHSH_Verified_At__c = DateTime.now()
            );
            insert backend;

            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_bv_cert',
                Backend__c = 'verified_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Raw_Results__c = '0x66',
                Debiased_Results__c = '0x6',
                Requested_By__c = UserInfo.getUserId()
            );
            insert job;

            Id certId = FairnessCertificateService.createCertificate(
                job.Id,
                '{"passed":true}',
                'Certified'
            );

            SetupController.CertificateDTO dto = SetupController.getCertificateDTO(
                certId
            );
            System.assertEquals(
                true,
                dto.backendVerified,
                'Certificate should show backend as verified'
            );
            System.assertNotEquals(
                null,
                dto.backendVerifiedAt,
                'Certificate should have backend verification timestamp'
            );
        }
    }

    @IsTest
    static void testNormalizeIBMStatusValues() {
        // Test refreshJobStatus with different IBM statuses by checking the
        // normalizeIBMStatus logic via refreshJobStatus path
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
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
        Map<String, Object> result = SetupController.refreshJobStatus(job.Id);
        Test.stopTest();

        // The mock returns "Completed" — verify normalization worked
        System.assertEquals('Completed', result.get('status'));
    }

    @IsTest
    static void testBuildPauliString() {
        // buildPauliString moved to IBMQuantumProvider — test via that class
        // 11-qubit system, ZZ on qubits 5 and 10
        String zz = IBMQuantumProvider.buildPauliString(11, 5, 10);
        System.assertEquals(11, zz.length(), 'Should be 11 characters');
        System.assertEquals('Z', zz.substring(0, 1), 'qubit 10 should be Z');
        System.assertEquals('Z', zz.substring(5, 6), 'qubit 5 should be Z');
        System.assertEquals(
            'I',
            zz.substring(1, 2),
            'other qubits should be I'
        );

        // 2-qubit system, qubits 0 and 1
        String zz2 = IBMQuantumProvider.buildPauliString(2, 0, 1);
        System.assertEquals('ZZ', zz2, 'qubit 1=Z (left), qubit 0=Z (right)');
    }

    // ── runValidationTests ──────────────────────────────────────────

    @IsTest
    static void testRunValidationTestsCompletedJob() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_val',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Debiased_Results__c = '0x66a5a5a5',
                Raw_Results__c = '0x69a5a5a5',
                Use_Bell_Test__c = false
            );
            insert job;

            Test.startTest();
            Map<String, Object> results = SetupController.runValidationTests(
                job.Id
            );
            Test.stopTest();

            System.assertNotEquals(null, results);
            System.assertEquals(
                true,
                results.get('allTestsCompleted'),
                'Should mark all tests completed'
            );
            System.assertNotEquals(
                null,
                results.get('manualRunTimestamp'),
                'Should have timestamp'
            );
        }
    }

    @IsTest
    static void testRunValidationTestsNotCompleted() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_val_nc',
                Backend__c = 'test_backend',
                Status__c = 'Running',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            insert job;

            try {
                SetupController.runValidationTests(job.Id);
                System.assert(false, 'Should throw');
            } catch (QuantumException e) {
                System.assert(e.getMessage().contains('not completed'));
            }
        }
    }

    @IsTest
    static void testRunValidationTestsNoDebiased() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_val_nod',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            insert job;

            try {
                SetupController.runValidationTests(job.Id);
                System.assert(false, 'Should throw');
            } catch (QuantumException e) {
                System.assert(e.getMessage().contains('No debiased'));
            }
        }
    }

    @IsTest
    static void testRunValidationTestsWithBellTest() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_val_bell',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Debiased_Results__c = '0x66a5a5a5',
                Raw_Results__c = '0110100111100011',
                Use_Bell_Test__c = true
            );
            insert job;

            Test.startTest();
            Map<String, Object> results = SetupController.runValidationTests(
                job.Id
            );
            Test.stopTest();

            System.assertNotEquals(null, results.get('chshSValue'));
        }
    }

    @IsTest
    static void testRunValidationTestsUpdatesCertificate() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_val_cert',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Debiased_Results__c = '0x66a5a5a5',
                Raw_Results__c = '0x69a5a5a5',
                Use_Bell_Test__c = false,
                Requested_By__c = UserInfo.getUserId()
            );
            insert job;

            Id certId = FairnessCertificateService.createCertificate(
                job.Id,
                '{"passed":true}',
                'Certified'
            );

            Test.startTest();
            SetupController.runValidationTests(job.Id);
            Test.stopTest();

            Fairness_Certificate__c cert = [
                SELECT Validation_Results__c
                FROM Fairness_Certificate__c
                WHERE Id = :certId
            ];
            System.assert(
                cert.Validation_Results__c.contains('allTestsCompleted'),
                'Certificate should be updated with new validation'
            );
        }
    }

    // ── getValidationResults ────────────────────────────────────────

    @IsTest
    static void testGetValidationResultsWithData() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_vr',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8,
                Validation_Results__c = '{"passed":true,"frequency":0.51}'
            );
            insert job;

            Map<String, Object> results = SetupController.getValidationResults(
                job.Id
            );
            System.assertEquals(true, results.get('passed'));
            System.assertEquals(0.51, results.get('frequency'));
        }
    }

    @IsTest
    static void testGetValidationResultsEmpty() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'test_vr_empty',
                Backend__c = 'test_backend',
                Status__c = 'Submitted',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            insert job;

            Map<String, Object> results = SetupController.getValidationResults(
                job.Id
            );
            // Map always contains jobType and circuitQasm even when no validation data
            System.assert(results.containsKey('jobType'));
            System.assert(results.containsKey('circuitQasm'));
            System.assert(!results.containsKey('monobit'));
        }
    }

    // ── verifyCertificate ───────────────────────────────────────────

    @IsTest
    static void testVerifyCertificateInvalid() {
        // Test with non-existent certificate
        try {
            SetupController.verifyCertificate(null);
            System.assert(false, 'Should throw');
        } catch (Exception e) {
            // AuraHandledException.getMessage() returns 'Script-thrown exception'
            // in Apex tests — just verify the exception was thrown
            System.assert(true, 'Correctly threw for null certificate ID');
        }
    }

    // ── retrieveJobResults ──────────────────────────────────────────

    @IsTest
    static void testRetrieveJobResultsNoExternalId() {
        Quantum_Job__c job = new Quantum_Job__c(
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        try {
            SetupController.retrieveJobResults(job.Id);
            System.assert(false, 'Should throw');
        } catch (Exception e) {
            // AuraHandledException.getMessage() returns 'Script-thrown exception'
            // in Apex tests — just verify the exception was thrown
            System.assert(true, 'Correctly threw for missing external job ID');
        }
    }

    @IsTest
    static void testRetrieveJobResultsSampler() {
        Test.setMock(HttpCalloutMock.class, new MockIBMCallouts());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        Quantum_Settings__c s = new Quantum_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_ctrl_123',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 4,
            Num_Qubits__c = 4,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        Test.startTest();
        Map<String, Object> result = SetupController.retrieveJobResults(job.Id);
        Test.stopTest();

        System.assertEquals('Completed', result.get('status'));
        System.assertNotEquals(null, result.get('certificateId'));
    }

    // ── getUsageStats ───────────────────────────────────────────────

    @IsTest
    static void testGetUsageStatsWithData() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job1 = new Quantum_Job__c(
                External_Job_ID__c = 'stat_1',
                Backend__c = 'test',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            Quantum_Job__c job2 = new Quantum_Job__c(
                External_Job_ID__c = 'stat_2',
                Backend__c = 'test',
                Status__c = 'Failed',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            insert new List<Quantum_Job__c>{ job1, job2 };

            Map<String, Object> stats = SetupController.getUsageStats();
            System.assertEquals(2, stats.get('totalJobs'));
            System.assertEquals(1, stats.get('completedJobs'));
            System.assertEquals(1, stats.get('failedJobs'));
        }
    }

    // ── startIntegrityCheck / stopIntegrityCheck ────────────────────

    @IsTest
    static void testIntegrityCheckControls() {
        SetupController.adminOverrideForTests = true;
        Test.startTest();
        SetupController.startIntegrityCheck();
        Test.stopTest();

        // Just verify it doesn't throw
        SetupController.stopIntegrityCheck();
        System.assert(true, 'Integrity check controls work');
    }

    // ── saveSettings edge cases ─────────────────────────────────────

    @IsTest
    static void testSaveSettingsPartialUpdate() {
        SetupController.adminOverrideForTests = true;
        // First save
        SetupController.saveSettings(
            'key1',
            'crn:test',
            'backend1',
            1024,
            false,
            false,
            5,
            null
        );

        // Partial update — only change backend
        SetupController.saveSettings(
            null,
            null,
            'backend2',
            null,
            null,
            null,
            null,
            null
        );

        Quantum_Settings__c settings = Quantum_Settings__c.getOrgDefaults();
        System.assertEquals(
            'key1',
            settings.IBM_API_Key__c,
            'Key should be unchanged'
        );
        System.assertEquals(
            'backend2',
            settings.Default_Backend__c,
            'Backend should be updated'
        );
    }

    // ── Authorization gates (B6) ────────────────────────────────────
    // Denial tests run as a bare Standard User (no permission sets), so
    // FeatureManagement.checkPermission('QuantumFair_Administer') is
    // false and the gated calls must throw AuraHandledException.

    @IsTest
    static void testSaveSettingsDeniedWithoutAdminPermission() {
        User restricted = createRestrictedUser();
        System.runAs(restricted) {
            try {
                SetupController.saveSettings(
                    'key',
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                );
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Non-admin correctly denied');
            }
            System.assertEquals(
                null,
                Quantum_Settings__c.getOrgDefaults().IBM_API_Key__c,
                'Settings must not be written when denied'
            );
        }
    }

    @IsTest
    static void testStartSweeperDeniedWithoutAdminPermission() {
        User restricted = createRestrictedUser();
        System.runAs(restricted) {
            try {
                SetupController.startSweeper();
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Non-admin correctly denied');
            }
            System.assertEquals(
                false,
                JobSweeper.isScheduled(),
                'Sweeper must not be scheduled when denied'
            );
        }
    }

    @IsTest
    static void testStopIntegrityCheckDeniedWithoutAdminPermission() {
        User restricted = createRestrictedUser();
        System.runAs(restricted) {
            try {
                SetupController.stopIntegrityCheck();
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Non-admin correctly denied');
            }
        }
    }

    @IsTest
    static void testExportComplianceEvidenceDeniedWithoutAdminPermission() {
        User restricted = createRestrictedUser();
        System.runAs(restricted) {
            try {
                SetupController.exportComplianceEvidence(
                    'SOC2',
                    '2026-01-01',
                    '2026-01-31'
                );
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Non-admin correctly denied');
            }
        }
    }

    @IsTest
    static void testVerifyBackendQuantumDeniedWithoutAdminPermission() {
        User restricted = createRestrictedUser();
        System.runAs(restricted) {
            try {
                SetupController.verifyBackendQuantum('test_backend');
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Non-admin correctly denied');
            }
        }
    }

    @IsTest
    static void testGetAvailableBackendsDeniedWithoutAdminPermission() {
        try {
            SetupController.getAvailableBackends();
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true, 'Non-admin correctly denied');
        }
    }

    // ── Auto-scheduling on saveSettings (B7) ────────────────────────

    @IsTest
    static void testSaveSettingsAutoSchedulesBackgroundJobs() {
        SetupController.adminOverrideForTests = true;

        SetupController.saveSettings(
            'test-key',
            'crn:test',
            'test_backend',
            1024,
            false,
            false,
            5,
            'compliance@example.com'
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :JobSweeper.JOB_NAME
            ],
            'Sweeper should be auto-scheduled once an API key is saved'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :IntegrityVerificationJob.JOB_NAME
            ],
            'Integrity check should be auto-scheduled once an API key is saved'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :ComplianceDigestJob.JOB_NAME
            ],
            'Digest should be auto-scheduled when a compliance email is saved'
        );

        // Idempotent: saving again must not double-schedule
        SetupController.saveSettings(
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :JobSweeper.JOB_NAME
            ],
            'Re-saving settings must not create duplicate schedules'
        );
    }

    @IsTest
    static void testSaveSettingsClearingEmailUnschedulesDigest() {
        SetupController.adminOverrideForTests = true;

        SetupController.saveSettings(
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            'compliance@example.com'
        );
        System.assertEquals(
            true,
            ComplianceDigestJob.isScheduled(),
            'Digest should be scheduled while a compliance email is set'
        );

        SetupController.saveSettings(
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            ''
        );
        System.assertEquals(
            false,
            ComplianceDigestJob.isScheduled(),
            'Digest should be unscheduled when the compliance email is cleared'
        );
    }

    // ── Compliance logging on settings changes (B6) ─────────────────

    @IsTest
    static void testSaveSettingsLogsComplianceEvent() {
        SetupController.adminOverrideForTests = true;

        SetupController.saveSettings(
            'super-secret-key',
            null,
            'backend1',
            null,
            null,
            null,
            null,
            null
        );

        List<Compliance_Event__c> events = [
            SELECT Event_Type__c, Severity__c, Actor__c, Detail__c
            FROM Compliance_Event__c
            WHERE Event_Type__c = 'SETTINGS_CHANGED'
        ];
        System.assertEquals(
            1,
            events.size(),
            'A SETTINGS_CHANGED compliance event should be logged'
        );
        System.assertEquals('INFO', events[0].Severity__c);
        System.assertEquals(
            UserInfo.getUserId(),
            events[0].Actor__c,
            'The acting user should be recorded'
        );
        System.assert(
            events[0].Detail__c.contains('API key updated'),
            'Detail should note that the API key was updated'
        );
        System.assert(
            events[0].Detail__c.contains('Default_Backend__c'),
            'Detail should list the changed fields'
        );
        System.assert(
            !events[0].Detail__c.contains('super-secret-key'),
            'The API key value must never be logged'
        );
    }

    // ── getAssignmentsDTO ───────────────────────────────────────────

    @IsTest
    static void testGetAssignmentsDTO() {
        System.runAs(qfAdmin()) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'dto_assign_job',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Shots__c = 1024,
                Num_Qubits__c = 8
            );
            insert job;

            Quantum_Assignment__c assignment = new Quantum_Assignment__c(
                Quantum_Job__c = job.Id,
                Assignment_Index__c = 0,
                Assigned_Record_ID__c = '001000000000001AAA',
                Assigned_To_ID__c = '005000000000001AAA',
                Random_Value__c = '0.4213'
            );
            insert assignment;

            List<Map<String, Object>> result = SetupController.getAssignmentsDTO(
                job.Id
            );
            System.assertEquals(
                1,
                result.size(),
                'Should return one assignment'
            );
            Map<String, Object> row = result[0];
            System.assertEquals(assignment.Id, row.get('id'));
            System.assert(row.containsKey('name'), 'Should expose name');
            System.assertEquals(
                0,
                ((Decimal) row.get('index')).intValue(),
                'index should map Assignment_Index__c'
            );
            System.assertEquals(
                '001000000000001AAA',
                row.get('recordId'),
                'recordId should map Assigned_Record_ID__c'
            );
            System.assertEquals(
                '005000000000001AAA',
                row.get('assigneeId'),
                'assigneeId should map Assigned_To_ID__c'
            );
            System.assertEquals(
                '0.4213',
                row.get('randomValue'),
                'randomValue should map Random_Value__c'
            );
        }
    }

    @IsTest
    static void testGetAssignmentsDTOEmpty() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'dto_assign_empty',
            Backend__c = 'test_backend',
            Status__c = 'Completed'
        );
        insert job;

        List<Map<String, Object>> result = SetupController.getAssignmentsDTO(
            job.Id
        );
        System.assertEquals(0, result.size(), 'Should return an empty list');
    }

    // ── FLS enforcement via stripInaccessible (H-S2) ────────────────

    @IsTest
    static void testGetJobStatusDTOStripsFieldsForRestrictedUser() {
        User restricted = createRestrictedUser();
        // The Auditor permission set grants object read (viewAllRecords)
        // but deliberately excludes Raw_Results__c/Debiased_Results__c FLS,
        // so stripInaccessible must null those fields out.
        PermissionSet auditorPs = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'QuantumFair_Auditor'
            LIMIT 1
        ];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = restricted.Id,
                PermissionSetId = auditorPs.Id
            );
        }

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'strip_test',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Raw_Results__c = '0x66',
            Debiased_Results__c = '0x6'
        );
        insert job;

        System.runAs(restricted) {
            SetupController.JobStatusDTO dto = SetupController.getJobStatusDTO(
                job.Id
            );
            System.assertNotEquals(null, dto, 'DTO should still be returned');
            System.assertEquals(
                null,
                dto.rawResults,
                'Raw results must be stripped for users without FLS'
            );
            System.assertEquals(
                null,
                dto.debiasedResults,
                'Debiased results must be stripped for users without FLS'
            );
        }
    }

    @IsTest
    static void testRunValidationTestsDeniedForReadOnlyUser() {
        User restricted = createRestrictedUser();

        System.runAs(restricted) {
            Quantum_Job__c job = new Quantum_Job__c(
                External_Job_ID__c = 'readonly_val',
                Backend__c = 'test_backend',
                Status__c = 'Completed',
                Debiased_Results__c = '0x66a5a5a5'
            );
            insert job;

            try {
                SetupController.runValidationTests(job.Id);
                System.assert(false, 'Should have thrown AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Read-only user correctly denied');
            }
        }
    }
}
