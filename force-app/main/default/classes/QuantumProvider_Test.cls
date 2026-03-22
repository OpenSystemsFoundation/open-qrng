/**
 * Tests for the QuantumProvider interface.
 * Uses a mock implementation to verify the interface contract
 * can be implemented, invoked, and used polymorphically.
 */
@IsTest
private class QuantumProvider_Test {
    /**
     * Mock QuantumProvider that returns deterministic test data.
     * Covers every method in the interface.
     */
    private class MockQuantumProvider implements QuantumProvider {
        public Boolean authenticateCalled = false;
        public Boolean testConnectionCalled = false;
        public Boolean submitJobCalled = false;
        public String lastOpenqasm;
        public String lastBackend;
        public Integer lastShots;

        public String getProviderName() {
            return 'mock';
        }

        public String authenticate() {
            authenticateCalled = true;
            return 'mock-token-abc123';
        }

        public Boolean testConnection() {
            testConnectionCalled = true;
            return true;
        }

        public String submitJob(
            String openqasm,
            String backend,
            Integer shots
        ) {
            submitJobCalled = true;
            lastOpenqasm = openqasm;
            lastBackend = backend;
            lastShots = shots;
            return 'mock-job-id-001';
        }

        public Id submitTrackedJob(
            String openqasm,
            String backend,
            Integer shots,
            String purpose,
            Boolean useBellTest,
            Integer numQubits
        ) {
            // Return a fake Account Id — we cannot insert Quantum_Job__c
            // without schema setup in a pure unit test
            return null;
        }

        public Map<String, Object> getJobStatus(String externalJobId) {
            return new Map<String, Object>{
                'status' => 'Completed',
                'id' => externalJobId
            };
        }

        public String getJobResults(String externalJobId) {
            return '{"results":[{"data":{"c":{"samples":["01101001","11010010"]}}}]}';
        }

        public List<Map<String, Object>> listBackends() {
            List<Map<String, Object>> backends = new List<Map<String, Object>>();
            backends.add(
                new Map<String, Object>{
                    'name' => 'mock_backend_1',
                    'status' => 'online',
                    'qubits' => 156
                }
            );
            backends.add(
                new Map<String, Object>{
                    'name' => 'mock_backend_2',
                    'status' => 'online',
                    'qubits' => 127
                }
            );
            return backends;
        }

        public Map<String, Object> getBackendProperties(String backendName) {
            return new Map<String, Object>{
                'backend_name' => backendName,
                'qubits' => new List<Object>(),
                'gates' => new List<Object>()
            };
        }

        public String getLeastBusyBackend() {
            return 'mock_backend_1';
        }

        public String buildCircuit(
            Integer numQubits,
            String backendName,
            Boolean useBellTest
        ) {
            return 'OPENQASM 3.0;\ninclude "stdgates.inc";\nqubit[' +
                numQubits +
                '] q;\nbit[' +
                numQubits +
                '] c;\nh q;\nmeasure q -> c;';
        }

        public Id submitVerificationJob(String backendName, Integer shots) {
            return null;
        }

        public List<Map<String, String>> discoverInstances() {
            List<Map<String, String>> instances = new List<Map<String, String>>();
            instances.add(
                new Map<String, String>{
                    'name' => 'Mock Instance',
                    'crn' => 'crn:v1:mock:public:quantum-computing:us-east:a/abc123:::'
                }
            );
            return instances;
        }
    }

    @IsTest
    static void testGetProviderName() {
        QuantumProvider provider = new MockQuantumProvider();

        System.assertEquals(
            'mock',
            provider.getProviderName(),
            'Provider name should be mock'
        );
    }

    @IsTest
    static void testAuthenticate() {
        MockQuantumProvider mock = new MockQuantumProvider();
        QuantumProvider provider = mock;

        Test.startTest();
        String token = provider.authenticate();
        Test.stopTest();

        System.assertEquals(true, mock.authenticateCalled);
        System.assertEquals(
            'mock-token-abc123',
            token,
            'Should return mock token'
        );
    }

    @IsTest
    static void testTestConnection() {
        MockQuantumProvider mock = new MockQuantumProvider();
        QuantumProvider provider = mock;

        Test.startTest();
        Boolean connected = provider.testConnection();
        Test.stopTest();

        System.assertEquals(true, mock.testConnectionCalled);
        System.assertEquals(true, connected);
    }

