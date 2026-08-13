/**
 * Queueable that runs extended randomness validation tests asynchronously.
 * Enqueued after the critical realtime gate (frequency + CHSH) passes.
 * Results stored on Quantum_Job__c.Validation_Results__c as JSON.
 *
 * Tests run: Approximate Entropy, Serial, Cumulative Sums, Longest Run of
 * Ones, plus SP 800-90B health tests (MCV min-entropy with confidence
 * bound, repetition count, adaptive proportion).
 *
 * REVOCATION: extended tests run AFTER certification. If the extended
 * suite fails, this runner revokes the already-issued certificate
 * (Status__c = 'Revoked'), records the failure on the job
 * (Error_Message__c), and publishes a Quantum_Job_Failed__e event so
 * UIs and subscribers hear about the downgrade.
 *
 * Sharing: `with sharing`, consistent with the other async workers in
 * this codebase (JobPoller, JobSweeper). The Queueable runs as the user
 * whose transaction enqueued it, who created/owns the job and certificate.
 *
 * Governor limits: 0 callouts, 2 SOQL, up to 2 DML + 1 event publish
 */
public with sharing class ValidationRunner implements Queueable {
    private Id jobId;

    public ValidationRunner(Id jobId) {
        this.jobId = jobId;
    }

    public void execute(QueueableContext context) {
        Quantum_Job__c job = [
            SELECT
                Id,
                Debiased_Results__c,
                Validation_Results__c,
                Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        if (String.isBlank(job.Debiased_Results__c)) {
            return;
        }

        // Decode hex-encoded debiased results back to binary for validation
        String debiasedBits = ResultParser.decodeRawResults(
            job.Debiased_Results__c
        );

        // Run extended tests
        Map<String, Object> extendedResults = RandomnessValidator.validateExtended(
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

        // Determine whether the extended suite failed (includes the
        // min-entropy threshold — minEntropyTest feeds extendedPassed)
        Boolean extendedPassed =
            (Boolean) extendedResults.get('extendedPassed') == true;

        String failureMessage = null;
        if (!extendedPassed) {
            failureMessage =
                'Extended validation failed: ' +
                buildFailureSummary(extendedResults);
            allResults.put('certificateRevoked', true);
            allResults.put('revocationReason', failureMessage);

            // Publish failure event so UIs/subscribers hear about the
            // revocation. Swallow-but-note publish failures: the record
            // updates below must still commit.
            Quantum_Job_Failed__e failEvent = new Quantum_Job_Failed__e(
                Job_Id__c = jobId,
                Error_Message__c = failureMessage.left(255)
            );
            Database.SaveResult publishResult = EventBus.publish(failEvent);
            allResults.put('failureEventPublished', publishResult.isSuccess());
            if (!publishResult.isSuccess()) {
                String publishError = publishResult.getErrors().isEmpty()
                    ? 'unknown'
                    : publishResult.getErrors()[0].getMessage();
                allResults.put('failureEventError', publishError);
                System.debug(
                    LoggingLevel.ERROR,
                    'ValidationRunner: Quantum_Job_Failed__e publish failed for job ' +
                        jobId +
                        ': ' +
                        publishError
                );
            }

            job.Error_Message__c = failureMessage;
        }

        job.Validation_Results__c = JSON.serialize(allResults);
        update job;

        // Also update the certificate: merge validation results and, on
        // extended failure, revoke the certification issued by the
        // realtime gate.
        List<Fairness_Certificate__c> certs = [
            SELECT Id, Status__c, Validation_Results__c
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!certs.isEmpty()) {
            certs[0].Validation_Results__c = JSON.serialize(allResults);
            if (!extendedPassed) {
                certs[0].Status__c = 'Revoked';
            }
            update certs;
        }
    }

    /**
     * Build a compact summary of the failing extended tests for
     * Error_Message__c and the platform event payload.
     */
    @TestVisible
    private static String buildFailureSummary(
        Map<String, Object> extendedResults
    ) {
        if (extendedResults.containsKey('error')) {
            return String.valueOf(extendedResults.get('error'));
        }

        List<String> failing = new List<String>();
        List<String> testKeys = new List<String>{
            'approximateEntropyTest',
            'serialTest',
            'cumulativeSumsTest',
            'longestRunOfOnesTest',
            'minEntropyTest',
            'repetitionCountTest',
            'adaptiveProportionTest'
        };
        for (String key : testKeys) {
            if ((Boolean) extendedResults.get(key) == false) {
                failing.add(key);
            }
        }

        String summary = failing.isEmpty()
            ? 'extended suite failed'
            : String.join(failing, ', ');
        if (extendedResults.containsKey('minEntropy')) {
            summary +=
                ' (minEntropy=' +
                String.valueOf(extendedResults.get('minEntropy')) +
                ')';
        }
        return summary;
    }
}
