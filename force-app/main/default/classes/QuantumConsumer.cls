/**
 * Interface for custom QRNG consumers.
 * Implement this to receive quantum randomness in subscriber orgs.
 * Register implementing classes via Custom Metadata.
 */
public interface QuantumConsumer {
    void onRandomnessReady(Id certificateId, List<String> randomBits);
    void onRandomnessFailed(Id jobId, String errorMessage);
}
