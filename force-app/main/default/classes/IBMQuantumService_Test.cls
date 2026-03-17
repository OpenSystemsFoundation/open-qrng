@IsTest
private class IBMQuantumService_Test {
    private class MockSubmitSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"access_token":"test-token-abc","token_type":"Bearer","expires_in":3600}'
                );
            } else if (
                req.getEndpoint().contains('/v1/jobs') &&
                req.getMethod() == 'POST'
            ) {
                res.setStatusCode(200);
                res.setBody('{"id":"job_abc123","backend":"test_backend"}');
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
                    '{"id":"job_abc123","status":"Completed","state":{"status":"Completed"}}'
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
            } else if (
                req.getEndpoint().contains('/v1/backends/') &&
                req.getEndpoint().contains('/configuration')
            ) {
                res.setStatusCode(200);
                res.setBody(
                    '{"backend_name":"test_backend","n_qubits":156,"basis_gates":["cx","id","rz","sx","x"],"max_shots":100000}'
                );
            } else if (req.getEndpoint().contains('/v1/backends')) {
                res.setStatusCode(200);
                res.setBody(
                    '{"devices":[' +
                        '{"name":"test_backend","status":"online","qubits":156,"is_simulator":false,"queue_length":5},' +
                        '{"name":"busy_backend","status":"online","qubits":127,"is_simulator":false,"queue_length":50},' +
                        '{"name":"offline_backend","status":"offline","qubits":65,"is_simulator":false,"queue_length":0},' +
                        '{"name":"sim_backend","status":"online","qubits":32,"is_simulator":true,"queue_length":0}' +
                        ']}'
                );
            }
            return res;
        }
    }

    @IsTest
    static void testSubmitJob() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        // Pre-set auth token and CRN
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        String qasm = QRNGCircuitBuilder.buildStandardCircuit(4);

        Test.startTest();
        Id jobId = IBMQuantumService.submitJob(
            qasm,
            'test_backend',
            1024,
            'Test purpose',
            false,
            4
        );
        Test.stopTest();

        Quantum_Job__c job = [
            SELECT Id, External_Job_ID__c, Status__c, Backend__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
        ];
        System.assertEquals('job_abc123', job.External_Job_ID__c);
        System.assertEquals('test_backend', job.Backend__c);
    }

    @IsTest
    static void testGetJobStatus() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Test.startTest();
        Map<String, Object> status = IBMQuantumService.getJobStatus(
            'job_abc123'
        );
        Test.stopTest();

        System.assertNotEquals(null, status);
    }

    @IsTest
    static void testGetJobResults() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Test.startTest();
        String results = IBMQuantumService.getJobResults('job_abc123');
        Test.stopTest();

        System.assert(
            results.contains('samples'),
            'Results should contain samples'
        );
    }

    @IsTest
    static void testGetBackends() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        Test.startTest();
        String backends = IBMQuantumService.getBackends();
        Test.stopTest();

        System.assert(
            backends.contains('test_backend'),
            'Should contain backend info'
        );
    }

    @IsTest
    static void testGetLeastBusyBackend() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        String bestBackend = IBMQuantumService.getLeastBusyBackend();
        Test.stopTest();

        // test_backend has queue_length=5, busy_backend has 50, offline is skipped, sim is skipped
        System.assertEquals(
            'test_backend',
            bestBackend,
            'Should return backend with lowest queue length'
        );
    }

    @IsTest
    static void testGetBackendProperties() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        Map<String, Object> props = IBMQuantumService.getBackendProperties(
            'test_backend'
        );
        Test.stopTest();

        System.assertNotEquals(null, props, 'Properties should not be null');
        System.assert(props.containsKey('qubits'), 'Should contain qubits');
        System.assert(props.containsKey('gates'), 'Should contain gates');
        System.assertEquals(
            '2026-03-15T10:00:00Z',
            props.get('last_update_date'),
            'Should contain last_update_date'
        );
    }

    @IsTest
    static void testGetBackendConfiguration() {
        Test.setMock(HttpCalloutMock.class, new MockSubmitSuccess());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);
        QRNG_Settings__c s = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Instance_CRN__c = 'crn:v1:bluemix:public:quantum-computing:test'
        );
        upsert s;

        Test.startTest();
        Map<String, Object> config = IBMQuantumService.getBackendConfiguration(
            'test_backend'
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            config,
            'Configuration should not be null'
        );
        System.assertEquals(
            'test_backend',
            config.get('backend_name'),
            'Should contain backend_name'
        );
        System.assertEquals(
            156,
            config.get('n_qubits'),
            'Should contain n_qubits'
        );
    }
}
