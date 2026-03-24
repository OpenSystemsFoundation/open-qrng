/**
 * Interface for quantum computing provider abstraction.
 * Implementations wrap vendor-specific REST APIs (IBM, IonQ, Quantinuum, etc.)
 * behind a common contract for authentication, job submission, polling,
 * result retrieval, and backend management.
 *
 * Each provider must be stateless — all auth/config is resolved internally
 * via Named Credentials or Custom Settings.
 *
 * To add a new provider, implement this interface and register it in
 * QuantumProviderFactory. See PROVIDERS.md for a step-by-step guide.
 */
public interface QuantumProvider {
    // ── Identity ────────────────────────────────────────────────────

    /**
     * Return the unique provider identifier (e.g. 'ibm', 'ionq', 'quantinuum').
     */
    String getProviderName();

    // ── Authentication ──────────────────────────────────────────────

    /**
     * Authenticate with the provider and return an access token or session identifier.
     * Implementations may cache tokens internally.
     */
    String authenticate();

    /**
     * Test the provider connection using the stored credentials.
     * @return true if the provider is reachable and credentials are valid
     */
    Boolean testConnection();

    // ── Job lifecycle ───────────────────────────────────────────────

    /**
     * Submit a standard quantum job.
     * @param openqasm  OpenQASM 3.0 circuit string
     * @param backend   Provider-specific backend name
     * @param shots     Number of measurement shots
     * @return External job ID assigned by the provider
     */
    String submitJob(String openqasm, String backend, Integer shots);

    /**
     * Submit a QRNG job with full metadata and create a Quantum_Job__c record.
     * Returns the Salesforce record Id of the created job.
     * @param openqasm    OpenQASM 3.0 circuit string
     * @param backend     Provider-specific backend name
     * @param shots       Number of measurement shots
     * @param purpose     Human-readable purpose description
     * @param useBellTest Whether this is a Bell test job
     * @param numQubits   Number of qubits used
     * @return Id of the created Quantum_Job__c record
     */
    Id submitTrackedJob(
        String openqasm,
        String backend,
        Integer shots,
        String purpose,
        Boolean useBellTest,
        Integer numQubits
    );

    /**
     * Poll the provider for current job status.
     * @param externalJobId  The provider's job identifier
     * @return Map with at least 'status' key; may include provider-specific metadata
     */
    Map<String, Object> getJobStatus(String externalJobId);

    /**
     * Retrieve completed job results as raw JSON.
     * @param externalJobId  The provider's job identifier
     * @return Raw results JSON string from the provider
     */
    String getJobResults(String externalJobId);

    // ── Backend discovery & health ──────────────────────────────────

    /**
     * List available quantum backends from this provider.
     * @return List of backend descriptors, each containing at least 'name' and 'status'
     */
    List<Map<String, Object>> listBackends();

    /**
     * Get detailed properties for a specific backend (T1, T2, gate errors, etc.).
     * @param backendName  Provider-specific backend identifier
     * @return Map of backend properties in provider-native format
     */
    Map<String, Object> getBackendProperties(String backendName);

    /**
     * Select the least busy (shortest queue) backend.
     * @return Backend name, or null if the provider does not support queue inspection
     */
    String getLeastBusyBackend();

    // ── Circuit building ────────────────────────────────────────────

    /**
     * Build a provider-optimized QRNG circuit for the given backend.
     * The provider may select optimal physical qubits based on calibration data.
     * @param numQubits    Number of logical qubits
     * @param backendName  Target backend (for qubit selection optimization)
     * @param useBellTest  Whether to build a Bell test circuit
     * @return OpenQASM 3.0 circuit string
     */
    String buildCircuit(
        Integer numQubits,
        String backendName,
        Boolean useBellTest
    );

    // ── Verification ────────────────────────────────────────────────

    /**
     * Submit a CHSH Bell test verification job for a backend.
     * Returns the Salesforce record Id of the verification job.
     * Providers implement this using their native observables/estimation API.
     * @param backendName  Backend to verify
     * @param shots        Number of measurement shots
     * @return Id of the created Quantum_Job__c record
     */
    Id submitVerificationJob(String backendName, Integer shots);

    // ── Provider-specific configuration ─────────────────────────────

    /**
     * Discover provider-specific instances, accounts, or projects.
     * For IBM this returns CRN instances; for IonQ it might return API projects.
     * @return List of maps with 'name' and provider-specific identifiers
     */
    List<Map<String, String>> discoverInstances();
}
