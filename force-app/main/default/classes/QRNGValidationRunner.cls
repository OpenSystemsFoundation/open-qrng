/**
 * Queueable that runs extended randomness validation tests asynchronously.
 * Enqueued after the critical realtime gate (frequency + CHSH) passes.
 * Results stored on Quantum_Job__c.Validation_Results__c as JSON.
 *
 * Tests run: Approximate Entropy, Serial, Cumulative Sums, Longest Run of Ones.
 * Governor limits: 0 callouts, ~5 SOQL, 2 DML
 */
public with sharing class QRNGValidationRunner implements Queueable {
    private Id jobId;

    public QRNGValidationRunner(Id jobId) {
        this.jobId = jobId;
    }

    public void execute(QueueableContext context) {
        Quantum_Job__c job = [
            SELECT Id, Debiased_Results__c, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        if (String.isBlank(job.Debiased_Results__c)) {
            return;
        }

        // Decode hex-encoded debiased results back to binary for validation
        String debiasedBits = QRNGResultParser.decodeRawResults(
            job.Debiased_Results__c
        );

        // Run extended tests
        Map<String, Object> extendedResults = QRNGValidator.validateExtended(
            debiasedBits
        );

        // Merge with existing validation results
        Map<String, Object> allResults = new Map<String, Object>();
        if (String.isNotBlank(job.Validation_Results__c)) {
            try {
                allResults = (Map<String, Object>) JSON.deserializeUntyped(
                    job.Validation_Results__c
                );
            } catch (Exception e) {
                // Start fresh if parse fails
            }
        }
        allResults.putAll(extendedResults);
        allResults.put('extendedTestsCompleted', true);
        allResults.put('extendedTestsTimestamp', DateTime.now().format());

        job.Validation_Results__c = JSON.serialize(allResults);
        update job;

        // Also update the certificate validation results
        List<Fairness_Certificate__c> certs = [
            SELECT Id, Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!certs.isEmpty()) {
            certs[0].Validation_Results__c = JSON.serialize(allResults);
            update certs;
        }
    }
}
