/**
 * Creates and manages Fairness Certificates for QRNG jobs.
 * Generates SHA-256 hashes for audit trail integrity.
 *
 * One job = one certificate. Re-retrieving results updates the existing cert.
 */
public with sharing class FairnessCertificateService {
    /**
     * Create a Fairness Certificate for a completed quantum job.
     * If a certificate already exists for this job, update it instead.
     */
    public static Id createCertificate(
        Id jobId,
        String validationResultsJson,
        String certStatus
    ) {
        Quantum_Job__c job = [
            SELECT
                Id,
                External_Job_ID__c,
                Backend__c,
                Circuit_QASM__c,
                Raw_Results__c,
                Debiased_Results__c,
                Purpose__c,
                Requested_By__c,
                Use_Bell_Test__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        String rawHash = computeSHA256(
            job.Raw_Results__c != null ? job.Raw_Results__c : ''
        );
        String debiasedHash = computeSHA256(
            job.Debiased_Results__c != null ? job.Debiased_Results__c : ''
        );

        // Check for existing certificate for this job
        List<Fairness_Certificate__c> existing = [
            SELECT Id
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Fairness_Certificate__c cert;
        if (!existing.isEmpty()) {
            // Update existing certificate with fresh hashes
            cert = existing[0];
            cert.Raw_Bitstring_Hash__c = rawHash;
            cert.Debiased_Bitstring_Hash__c = debiasedHash;
            cert.Validation_Results__c = validationResultsJson;
            cert.Status__c = certStatus;
            cert.Tampered__c = false;
            cert.Last_Integrity_Check__c = DateTime.now();
        } else {
            // Create new certificate
            cert = new Fairness_Certificate__c(
                Quantum_Job__c = job.Id,
                External_Job_ID__c = job.External_Job_ID__c,
                Backend__c = job.Backend__c,
                Circuit_QASM__c = job.Circuit_QASM__c,
                Raw_Bitstring_Hash__c = rawHash,
                Debiased_Bitstring_Hash__c = debiasedHash,
                Validation_Results__c = validationResultsJson,
                Created_By_User__c = job.Requested_By__c,
                Purpose__c = job.Purpose__c,
                Status__c = certStatus,
                Tampered__c = false,
                Last_Integrity_Check__c = DateTime.now()
            );
        }

        // Parse validation results for CHSH value if present
        if (String.isNotBlank(validationResultsJson)) {
            try {
                Map<String, Object> valResults = (Map<String, Object>) JSON.deserializeUntyped(
                    validationResultsJson
                );
                if (valResults.containsKey('chshSValue')) {
                    cert.CHSH_S_Value__c = (Double) valResults.get(
                        'chshSValue'
                    );
                }
            } catch (Exception e) {
                // Non-critical - continue without CHSH value
            }
        }

        // Stamp backend verification status at certificate creation time
        if (String.isNotBlank(job.Backend__c)) {
            List<QRNG_Backend__c> backends = [
                SELECT
                    Id,
                    Quantum_Verified__c,
                    CHSH_S_Value__c,
                    CHSH_Verified_At__c
                FROM QRNG_Backend__c
                WHERE Name = :job.Backend__c
                LIMIT 1
            ];
            if (!backends.isEmpty()) {
                QRNG_Backend__c backend = backends[0];
                cert.Backend_Verified__c = backend.Quantum_Verified__c;
                cert.Backend_Verified_At__c = backend.CHSH_Verified_At__c;
                // Also populate CHSH S-value from backend if not set by job
                if (
                    cert.CHSH_S_Value__c == null &&
                    backend.CHSH_S_Value__c != null
                ) {
                    cert.CHSH_S_Value__c = backend.CHSH_S_Value__c;
                }
            }
        }

        upsert cert;
        return cert.Id;
    }

    /**
     * Update the assignment hash on a certificate after assignments are created.
     */
    public static void updateAssignmentHash(
        Id certificateId,
        String assignmentData
    ) {
        Fairness_Certificate__c cert = new Fairness_Certificate__c(
            Id = certificateId,
            Assignment_Hash__c = computeSHA256(assignmentData)
        );
        update cert;
    }

    /**
     * Verify integrity of a certificate by re-computing hashes.
     * Sets or clears the Tampered__c flag on the record.
     */
    public static Map<String, Object> verifyCertificate(Id certificateId) {
        Fairness_Certificate__c cert = [
            SELECT
                Id,
                Quantum_Job__c,
                Raw_Bitstring_Hash__c,
                Debiased_Bitstring_Hash__c,
                Assignment_Hash__c
            FROM Fairness_Certificate__c
            WHERE Id = :certificateId
            LIMIT 1
        ];

        Quantum_Job__c job = [
            SELECT Id, Raw_Results__c, Debiased_Results__c
            FROM Quantum_Job__c
            WHERE Id = :cert.Quantum_Job__c
            LIMIT 1
        ];

        String recomputedRawHash = computeSHA256(
            job.Raw_Results__c != null ? job.Raw_Results__c : ''
        );
        String recomputedDebiasedHash = computeSHA256(
            job.Debiased_Results__c != null ? job.Debiased_Results__c : ''
        );

        Boolean rawMatch = cert.Raw_Bitstring_Hash__c == recomputedRawHash;
        Boolean debiasedMatch =
            cert.Debiased_Bitstring_Hash__c == recomputedDebiasedHash;
        Boolean verified = rawMatch && debiasedMatch;

        // Update tampered flag and last check timestamp
        cert.Tampered__c = !verified;
        cert.Last_Integrity_Check__c = DateTime.now();
        update cert;

        Map<String, Object> result = new Map<String, Object>();
        result.put('rawHashMatch', rawMatch);
        result.put('debiasedHashMatch', debiasedMatch);
        result.put('integrityVerified', verified);
        return result;
    }

    /**
     * Compute SHA-256 hash of input string.
     */
    public static String computeSHA256(String input) {
        Blob inputBlob = Blob.valueOf(input);
        Blob hashBlob = Crypto.generateDigest('SHA-256', inputBlob);
        return EncodingUtil.convertToHex(hashBlob);
    }
}
