/**
 * REST API client for IBM Qiskit Runtime.
 * Handles job submission, status polling, and result retrieval.
 *
 * Base URL: https://quantum.cloud.ibm.com/api
 * Governor limits: 1-2 callouts per invocation
 */
public with sharing class IBMQuantumService {

    private static final String BASE_URL = 'https://quantum.cloud.ibm.com/api';

    /**
     * Submit a QRNG job to IBM Quantum Runtime.
     * Creates Quantum_Job__c record and returns its Id.
     */
    public static Id submitJob(String openqasm, String backend, Integer shots, String purpose, Boolean useBellTest, Integer numQubits) {
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
            IBM_Job_ID__c = ibmJobId,
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
    public static String callSubmitJob(String openqasm, String backend, Integer shots) {
        String token = IBMQuantumAuth.getAccessToken();

        // Build request body per IBM Qiskit Runtime API
        Map<String, Object> body = new Map<String, Object>();
        body.put('program_id', 'sampler');
        body.put('backend', backend);

        Map<String, Object> params = new Map<String, Object>();
        List<Object> pubs = new List<Object>();
        List<Object> pub = new List<Object>();
        pub.add(openqasm);
        pub.add(null);  // no observables
        pub.add(shots);
        pubs.add(pub);
        params.put('pubs', pubs);
        params.put('version', 2);
        body.put('params', params);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
            throw new QRNGException('IBM job submission failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) responseMap.get('id');
    }

    /**
     * Get job status from IBM
     */
    public static Map<String, Object> getJobStatus(String ibmJobId) {
        String token = IBMQuantumAuth.getAccessToken();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs/' + ibmJobId);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QRNGException('Failed to get job status: ' + res.getStatusCode());
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Get job results from IBM (only call when status is Completed)
     */
    public static String getJobResults(String ibmJobId) {
        String token = IBMQuantumAuth.getAccessToken();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/jobs/' + ibmJobId + '/results');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setTimeout(60000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QRNGException('Failed to get job results: ' + res.getStatusCode());
        }

        return res.getBody();
    }

    /**
     * Get available backends from IBM
     */
    public static String getBackends() {
        String token = IBMQuantumAuth.getAccessToken();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + '/v1/backends');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setTimeout(30000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() != 200) {
            throw new QRNGException('Failed to get backends: ' + res.getStatusCode());
        }

        return res.getBody();
    }
}
