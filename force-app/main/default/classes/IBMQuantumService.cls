/**
 * REST API client for IBM Qiskit Runtime.
 * Handles job submission, status polling, and result retrieval.
 *
 * Base URL: https://quantum.cloud.ibm.com/api
 * Governor limits: 1-2 callouts per invocation
 */
public with sharing class IBMQuantumService {
    private static final String BASE_URL = 'https://quantum.cloud.ibm.com/api';
    private static final String IBM_API_VERSION = '2025-11-01';

    /**
     * Get the Instance CRN from settings.
     */
    private static String getInstanceCRN() {
        Quantum_Settings__c settings = Quantum_Settings__c.getInstance();
        return settings != null ? settings.Instance_CRN__c : null;
    }

    /**
     * Find the least busy operational backend.
     * Calls /v1/backends and returns the backend name with the lowest queue_length.
     *
     * Governor limits: 1 callout
     */
    public static String getLeastBusyBackend() {
        String backendsJson = getBackends();
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            backendsJson
        );

        List<Object> devices;
        if (response.containsKey('devices')) {
            devices = (List<Object>) response.get('devices');
        } else if (response.containsKey('backends')) {
            devices = (List<Object>) response.get('backends');
        } else {
            return null;
        }

        String bestBackend = null;
        Integer lowestQueue = 2147483647;

        for (Object device : devices) {
            Map<String, Object> d = (Map<String, Object>) device;

            // Check status - only consider online backends
            Object statusObj = d.get('status');
            String statusName;
            if (statusObj instanceof Map<String, Object>) {
                statusName = (String) ((Map<String, Object>) statusObj)
                    .get('name');
            } else {
                statusName = String.valueOf(statusObj);
            }
            if (statusName != 'online') {
                continue;
            }

            // Skip simulators
            Boolean isSim = d.containsKey('is_simulator')
                ? (Boolean) d.get('is_simulator')
                : false;
            if (isSim) {
                continue;
            }

            Integer queueLen = d.containsKey('queue_length')
                ? (Integer) d.get('queue_length')
                : 2147483647;

            if (queueLen < lowestQueue) {
                lowestQueue = queueLen;
                bestBackend = (String) d.get('name');
            }
        }

        return bestBackend;
    }

    /**
     * Submit a QRNG job to IBM Quantum Runtime.
     * Creates Quantum_Job__c record and returns its Id.
     */
    public static Id submitJob(
        String openqasm,
        String backend,
        Integer shots,
        String purpose,
        Boolean useBellTest,
        Integer numQubits
    ) {
        // Callout first (before any DML to avoid mixed DML/callout error)
        String ibmJobId;
        try {
            ibmJobId = callSubmitJob(openqasm, backend, shots);
        } catch (Exception e) {
            // Create a failed job record for audit trail
            Quantum_Job__c failedJob = new Quantum_Job__c(
                Backend__c = backend,
                Status__c = 'Failed',
                Circuit_QASM__c = openqasm,
                Shots__c = shots,
                Num_Qubits__c = numQubits,
                Purpose__c = purpose,
                Use_Bell_Test__c = useBellTest != null ? useBellTest : false,
                Job_Type__c = 'Quantum',
                Requested_By__c = UserInfo.getUserId(),
                Submitted_At__c = DateTime.now(),
                Error_Message__c = e.getMessage()
            );
            insert failedJob;

            Quantum_Job_Failed__e failEvent = new Quantum_Job_Failed__e(
                Job_Id__c = failedJob.Id,
                Error_Message__c = e.getMessage().left(255)
            );
            EventBus.publish(failEvent);

            throw new QuantumException(
                'Job submission failed: ' + e.getMessage()
            );
        }

        // DML after callout succeeds
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = ibmJobId,
            Provider__c = 'ibm',
            Backend__c = backend,
            Status__c = 'Submitted',
            Circuit_QASM__c = openqasm,
            Shots__c = shots,
            Num_Qubits__c = numQubits,
            Purpose__c = purpose,
            Use_Bell_Test__c = useBellTest != null ? useBellTest : false,
            Job_Type__c = 'Quantum',
            Requested_By__c = UserInfo.getUserId(),
            Submitted_At__c = DateTime.now()
        );
        insert job;

        // Enqueue poller
        System.enqueueJob(new JobPoller(job.Id, ibmJobId, 0));

        return job.Id;
    }

    /**
     * Call IBM API to submit a job
     */
    public static String callSubmitJob(
        String openqasm,
        String backend,
        Integer shots
    ) {
        String token = IBMQuantumAuth.getAccessToken();

        // Build request body per IBM Qiskit Runtime API
        Map<String, Object> body = new Map<String, Object>();
        body.put('program_id', 'sampler');
        body.put('backend', backend);

        Map<String, Object> params = new Map<String, Object>();
        List<Object> pubs = new List<Object>();
        List<Object> pub = new List<Object>();
        pub.add(openqasm);
        pub.add(null); // no observables
        pub.add(shots);
        pubs.add(pub);
        params.put('pubs', pubs);
        params.put('version', 2);
        body.put('params', params);

        String instanceCRN = getInstanceCRN();
        if (String.isBlank(instanceCRN)) {
            throw new QuantumException(
                'Instance CRN not configured. Please set it in the Setup tab.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Service-CRN', instanceCRN);
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setBody(JSON.serialize(body));
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new QuantumException(
                'IBM job submission failed: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        return (String) responseMap.get('id');
    }

    /**
     * Get job status from IBM
     */
    public static Map<String, Object> getJobStatus(String ibmJobId) {
        String token = IBMQuantumAuth.getAccessToken();
        String instanceCRN = getInstanceCRN();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs/' + ibmJobId);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        if (String.isNotBlank(instanceCRN)) {
            req.setHeader('Service-CRN', instanceCRN);
        }
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QuantumException(
                'Failed to get job status: ' + res.getStatusCode()
            );
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Get job results from IBM (only call when status is Completed)
     */
    public static String getJobResults(String ibmJobId) {
        String token = IBMQuantumAuth.getAccessToken();
        String instanceCRN = getInstanceCRN();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs/' + ibmJobId + '/results');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        if (String.isNotBlank(instanceCRN)) {
            req.setHeader('Service-CRN', instanceCRN);
        }
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QuantumException(
                'Failed to get job results: ' + res.getStatusCode()
            );
        }

        return res.getBody();
    }

    /**
     * Get available backends from IBM
     */
    public static String getBackends() {
        String token = IBMQuantumAuth.getAccessToken();
        String instanceCRN = getInstanceCRN();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/backends');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        if (String.isNotBlank(instanceCRN)) {
            req.setHeader('Service-CRN', instanceCRN);
        }
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QuantumException(
                'Failed to get backends: ' + res.getStatusCode()
            );
        }

        return res.getBody();
    }

    /**
     * Get detailed backend properties (T1, T2, gate errors, readout errors).
     * Endpoint: GET /v1/backends/{backend}/properties
     *
     * Governor limits: 1 callout
     */
    public static Map<String, Object> getBackendProperties(String backendName) {
        String token = IBMQuantumAuth.getAccessToken();
        String instanceCRN = getInstanceCRN();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            BASE_URL +
                '/v1/backends/' +
                EncodingUtil.urlEncode(backendName, 'UTF-8') +
                '/properties'
        );
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        if (String.isNotBlank(instanceCRN)) {
            req.setHeader('Service-CRN', instanceCRN);
        }
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QuantumException(
                'Failed to get backend properties: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Extract coupling map from backend configuration as List<List<Integer>>.
     * Each inner list is a [q0, q1] connected pair.
     *
     * Governor limits: 1 callout
     */
    public static List<List<Integer>> getCouplingMap(String backendName) {
        Map<String, Object> config = getBackendConfiguration(backendName);
        List<List<Integer>> couplingMap = new List<List<Integer>>();

        // Try coupling_map (list of [q0, q1] pairs)
        if (config.containsKey('coupling_map')) {
            List<Object> edges = (List<Object>) config.get('coupling_map');
            for (Object edge : edges) {
                List<Object> pair = (List<Object>) edge;
                couplingMap.add(
                    new List<Integer>{ (Integer) pair[0], (Integer) pair[1] }
                );
            }
        }

        // Fallback: try gates array for cx/cz entries
        if (couplingMap.isEmpty() && config.containsKey('gates')) {
            List<Object> gates = (List<Object>) config.get('gates');
            Set<String> seen = new Set<String>();
            for (Object gObj : gates) {
                Map<String, Object> gate = (Map<String, Object>) gObj;
                String gateName = (String) gate.get('gate');
                if (gateName == 'cz' || gateName == 'cx' || gateName == 'ecr') {
                    List<Object> qubits = (List<Object>) gate.get('qubits');
                    if (qubits != null && qubits.size() == 2) {
                        Integer q0 = (Integer) qubits[0];
                        Integer q1 = (Integer) qubits[1];
                        String key = q0 + '-' + q1;
                        if (!seen.contains(key)) {
                            seen.add(key);
                            couplingMap.add(new List<Integer>{ q0, q1 });
                        }
                    }
                }
            }
        }

        return couplingMap;
    }

    /**
     * Extract per-qubit readout error rates from backend properties.
     * Returns Map of qubit index → readout error probability.
     *
     * Governor limits: 1 callout
     */
    public static Map<Integer, Double> getReadoutErrors(String backendName) {
        Map<String, Object> props = getBackendProperties(backendName);
        Map<Integer, Double> errors = new Map<Integer, Double>();

        // Try qubits array (list of qubit property lists)
        if (props.containsKey('qubits')) {
            List<Object> qubits = (List<Object>) props.get('qubits');
            for (Integer i = 0; i < qubits.size(); i++) {
                List<Object> qubitProps = (List<Object>) qubits[i];
                for (Object propObj : qubitProps) {
                    Map<String, Object> prop = (Map<String, Object>) propObj;
                    String propName = (String) prop.get('name');
                    if (
                        propName == 'readout_error' ||
                        propName == 'prob_meas1_prep0'
                    ) {
                        Object val = prop.get('value');
                        if (val != null) {
                            errors.put(i, (Double) val);
                        }
                        break;
                    }
                }
            }
        }

        return errors;
    }

    /**
     * Extract per-edge two-qubit gate error rates from backend properties.
     * Returns Map of "q0-q1" → gate error probability for CZ/ECR gates.
     * Used by selectBestPairs to weight entangling gate fidelity.
     *
     * Governor limits: 1 callout
     */
    public static Map<String, Double> getGateErrors(String backendName) {
        Map<String, Object> props = getBackendProperties(backendName);
        Map<String, Double> errors = new Map<String, Double>();

        if (props.containsKey('gates')) {
            List<Object> gates = (List<Object>) props.get('gates');
            for (Object gObj : gates) {
                Map<String, Object> gate = (Map<String, Object>) gObj;
                String gateName = (String) gate.get('gate');
                if (gateName == 'cz' || gateName == 'cx' || gateName == 'ecr') {
                    List<Object> qubits = (List<Object>) gate.get('qubits');
                    if (qubits != null && qubits.size() == 2) {
                        Integer q0 = (Integer) qubits[0];
                        Integer q1 = (Integer) qubits[1];
                        String key = q0 + '-' + q1;

                        // Extract gate error from parameters
                        if (gate.containsKey('parameters')) {
                            List<Object> params = (List<Object>) gate.get(
                                'parameters'
                            );
                            for (Object pObj : params) {
                                Map<String, Object> param = (Map<String, Object>) pObj;
                                String paramName = (String) param.get('name');
                                if (paramName == 'gate_error') {
                                    Object val = param.get('value');
                                    if (val != null) {
                                        errors.put(key, (Double) val);
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        return errors;
    }

    /**
     * Submit a CHSH verification job using IBM Estimator V2.
     * The Estimator handles measurement basis changes via observables,
     * so the circuit only needs to create a Bell state (no Ry rotations).
     *
     * Observable format: {"ZZ": 1.0, "ZX": -1.0, "XZ": 1.0, "XX": 1.0}
     * Returns the S-value directly as an expectation value.
     *
     * Governor limits: 1 callout
     */
    public static Id submitEstimatorJob(
        String openqasm,
        String backend,
        Map<String, Double> observables,
        Integer shots,
        String purpose
    ) {
        String ibmJobId;
        try {
            ibmJobId = callSubmitEstimatorJob(
                openqasm,
                backend,
                observables,
                shots
            );
        } catch (Exception e) {
            Quantum_Job__c failedJob = new Quantum_Job__c(
                Backend__c = backend,
                Status__c = 'Failed',
                Circuit_QASM__c = openqasm,
                Shots__c = shots,
                Num_Qubits__c = 2,
                Purpose__c = purpose,
                Program_Id__c = 'estimator',
                Requested_By__c = UserInfo.getUserId(),
                Submitted_At__c = DateTime.now(),
                Error_Message__c = e.getMessage()
            );
            insert failedJob;

            Quantum_Job_Failed__e failEvent = new Quantum_Job_Failed__e(
                Job_Id__c = failedJob.Id,
                Error_Message__c = e.getMessage().left(255)
            );
            EventBus.publish(failEvent);

            throw new QuantumException(
                'Estimator job submission failed: ' + e.getMessage()
            );
        }

        // Store observable labels in submission order so the poller
        // can map each result back to its Pauli term.
        Map<String, Object> submissionMeta = new Map<String, Object>();
        submissionMeta.put(
            'observableLabels',
            new List<String>(observables.keySet())
        );
        submissionMeta.put('observableCoeffs', observables);

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = ibmJobId,
            Provider__c = 'ibm',
            Backend__c = backend,
            Status__c = 'Submitted',
            Circuit_QASM__c = openqasm,
            Shots__c = shots,
            Num_Qubits__c = 2,
            Purpose__c = purpose,
            Program_Id__c = 'estimator',
            Requested_By__c = UserInfo.getUserId(),
            Submitted_At__c = DateTime.now(),
            Validation_Results__c = JSON.serialize(submissionMeta)
        );
        insert job;

        System.enqueueJob(new JobPoller(job.Id, ibmJobId, 0));

        return job.Id;
    }

    /**
     * Call IBM API to submit an Estimator V2 job.
     * PUB format: [circuit, observables, parameter_values, precision]
     */
    public static String callSubmitEstimatorJob(
        String openqasm,
        String backend,
        Map<String, Double> observables,
        Integer shots
    ) {
        String token = IBMQuantumAuth.getAccessToken();

        Map<String, Object> body = new Map<String, Object>();
        body.put('program_id', 'estimator');
        body.put('backend', backend);

        Map<String, Object> params = new Map<String, Object>();
        List<Object> pubs = new List<Object>();

        // Submit each Pauli term as a separate PUB so we get
        // individual expectation values for auditability.
        for (String pauliStr : observables.keySet()) {
            Map<String, Double> singleObs = new Map<String, Double>{
                pauliStr => 1.0
            };
            List<Object> pub = new List<Object>();
            pub.add(openqasm);
            pub.add(singleObs);
            pubs.add(pub);
        }
        params.put('pubs', pubs);
        params.put('version', 2);
        // M3 measurement error mitigation — needed to reliably exceed S > 2 on noisy hardware
        params.put('resilience_level', 1);
        body.put('params', params);

        String instanceCRN = getInstanceCRN();
        if (String.isBlank(instanceCRN)) {
            throw new QuantumException(
                'Instance CRN not configured. Please set it in the Setup tab.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Service-CRN', instanceCRN);
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setBody(JSON.serialize(body));
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new QuantumException(
                'IBM estimator job submission failed: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        return (String) responseMap.get('id');
    }

    /**
     * Submit a CHSH Estimator job with 4 circuits (one per measurement setting).
     * Each circuit is a Bell state + Ry basis rotations, evaluated against ZZ.
     * Returns the Quantum_Job__c record Id.
     *
     * @param circuits 4 QASM circuits in order: E(a,b), E(a,b'), E(a',b), E(a',b')
     * @param observable ZZ Pauli string for the active qubits
     * @param backend IBM backend name
     * @param shots Number of shots per circuit
     * @param purpose Job purpose description
     */
    public static Id submitCHSHEstimatorJob(
        List<String> circuits,
        String observable,
        String backend,
        Integer shots,
        String purpose
    ) {
        String ibmJobId;
        try {
            ibmJobId = callSubmitMultiCircuitEstimatorJob(
                circuits,
                observable,
                backend,
                shots
            );
        } catch (Exception e) {
            Quantum_Job__c failedJob = new Quantum_Job__c(
                Backend__c = backend,
                Status__c = 'Failed',
                Circuit_QASM__c = circuits[0],
                Shots__c = shots,
                Num_Qubits__c = 2,
                Purpose__c = purpose,
                Program_Id__c = 'estimator',
                Job_Type__c = 'CHSH Verification',
                Requested_By__c = UserInfo.getUserId(),
                Submitted_At__c = DateTime.now(),
                Error_Message__c = e.getMessage()
            );
            insert failedJob;

            Quantum_Job_Failed__e failEvent = new Quantum_Job_Failed__e(
                Job_Id__c = failedJob.Id,
                Error_Message__c = e.getMessage().left(255)
            );
            EventBus.publish(failEvent);

            throw new QuantumException(
                'CHSH Estimator job submission failed: ' + e.getMessage()
            );
        }

        // Store CHSH metadata: labels, coefficients, and all circuits
        // S = E(a,b) - E(a,b') + E(a',b) + E(a',b')
        List<String> pubLabels = new List<String>{
            'E(a,b)',
            'E(a,b\')',
            'E(a\',b)',
            'E(a\',b\')'
        };
        Map<String, Double> chshCoeffs = new Map<String, Double>{
            'E(a,b)' => 1.0,
            'E(a,b\')' => -1.0,
            'E(a\',b)' => 1.0,
            'E(a\',b\')' => 1.0
        };
        Map<String, Object> submissionMeta = new Map<String, Object>();
        submissionMeta.put('observableLabels', pubLabels);
        submissionMeta.put('observableCoeffs', chshCoeffs);
        submissionMeta.put('observable', observable);

        // Store all 4 circuits as JSON array in Circuit_QASM__c
        String allCircuits = JSON.serialize(circuits);

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = ibmJobId,
            Provider__c = 'ibm',
            Backend__c = backend,
            Status__c = 'Submitted',
            Circuit_QASM__c = allCircuits.left(131072),
            Shots__c = shots,
            Num_Qubits__c = 2,
            Purpose__c = purpose,
            Program_Id__c = 'estimator',
            Job_Type__c = 'CHSH Verification',
            Requested_By__c = UserInfo.getUserId(),
            Submitted_At__c = DateTime.now(),
            Validation_Results__c = JSON.serialize(submissionMeta)
        );
        insert job;

        System.enqueueJob(new JobPoller(job.Id, ibmJobId, 0));

        return job.Id;
    }

    /**
     * Call IBM API to submit a multi-circuit Estimator V2 job.
     * Each circuit gets the same observable as a separate PUB.
     */
    public static String callSubmitMultiCircuitEstimatorJob(
        List<String> circuits,
        String observable,
        String backend,
        Integer shots
    ) {
        String token = IBMQuantumAuth.getAccessToken();

        Map<String, Object> body = new Map<String, Object>();
        body.put('program_id', 'estimator');
        body.put('backend', backend);

        Map<String, Object> params = new Map<String, Object>();
        List<Object> pubs = new List<Object>();

        // One PUB per circuit, each with the same ZZ observable
        Map<String, Double> obs = new Map<String, Double>{ observable => 1.0 };
        for (String qasm : circuits) {
            List<Object> pub = new List<Object>();
            pub.add(qasm);
            pub.add(obs);
            pubs.add(pub);
        }
        params.put('pubs', pubs);
        params.put('version', 2);
        // No error mitigation — raw results prove genuine quantum behavior
        params.put('resilience_level', 0);
        body.put('params', params);

        String instanceCRN = getInstanceCRN();
        if (String.isBlank(instanceCRN)) {
            throw new QuantumException(
                'Instance CRN not configured. Please set it in the Setup tab.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Service-CRN', instanceCRN);
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setBody(JSON.serialize(body));
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new QuantumException(
                'IBM CHSH estimator job submission failed: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
        );
        return (String) responseMap.get('id');
    }

    /**
     * Get backend configuration (coupling map, basis gates, max_shots).
     * Endpoint: GET /v1/backends/{backend}/configuration
     *
     * Governor limits: 1 callout
     */
    public static Map<String, Object> getBackendConfiguration(
        String backendName
    ) {
        String token = IBMQuantumAuth.getAccessToken();
        String instanceCRN = getInstanceCRN();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            BASE_URL +
                '/v1/backends/' +
                EncodingUtil.urlEncode(backendName, 'UTF-8') +
                '/configuration'
        );
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        if (String.isNotBlank(instanceCRN)) {
            req.setHeader('Service-CRN', instanceCRN);
        }
        req.setHeader('IBM-API-Version', IBM_API_VERSION);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QuantumException(
                'Failed to get backend configuration: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
}
