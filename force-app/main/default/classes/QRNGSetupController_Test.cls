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
    static void testGetAuditTrailDTO() {
        List<QRNGSetupController.AuditTrailDTO> trail = QRNGSetupController.getAuditTrailDTO();
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
    static void testGetJobStatusDTO() {
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

        QRNGSetupController.JobStatusDTO dto = QRNGSetupController.getJobStatusDTO(
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

    @IsTest
    static void testGetJobStatusDTONullNumerics() {
        // Test with null numeric fields to cover null-safe casting
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_dto_null',
            Backend__c = 'test_backend',
            Status__c = 'Submitted'
        );
        insert job;

        QRNGSetupController.JobStatusDTO dto = QRNGSetupController.getJobStatusDTO(
            job.Id
        );
        System.assertEquals('Submitted', dto.status);
        System.assertEquals(null, dto.shots);
        System.assertEquals(null, dto.numQubits);
        System.assertEquals(0, dto.pollCount);
    }

    @IsTest
    static void testGetCertificateDTO() {
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

        QRNGSetupController.CertificateDTO dto = QRNGSetupController.getCertificateDTO(
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

    @IsTest
    static void testGetAuditTrailDTOWithData() {
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

        List<QRNGSetupController.AuditTrailDTO> trail = QRNGSetupController.getAuditTrailDTO();
        System.assertEquals(1, trail.size(), 'Should return one audit entry');
        System.assertEquals('test_audit_dto', trail[0].externalJobId);
        System.assertEquals('test_backend', trail[0].backend);
        System.assertEquals('Certified', trail[0].status);
        System.assertEquals('Audit trail test', trail[0].purpose);
        System.assertEquals(false, trail[0].tampered);
        System.assertNotEquals(null, trail[0].recordId);
        System.assertEquals(job.Id, trail[0].quantumJobId);
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
        QRNG_Settings__c s = new QRNG_Settings__c(
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
        Map<String, Object> result = QRNGSetupController.refreshJobStatus(
            job.Id
        );
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
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            IBM_API_Key__c = 'test-key',
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        QRNG_Provider__c provider = new QRNG_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        QRNG_Backend__c backend = new QRNG_Backend__c(
            Name = 'test_backend',
            Backend_Key__c = 'ibm:test_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 156
        );
        insert backend;

        Test.startTest();
        Id jobId = QRNGSetupController.verifyBackendQuantum('test_backend');
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
        QRNG_Provider__c provider = new QRNG_Provider__c(
            Name = 'Test Provider',
            Provider_Key__c = 'test',
            Is_Active__c = true
        );
        insert provider;

        QRNG_Backend__c backend = new QRNG_Backend__c(
            Name = 'verified_backend',
            Backend_Key__c = 'test:verified_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 127,
            CHSH_S_Value__c = 2.61,
            CHSH_Verified_At__c = DateTime.now()
        );
        insert backend;

        List<QRNGSetupController.BackendHealthDTO> health = QRNGSetupController.getAllBackendHealth();
        System.assertEquals(1, health.size());
        System.assertEquals(2.61, health[0].chshSValue);
        System.assertNotEquals(null, health[0].chshVerifiedAt);
        System.assertEquals(true, health[0].quantumVerified);
    }

    @IsTest
    static void testGetCertificateDTOWithBackendVerification() {
        QRNG_Provider__c provider = new QRNG_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        QRNG_Backend__c backend = new QRNG_Backend__c(
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

        QRNGSetupController.CertificateDTO dto = QRNGSetupController.getCertificateDTO(
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
        Map<String, Object> results = QRNGSetupController.runValidationTests(
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

    @IsTest
    static void testRunValidationTestsNotCompleted() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_val_nc',
            Backend__c = 'test_backend',
            Status__c = 'Running',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        try {
            QRNGSetupController.runValidationTests(job.Id);
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('not completed'));
        }
    }

    @IsTest
    static void testRunValidationTestsNoDebiased() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_val_nod',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        try {
            QRNGSetupController.runValidationTests(job.Id);
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(e.getMessage().contains('No debiased'));
        }
    }

    @IsTest
    static void testRunValidationTestsWithBellTest() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_val_bell',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 4,
            Debiased_Results__c = '0x66a5a5a5',
            Raw_Results__c = '0110100111100011',
            Use_Bell_Test__c = true
        );
        insert job;

        Test.startTest();
        Map<String, Object> results = QRNGSetupController.runValidationTests(
            job.Id
        );
        Test.stopTest();

        System.assertNotEquals(null, results.get('chshSValue'));
    }

    @IsTest
    static void testRunValidationTestsUpdatesCertificate() {
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
        QRNGSetupController.runValidationTests(job.Id);
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

    // ── getValidationResults ────────────────────────────────────────

    @IsTest
    static void testGetValidationResultsWithData() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_vr',
            Backend__c = 'test_backend',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8,
            Validation_Results__c = '{"passed":true,"frequency":0.51}'
        );
        insert job;

        Map<String, Object> results = QRNGSetupController.getValidationResults(
            job.Id
        );
        System.assertEquals(true, results.get('passed'));
        System.assertEquals(0.51, results.get('frequency'));
    }

    @IsTest
    static void testGetValidationResultsEmpty() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_vr_empty',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Map<String, Object> results = QRNGSetupController.getValidationResults(
            job.Id
        );
        System.assertEquals(0, results.size());
    }

    // ── verifyCertificate ───────────────────────────────────────────

    @IsTest
    static void testVerifyCertificateInvalid() {
        // Test with non-existent certificate
        try {
            QRNGSetupController.verifyCertificate(null);
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
            QRNGSetupController.retrieveJobResults(job.Id);
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
        QRNG_Settings__c s = new QRNG_Settings__c(
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
        Map<String, Object> result = QRNGSetupController.retrieveJobResults(
            job.Id
        );
        Test.stopTest();

        System.assertEquals('Completed', result.get('status'));
        System.assertNotEquals(null, result.get('certificateId'));
    }

    // ── getUsageStats ───────────────────────────────────────────────

    @IsTest
    static void testGetUsageStatsWithData() {
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

        Map<String, Object> stats = QRNGSetupController.getUsageStats();
        System.assertEquals(2, stats.get('totalJobs'));
        System.assertEquals(1, stats.get('completedJobs'));
        System.assertEquals(1, stats.get('failedJobs'));
    }

    // ── startIntegrityCheck / stopIntegrityCheck ────────────────────

    @IsTest
    static void testIntegrityCheckControls() {
        Test.startTest();
        QRNGSetupController.startIntegrityCheck();
        Test.stopTest();

        // Just verify it doesn't throw
        QRNGSetupController.stopIntegrityCheck();
        System.assert(true, 'Integrity check controls work');
    }

    // ── saveSettings edge cases ─────────────────────────────────────

    @IsTest
    static void testSaveSettingsPartialUpdate() {
        // First save
        QRNGSetupController.saveSettings(
            'key1',
            'crn:test',
            'backend1',
            1024,
            false,
            false,
            5
        );

        // Partial update — only change backend
        QRNGSetupController.saveSettings(
            null,
            null,
            'backend2',
            null,
            null,
            null,
            null
        );

        QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
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
}
