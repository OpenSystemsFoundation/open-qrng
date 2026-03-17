/**
 * Interface for quantum computing provider abstraction.
 * Implementations wrap vendor-specific REST APIs (IBM, IonQ, etc.)
 * behind a common contract for job submission, polling, and result retrieval.
 *
 * Each provider must be stateless — all auth/config is resolved internally
 * via Named Credentials or Custom Settings.
 */
public interface QuantumProvider {
    /**
     * Return the unique provider identifier (e.g. 'ibm', 'ionq', 'quantinuum').
     */
    String getProviderName();

    /**
     * Authenticate with the provider and return an access token or session identifier.
     * Implementations may cache tokens internally.
     */
    String authenticate();

    /**
     * Submit a quantum job.
     * @param openqasm  OpenQASM 3.0 circuit string
     * @param backend   Provider-specific backend name
     * @param shots     Number of measurement shots
     * @return External job ID assigned by the provider
     */
    String submitJob(String openqasm, String backend, Integer shots);

    /**
     * Poll the provider for current job status.
     * @param externalJobId  The provider's job identifier
     * @return Map with at least 'status' key; may include provider-specific metadata
     */
    Map<String, Object> getJobStatus(String externalJobId);

    /**
     * Retrieve completed job results.
     * @param externalJobId  The provider's job identifier
     * @return Raw results JSON string from the provider
     */
    String getJobResults(String externalJobId);

    /**
     * List available quantum backends from this provider.
     * @return List of backend descriptors, each containing at least 'name' and 'status'
     */
    List<Map<String, Object>> listBackends();

    /**
     * Get detailed properties for a specific backend (T1, T2, gate errors, etc.).
     * @param backendName  Provider-specific backend identifier
     * @return Map of backend properties
     */
    Map<String, Object> getBackendProperties(String backendName);
}
