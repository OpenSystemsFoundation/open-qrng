/**
 * IBM Quantum implementation of the QuantumProvider interface.
 * Delegates to existing IBMQuantumService and IBMQuantumAuth classes
 * for all API communication, and to CircuitBuilder for circuit generation.
 *
 * This is the reference provider implementation. To add a new provider
 * (e.g. IonQ, Quantinuum), create a similar class implementing QuantumProvider
 * and register it in QuantumProviderFactory. See docs/solution-design.md (Extensibility) for details.
 *
 * Governor limits: delegates to IBMQuantumService (1-2 callouts per method)
 */
public with sharing class IBMQuantumProvider implements QuantumProvider {
    // ── Identity ────────────────────────────────────────────────────

    public String getProviderName() {
        return 'ibm';
    }

    // ── Authentication ──────────────────────────────────────────────

    public String authenticate() {
        return IBMQuantumAuth.getAccessToken();
    }

    public Boolean testConnection() {
        return IBMQuantumAuth.testApiKey();
    }

    // ── Job lifecycle ───────────────────────────────────────────────

    public String submitJob(String openqasm, String backend, Integer shots) {
        return IBMQuantumService.callSubmitJob(openqasm, backend, shots);
    }

    public Id submitTrackedJob(
        String openqasm,
        String backend,
        Integer shots,
        String purpose,
        Boolean useBellTest,
        Integer numQubits
    ) {
        return IBMQuantumService.submitJob(
            openqasm,
            backend,
            shots,
            purpose,
            useBellTest,
            numQubits
        );
    }

    public Map<String, Object> getJobStatus(String externalJobId) {
        return IBMQuantumService.getJobStatus(externalJobId);
    }

    public String getJobResults(String externalJobId) {
        return IBMQuantumService.getJobResults(externalJobId);
    }

    // ── Backend discovery & health ──────────────────────────────────

    public List<Map<String, Object>> listBackends() {
        String backendsJson = IBMQuantumService.getBackends();
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            backendsJson
        );

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
            backendInfo.put(
                'status',
                deviceMap.containsKey('status')
                    ? deviceMap.get('status')
                    : 'unknown'
            );
            backendInfo.put(
                'qubits',
                deviceMap.containsKey('qubits')
                    ? deviceMap.get('qubits')
                    : (deviceMap.containsKey('num_qubits')
                          ? deviceMap.get('num_qubits')
                          : 0)
            );
            // IBM-specific fields — other providers may omit these
            if (deviceMap.containsKey('pending_jobs')) {
                backendInfo.put('queueLength', deviceMap.get('pending_jobs'));
            } else if (deviceMap.containsKey('queue_length')) {
                backendInfo.put('queueLength', deviceMap.get('queue_length'));
            }
            if (deviceMap.containsKey('is_simulator')) {
                backendInfo.put('isSimulator', deviceMap.get('is_simulator'));
            }
            if (deviceMap.containsKey('processor_type')) {
                Map<String, Object> proc = (Map<String, Object>) deviceMap.get(
                    'processor_type'
                );
                if (proc != null) {
                    backendInfo.put('processorFamily', proc.get('family'));
                    backendInfo.put('processorRevision', proc.get('revision'));
                }
            }
            backends.add(backendInfo);
        }

        return backends;
    }

    public Map<String, Object> getBackendProperties(String backendName) {
        return IBMQuantumService.getBackendProperties(backendName);
    }

    public String getLeastBusyBackend() {
        return IBMQuantumService.getLeastBusyBackend();
    }

    // ── Circuit building ────────────────────────────────────────────

    public String buildCircuit(
        Integer numQubits,
        String backendName,
        Boolean useBellTest
    ) {
        // Fetch calibration data for qubit selection optimization
        Map<Integer, Double> readoutErrors;
        try {
            readoutErrors = IBMQuantumService.getReadoutErrors(backendName);
        } catch (Exception e) {
            readoutErrors = null;
        }

        if (useBellTest) {
            List<List<Integer>> couplingMap = IBMQuantumService.getCouplingMap(
                backendName
            );
            return CircuitBuilder.buildBellTestCircuit(
                numQubits / 2,
                couplingMap,
                readoutErrors
            );
        }
        return CircuitBuilder.buildStandardCircuit(numQubits, readoutErrors);
    }

    // ── Verification ────────────────────────────────────────────────

    public Id submitVerificationJob(String backendName, Integer shots) {
        // Fetch calibration data for best qubit pair selection
        List<List<Integer>> couplingMap = IBMQuantumService.getCouplingMap(
            backendName
        );
        Map<Integer, Double> readoutErrors;
        try {
            readoutErrors = IBMQuantumService.getReadoutErrors(backendName);
        } catch (Exception e) {
            readoutErrors = null;
        }
        Map<String, Double> gateErrors;
        try {
            gateErrors = IBMQuantumService.getGateErrors(backendName);
        } catch (Exception e) {
            gateErrors = null;
        }

        // Select the single best qubit pair
        CircuitBuilder.CoupledPair bestPair = CircuitBuilder.selectBestPair(
            couplingMap,
            readoutErrors,
            gateErrors
        );

        // Build 4 circuits with optimal CHSH measurement angles
        List<String> circuits = CircuitBuilder.buildCHSHVerificationCircuits(
            bestPair.q0,
            bestPair.q1
        );

        // Observable: ZZ on the active qubit pair
        Integer numCircuitQubits = Math.max(bestPair.q0, bestPair.q1) + 1;
        String zzObservable = buildPauliString(
            numCircuitQubits,
            bestPair.q0,
            bestPair.q1
        );

        return IBMQuantumService.submitCHSHEstimatorJob(
            circuits,
            zzObservable,
            backendName,
            shots,
            'CHSH backend verification'
        );
    }

    // ── Provider-specific configuration ─────────────────────────────

    public List<Map<String, String>> discoverInstances() {
        return IBMQuantumAuth.discoverInstances();
    }

    // ── Internal helpers ────────────────────────────────────────────

    /**
     * Build a ZZ Pauli string for the given qubit pair.
     * Pauli string convention: rightmost = qubit 0.
     */
    @TestVisible
    private static String buildPauliString(
        Integer numQubits,
        Integer qubitA,
        Integer qubitB
    ) {
        List<String> chars = new List<String>();
        for (Integer i = 0; i < numQubits; i++) {
            chars.add('I');
        }
        chars.set(qubitA, 'Z');
        chars.set(qubitB, 'Z');
        // Reverse so rightmost = qubit 0
        List<String> reversed = new List<String>();
        for (Integer i = numQubits - 1; i >= 0; i--) {
            reversed.add(chars.get(i));
        }
        return String.join(reversed, '');
    }
}
