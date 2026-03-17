/**
 * Nightly scheduled job that verifies SHA-256 integrity of all Fairness Certificates.
 * Re-computes hashes from Quantum_Job__c data and flags tampered records.
 *
 * Pattern: Schedulable outer class + inner Queueable worker.
 * Uses cursor-based pagination (Id >) to handle large cert volumes.
 *
 * Governor limits per worker execution: ~4 SOQL, 1 DML, 0 callouts
 */
public class IntegrityVerificationJob implements Schedulable {
    public static final String JOB_NAME = 'QRNG_Integrity_Verification';
    @TestVisible
    private static final Integer BATCH_SIZE = 50;

    public void execute(SchedulableContext sc) {
        if (!Test.isRunningTest()) {
            System.enqueueJob(new IntegrityVerificationWorker(null));
        }
    }

    /**
     * Schedule the job at the configured hour (daily).
     * Default: 2 AM (off-peak best practice).
     */
    public static void scheduleDefault() {
        unschedule();
        Integer hour = getCheckHour();
        String cronExp = '0 0 ' + hour + ' * * ?';
        System.schedule(JOB_NAME, cronExp, new IntegrityVerificationJob());
    }

    public static void unschedule() {
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ];
        for (CronTrigger ct : jobs) {
            System.abortJob(ct.Id);
        }
    }

    public static Boolean isScheduled() {
        return [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :JOB_NAME
            ] > 0;
    }

    @TestVisible
    private static Integer getCheckHour() {
        QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
        if (settings != null && settings.Integrity_Check_Hour__c != null) {
            Integer val = (Integer) settings.Integrity_Check_Hour__c;
            return (val >= 0 && val <= 23) ? val : 2;
        }
        return 2;
    }

    /**
     * Inner Queueable worker. Processes certificates in batches using
     * cursor-based pagination (WHERE Id > lastProcessedId).
     */
    public class IntegrityVerificationWorker implements Queueable {
        private Id lastProcessedId;

        public IntegrityVerificationWorker(Id lastProcessedId) {
            this.lastProcessedId = lastProcessedId;
        }

        public void execute(QueueableContext context) {
            // Query batch of Certified certificates
            List<Fairness_Certificate__c> certs;
            if (lastProcessedId == null) {
                certs = [
                    SELECT
                        Id,
                        Quantum_Job__c,
                        Raw_Bitstring_Hash__c,
                        Debiased_Bitstring_Hash__c
                    FROM Fairness_Certificate__c
                    WHERE Status__c = 'Certified'
                    ORDER BY Id ASC
                    LIMIT :BATCH_SIZE
                ];
            } else {
                certs = [
                    SELECT
                        Id,
                        Quantum_Job__c,
                        Raw_Bitstring_Hash__c,
                        Debiased_Bitstring_Hash__c
                    FROM Fairness_Certificate__c
                    WHERE Status__c = 'Certified' AND Id > :lastProcessedId
                    ORDER BY Id ASC
                    LIMIT :BATCH_SIZE
                ];
            }

            if (certs.isEmpty()) {
                return;
            }

            // Bulk-query all related jobs
            Set<Id> jobIds = new Set<Id>();
            for (Fairness_Certificate__c c : certs) {
                if (c.Quantum_Job__c != null) {
                    jobIds.add(c.Quantum_Job__c);
                }
            }

            Map<Id, Quantum_Job__c> jobMap = new Map<Id, Quantum_Job__c>(
                [
                    SELECT Id, Raw_Results__c, Debiased_Results__c
                    FROM Quantum_Job__c
                    WHERE Id IN :jobIds
                ]
            );

            // Verify each certificate
            List<Fairness_Certificate__c> toUpdate = new List<Fairness_Certificate__c>();
            for (Fairness_Certificate__c cert : certs) {
                Quantum_Job__c job = jobMap.get(cert.Quantum_Job__c);
                if (job == null) {
                    continue;
                }

                String rawHash = FairnessCertificateService.computeSHA256(
                    job.Raw_Results__c != null ? job.Raw_Results__c : ''
                );
                String debiasedHash = FairnessCertificateService.computeSHA256(
                    job.Debiased_Results__c != null
                        ? job.Debiased_Results__c
                        : ''
                );

                Boolean tampered =
                    cert.Raw_Bitstring_Hash__c != rawHash ||
                    cert.Debiased_Bitstring_Hash__c != debiasedHash;

                cert.Tampered__c = tampered;
                cert.Last_Integrity_Check__c = DateTime.now();
                toUpdate.add(cert);
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }

            // Chain to next batch if we got a full batch
            if (certs.size() == BATCH_SIZE && !Test.isRunningTest()) {
                Id lastId = certs[certs.size() - 1].Id;
                System.enqueueJob(new IntegrityVerificationWorker(lastId));
            }
        }
    }
}