    @IsTest
    static void testSubmitJob() {
        MockQuantumProvider mock = new MockQuantumProvider();
        QuantumProvider provider = mock;
        String qasm = 'OPENQASM 3.0;\nqubit[8] q;\nh q;\nmeasure q;';

        Test.startTest();
        String jobId = provider.submitJob(qasm, 'ibm_brisbane', 4096);
        Test.stopTest();

        System.assertEquals(true, mock.submitJobCalled);
        System.assertEquals(qasm, mock.lastOpenqasm);
        System.assertEquals('ibm_brisbane', mock.lastBackend);
        System.assertEquals(4096, mock.lastShots);
        System.assertEquals('mock-job-id-001', jobId);
    }

    @IsTest
    static void testSubmitTrackedJobReturnsNull() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        Id jobId = provider.submitTrackedJob(
            'OPENQASM 3.0;',
            'ibm_brisbane',
            1024,
            'Test purpose',
            false,
            8
        );
        Test.stopTest();

        System.assertEquals(null, jobId, 'Mock returns null for tracked job');
    }

    @IsTest
    static void testGetJobStatus() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        Map<String, Object> status = provider.getJobStatus('ext-job-123');
        Test.stopTest();

        System.assertEquals('Completed', status.get('status'));
        System.assertEquals('ext-job-123', status.get('id'));
    }

    @IsTest
    static void testGetJobResults() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        String results = provider.getJobResults('ext-job-123');
        Test.stopTest();

        System.assert(
            results.contains('samples'),
            'Results should contain measurement samples'
        );
    }

    @IsTest
    static void testListBackends() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        List<Map<String, Object>> backends = provider.listBackends();
        Test.stopTest();

        System.assertEquals(2, backends.size());
        System.assertEquals('mock_backend_1', backends[0].get('name'));
        System.assertEquals(156, backends[0].get('qubits'));
    }

    @IsTest
    static void testGetBackendProperties() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        Map<String, Object> props = provider.getBackendProperties(
            'ibm_brisbane'
        );
        Test.stopTest();

        System.assertEquals('ibm_brisbane', props.get('backend_name'));
    }

    @IsTest
    static void testGetLeastBusyBackend() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        String backend = provider.getLeastBusyBackend();
        Test.stopTest();

        System.assertEquals('mock_backend_1', backend);
    }

    @IsTest
    static void testBuildCircuit() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        String circuit = provider.buildCircuit(8, 'ibm_brisbane', false);
        Test.stopTest();

        System.assert(
            circuit.contains('OPENQASM 3.0'),
            'Circuit should be valid OpenQASM'
        );
        System.assert(
            circuit.contains('qubit[8]'),
            'Circuit should use requested qubit count'
        );
    }

    @IsTest
    static void testBuildBellTestCircuit() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        String circuit = provider.buildCircuit(2, 'ibm_brisbane', true);
        Test.stopTest();

        System.assert(
            circuit.contains('OPENQASM 3.0'),
            'Bell test circuit should be valid OpenQASM'
        );
    }

    @IsTest
    static void testSubmitVerificationJob() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        Id jobId = provider.submitVerificationJob('ibm_brisbane', 8192);
        Test.stopTest();

        System.assertEquals(null, jobId, 'Mock returns null');
    }

    @IsTest
    static void testDiscoverInstances() {
        QuantumProvider provider = new MockQuantumProvider();

        Test.startTest();
        List<Map<String, String>> instances = provider.discoverInstances();
        Test.stopTest();

        System.assertEquals(1, instances.size());
        System.assertEquals('Mock Instance', instances[0].get('name'));
        System.assert(
            instances[0].get('crn').startsWith('crn:'),
            'CRN should start with crn: prefix'
        );
    }

    @IsTest
    static void testPolymorphicUsage() {
        // Verify the interface can be stored and used as a generic reference
        List<QuantumProvider> providers = new List<QuantumProvider>();
        providers.add(new MockQuantumProvider());

        for (QuantumProvider p : providers) {
            System.assertNotEquals(null, p.getProviderName());
            System.assertNotEquals(null, p.getLeastBusyBackend());
        }
    }
}
