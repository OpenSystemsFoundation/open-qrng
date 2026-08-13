/**
 * Creates and manages Fairness Certificates for QRNG jobs.
 * Generates SHA-256 hashes for audit trail integrity.
 * Maintains a sequential certificate chain where each certificate
 * stores the hash of its predecessor for tamper-evident ordering.
 *
 * One job = one certificate. Re-retrieving results updates the existing cert.
 */
public with sharing class FairnessCertificateService {
    private static final String GENESIS_HASH = computeSHA256('GENESIS');

    /**
     * Create a Fairness Certificate for a completed quantum job.
     * If a certificate already exists for this job, update it instead.
     * Links to the previous certificate in the chain for tamper-evident ordering.
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
            SELECT
                Id,
                Previous_Certificate__c,
                Previous_Certificate_Hash__c,
                Chain_Position__c,
                CHSH_S_Value__c
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Fairness_Certificate__c cert;
        if (
            !existing.isEmpty() &&
            existing[0].Previous_Certificate_Hash__c != null
        ) {
            // Re-certification of an already-chained certificate: the chain
            // link (predecessor hash, predecessor lookup, position) is
            // immutable — never re-link to the current chain tail. Only the
            // content hashes and the chain hash derived from the unchanged
            // link fields are refreshed.
            cert = existing[0];
            cert.Raw_Bitstring_Hash__c = rawHash;
            cert.Debiased_Bitstring_Hash__c = debiasedHash;
            cert.Validation_Results__c = validationResultsJson;
            cert.Status__c = certStatus;
            cert.Tampered__c = false;
            cert.Last_Integrity_Check__c = DateTime.now();
            cert.Chain_Hash__c = computeSHA256(
                rawHash + debiasedHash + cert.Previous_Certificate_Hash__c
            );
        } else {
            // New certificate (or legacy certificate without a chain link):
            // append to the chain tail. The tail is locked (FOR UPDATE) so
            // concurrent creators serialize instead of both linking to the
            // same predecessor.
            Fairness_Certificate__c tail = lockChainTail();
            String prevHash;
            Decimal prevPosition;
            Id prevCertId;
            if (tail != null) {
                prevHash = tail.Chain_Hash__c;
                prevPosition = tail.Chain_Position__c;
                prevCertId = tail.Id;
            } else {
                prevHash = GENESIS_HASH;
                prevPosition = 0;
                prevCertId = null;
            }

            // Chain hash: SHA-256(rawHash + debiasedHash + previousHash)
            String chainHash = computeSHA256(rawHash + debiasedHash + prevHash);

            if (!existing.isEmpty()) {
                cert = existing[0];
                cert.Raw_Bitstring_Hash__c = rawHash;
                cert.Debiased_Bitstring_Hash__c = debiasedHash;
                cert.Validation_Results__c = validationResultsJson;
                cert.Status__c = certStatus;
                cert.Tampered__c = false;
                cert.Last_Integrity_Check__c = DateTime.now();
                cert.Chain_Hash__c = chainHash;
                cert.Previous_Certificate__c = prevCertId;
                cert.Previous_Certificate_Hash__c = prevHash;
                cert.Chain_Position__c = prevPosition + 1;
            } else {
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
                    Last_Integrity_Check__c = DateTime.now(),
                    Chain_Hash__c = chainHash,
                    Previous_Certificate__c = prevCertId,
                    Previous_Certificate_Hash__c = prevHash,
                    Chain_Position__c = prevPosition + 1
                );
            }
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
            List<Quantum_Backend__c> backends = [
                SELECT
                    Id,
                    Quantum_Verified__c,
                    CHSH_S_Value__c,
                    CHSH_Verified_At__c
                FROM Quantum_Backend__c
                WHERE Name = :job.Backend__c
                LIMIT 1
            ];
            if (!backends.isEmpty()) {
                Quantum_Backend__c backend = backends[0];
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
     * Verify integrity of a certificate by re-computing hashes and walking
     * to its actual predecessor in the chain.
     * Sets or clears the Tampered__c flag on the record.
     * Records who verified and when for audit trail compliance.
     */
    public static Map<String, Object> verifyCertificate(Id certificateId) {
        Fairness_Certificate__c cert = [
            SELECT
                Id,
                Quantum_Job__c,
                Raw_Bitstring_Hash__c,
                Debiased_Bitstring_Hash__c,
                Assignment_Hash__c,
                Chain_Hash__c,
                Chain_Position__c,
                Previous_Certificate_Hash__c,
                Previous_Certificate__c
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

        // Verify chain link integrity: (1) the chain hash must recompute
        // from this cert's content and its stored predecessor hash, and
        // (2) the stored predecessor hash must equal the ACTUAL
        // predecessor's Chain_Hash__c — a forged Previous_Certificate_Hash__c
        // with a self-consistently recomputed Chain_Hash__c is tampering.
        Boolean chainMatch = true;
        Boolean previousHashMatch = true;
        if (cert.Chain_Hash__c != null) {
            String prevHashForLink = cert.Previous_Certificate_Hash__c != null
                ? cert.Previous_Certificate_Hash__c
                : GENESIS_HASH;
            String recomputedChainHash = computeSHA256(
                recomputedRawHash + recomputedDebiasedHash + prevHashForLink
            );
            chainMatch = cert.Chain_Hash__c == recomputedChainHash;

            Fairness_Certificate__c predecessor = findPredecessor(cert);
            if (predecessor != null) {
                previousHashMatch =
                    cert.Previous_Certificate_Hash__c ==
                    predecessor.Chain_Hash__c;
            } else if (
                cert.Chain_Position__c != null &&
                cert.Chain_Position__c > 1
            ) {
                // A predecessor should exist but cannot be found — broken link
                previousHashMatch = false;
            } else {
                // Genesis certificate: predecessor hash must be the genesis hash
                previousHashMatch =
                    cert.Previous_Certificate_Hash__c == null ||
                    cert.Previous_Certificate_Hash__c == GENESIS_HASH;
            }
        }

        Boolean verified =
            rawMatch &&
            debiasedMatch &&
            chainMatch &&
            previousHashMatch;

        // Update tampered flag, verification audit fields, and last check timestamp
        cert.Tampered__c = !verified;
        cert.Last_Integrity_Check__c = DateTime.now();
        cert.Verified_By__c = UserInfo.getUserId();
        cert.Verified_At__c = DateTime.now();
        update cert;

        // Log tamper detection as a compliance event
        if (!verified) {
            Map<String, Object> detail = new Map<String, Object>{
                'rawHashMatch' => rawMatch,
                'debiasedHashMatch' => debiasedMatch,
                'chainHashMatch' => chainMatch,
                'previousHashMatch' => previousHashMatch,
                'certificateId' => certificateId
            };
            ComplianceEventLogger.log(
                'TAMPER_DETECTED',
                'CRITICAL',
                certificateId,
                cert.Quantum_Job__c,
                detail
            );
        }

        Map<String, Object> result = new Map<String, Object>();
        result.put('rawHashMatch', rawMatch);
        result.put('debiasedHashMatch', debiasedMatch);
        result.put('chainHashMatch', chainMatch);
        result.put('previousHashMatch', previousHashMatch);
        result.put('integrityVerified', verified);
        return result;
    }

    /**
     * Resolve a certificate's actual predecessor: prefer the
     * Previous_Certificate__c lookup, fall back to the certificate at
     * Chain_Position__c - 1. Returns null when no predecessor exists
     * (genesis certificate) or none can be found.
     */
    private static Fairness_Certificate__c findPredecessor(
        Fairness_Certificate__c cert
    ) {
        if (cert.Previous_Certificate__c != null) {
            List<Fairness_Certificate__c> byId = [
                SELECT Id, Chain_Hash__c
                FROM Fairness_Certificate__c
                WHERE Id = :cert.Previous_Certificate__c
                LIMIT 1
            ];
            if (!byId.isEmpty()) {
                return byId[0];
            }
        }
        if (cert.Chain_Position__c != null && cert.Chain_Position__c > 1) {
            Decimal prevPosition = cert.Chain_Position__c - 1;
            List<Fairness_Certificate__c> byPosition = [
                SELECT Id, Chain_Hash__c
                FROM Fairness_Certificate__c
                WHERE
                    Chain_Position__c = :prevPosition
                    AND Chain_Hash__c != NULL
                    AND Id != :cert.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!byPosition.isEmpty()) {
                return byPosition[0];
            }
        }
        return null;
    }

    /**
     * Lock and return the current chain tail (highest Chain_Position__c),
     * or null when the chain is empty. SOQL disallows ORDER BY together
     * with FOR UPDATE, so the tail position is read first and every
     * certificate at or above it is locked; concurrent chain-head writers
     * therefore serialize on the tail row instead of both linking to the
     * same predecessor.
     */
    private static Fairness_Certificate__c lockChainTail() {
        List<AggregateResult> agg = [
            SELECT MAX(Chain_Position__c) maxPos
            FROM Fairness_Certificate__c
            WHERE Chain_Hash__c != NULL
        ];
        Object maxPosObj = agg.isEmpty() ? null : agg[0].get('maxPos');
        if (maxPosObj == null) {
            return null;
        }
        Decimal maxPos = (Decimal) maxPosObj;

        List<Fairness_Certificate__c> tails = [
            SELECT Id, Chain_Hash__c, Chain_Position__c
            FROM Fairness_Certificate__c
            WHERE Chain_Hash__c != NULL AND Chain_Position__c >= :maxPos
            FOR UPDATE
        ];
        Fairness_Certificate__c tail = null;
        for (Fairness_Certificate__c c : tails) {
            if (tail == null || c.Chain_Position__c > tail.Chain_Position__c) {
                tail = c;
            }
        }
        return tail;
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
