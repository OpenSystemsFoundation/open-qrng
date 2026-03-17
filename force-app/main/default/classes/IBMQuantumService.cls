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
        QRNG_Settings__c settings = QRNG_Settings__c.getInstance();
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
        Integer lowestQueue = Integer.MAX_VALUE;

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
                : Integer.MAX_VALUE;

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
                Requested_By__c = UserInfo.getUserId(),
                Submitted_At__c = DateTime.now(),
                Error_Message__c = e.getMessage()
            );
            insert failedJob;

            QRNG_Failed__e failEvent = new QRNG_Failed__e(
                Job_Id__c = failedJob.Id,
                Error_Message__c = e.getMessage().left(255)
            );
            EventBus.publish(failEvent);

            throw new QRNGException('Job submission failed: ' + e.getMessage());
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
            Requested_By__c = UserInfo.getUserId(),
            Submitted_At__c = DateTime.now()
        );
        insert job;

        // Enqueue poller
        System.enqueueJob(new QRNGJobPoller(job.Id, ibmJobId, 0));

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
            throw new QRNGException(
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
            throw new QRNGException(
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
            throw new QRNGException(
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
            throw new QRNGException(
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
            throw new QRNGException(
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
            throw new QRNGException(
                'Failed to get backend properties: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
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
            throw new QRNGException(
                'Failed to get backend configuration: ' +
                    res.getStatusCode() +
                    ' ' +
                    res.getBody()
            );
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
}
