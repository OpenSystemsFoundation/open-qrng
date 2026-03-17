/**
 * IBM Quantum implementation of the QuantumProvider interface.
 * Thin wrapper that delegates to existing IBMQuantumService and IBMQuantumAuth classes.
 *
 * This class bridges the new provider abstraction with the existing IBM-specific
 * service layer. Future refactoring may inline the logic here, but for now this
 * avoids disrupting the working IBMQuantumService.
 *
 * Governor limits: delegates to IBMQuantumService (1-2 callouts per method)
 */
public with sharing class IBMQuantumProvider implements QuantumProvider {
    public String getProviderName() {
        return 'ibm';
    }

    public String authenticate() {
        return IBMQuantumAuth.getAccessToken();
    }

    public String submitJob(String openqasm, String backend, Integer shots) {
        return IBMQuantumService.callSubmitJob(openqasm, backend, shots);
    }

    public Map<String, Object> getJobStatus(String externalJobId) {
        return IBMQuantumService.getJobStatus(externalJobId);
    }

    public String getJobResults(String externalJobId) {
        return IBMQuantumService.getJobResults(externalJobId);
    }

    public List<Map<String, Object>> listBackends() {
        String backendsJson = IBMQuantumService.getBackends();
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(backendsJson);

        List<Map<String, Object>> backends = new List<Map<String, Object>>();
        List<Object> devices;

        if (response.containsKey('devices')) {
            devices = (List<Object>) response.get('devices');
        } else if (response.containsKey('backends')) {
            devices = (List<Object>) response.get('backends');
        } else {
            return backends;
        }

        for (Object device : devices) {
            Map<String, Object> deviceMap = (Map<String, Object>) device;
            Map<String, Object> backendInfo = new Map<String, Object>();
            backendInfo.put('name', deviceMap.get('name'));
            backendInfo.put('status', deviceMap.containsKey('status') ? deviceMap.get('status') : 'unknown');
            backendInfo.put('qubits', deviceMap.containsKey('qubits')
                ? deviceMap.get('qubits')
                : (deviceMap.containsKey('num_qubits') ? deviceMap.get('num_qubits') : 0));
            backends.add(backendInfo);
        }

        return backends;
    }

    public Map<String, Object> getBackendProperties(String backendName) {
        return IBMQuantumService.getBackendProperties(backendName);
    }
}
