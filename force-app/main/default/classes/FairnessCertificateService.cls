/**
 * Creates and manages Fairness Certificates for QRNG jobs.
 * Generates SHA-256 hashes for audit trail integrity.
 */
public with sharing class FairnessCertificateService {
    /**
     * Create a Fairness Certificate for a completed quantum job.
     */
    public static Id createCertificate(
        Id jobId,
        String validationResultsJson,
        String certStatus
    ) {
        Quantum_Job__c job = [
            SELECT
                Id,
                IBM_Job_ID__c,
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

        Fairness_Certificate__c cert = new Fairness_Certificate__c(
            Quantum_Job__c = job.Id,
            IBM_Job_ID__c = job.IBM_Job_ID__c,
            Backend__c = job.Backend__c,
            Circuit_QASM__c = job.Circuit_QASM__c,
            Raw_Bitstring_Hash__c = computeSHA256(
                job.Raw_Results__c != null ? job.Raw_Results__c : ''
            ),
            Debiased_Bitstring_Hash__c = computeSHA256(
                job.Debiased_Results__c != null ? job.Debiased_Results__c : ''
            ),
            Validation_Results__c = validationResultsJson,
            Created_By_User__c = job.Requested_By__c,
            Purpose__c = job.Purpose__c,
            Status__c = certStatus
        );

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

        insert cert;
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

        Map<String, Object> result = new Map<String, Object>();

        String recomputedRawHash = computeSHA256(
            job.Raw_Results__c != null ? job.Raw_Results__c : ''
        );
        String recomputedDebiasedHash = computeSHA256(
            job.Debiased_Results__c != null ? job.Debiased_Results__c : ''
        );

        result.put(
            'rawHashMatch',
            cert.Raw_Bitstring_Hash__c == recomputedRawHash
        );
        result.put(
            'debiasedHashMatch',
            cert.Debiased_Bitstring_Hash__c == recomputedDebiasedHash
        );
        result.put(
            'integrityVerified',
            cert.Raw_Bitstring_Hash__c == recomputedRawHash &&
                cert.Debiased_Bitstring_Hash__c == recomputedDebiasedHash
        );

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
