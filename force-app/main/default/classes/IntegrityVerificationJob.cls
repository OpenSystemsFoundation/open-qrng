/**
 * Nightly scheduled job that verifies SHA-256 integrity of all Fairness Certificates.
 * Re-computes hashes from Quantum_Job__c data and flags tampered records.
 * Also verifies certificate chain continuity (each cert's Previous_Certificate_Hash__c
 * must match the actual prior cert's Chain_Hash__c).
 *
 * Pattern: Schedulable outer class + inner Queueable worker.
 * Uses cursor-based pagination (Id >) to handle large cert volumes.
 *
 * Governor limits per worker execution: ~5 SOQL, 1-2 DML, 0 callouts
 */
public with sharing class IntegrityVerificationJob implements Schedulable {
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
     * Verifies both hash integrity and chain continuity.
     */
    public with sharing class IntegrityVerificationWorker implements Queueable {
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
                        Debiased_Bitstring_Hash__c,
                        Chain_Hash__c,
                        Previous_Certificate__c,
                        Previous_Certificate_Hash__c,
                        Chain_Position__c
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
                        Debiased_Bitstring_Hash__c,
                        Chain_Hash__c,
                        Previous_Certificate__c,
                        Previous_Certificate_Hash__c,
                        Chain_Position__c
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

            // Bulk-query previous certificates for chain verification
            Set<Id> prevCertIds = new Set<Id>();
            for (Fairness_Certificate__c c : certs) {
                if (c.Previous_Certificate__c != null) {
                    prevCertIds.add(c.Previous_Certificate__c);
                }
            }
            Map<Id, Fairness_Certificate__c> prevCertMap = new Map<Id, Fairness_Certificate__c>();
            if (!prevCertIds.isEmpty()) {
                prevCertMap = new Map<Id, Fairness_Certificate__c>(
                    [
                        SELECT Id, Chain_Hash__c
                        FROM Fairness_Certificate__c
                        WHERE Id IN :prevCertIds
                    ]
                );
            }

            // Verify each certificate
            List<Fairness_Certificate__c> toUpdate = new List<Fairness_Certificate__c>();
            List<Compliance_Event__c> events = new List<Compliance_Event__c>();
            Integer passCount = 0;
            Integer failCount = 0;

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

                Boolean hashTampered =
                    cert.Raw_Bitstring_Hash__c != rawHash ||
                    cert.Debiased_Bitstring_Hash__c != debiasedHash;

                // Verify chain link
                Boolean chainBroken = false;
                if (
                    cert.Previous_Certificate__c != null &&
                    cert.Previous_Certificate_Hash__c != null
                ) {
                    Fairness_Certificate__c prevCert = prevCertMap.get(
                        cert.Previous_Certificate__c
                    );
                    if (
                        prevCert != null &&
                        prevCert.Chain_Hash__c !=
                        cert.Previous_Certificate_Hash__c
                    ) {
                        chainBroken = true;
                    }
                }

                Boolean tampered = hashTampered || chainBroken;
                cert.Tampered__c = tampered;
                cert.Last_Integrity_Check__c = DateTime.now();
                toUpdate.add(cert);

                if (tampered) {
                    failCount++;
                    Compliance_Event__c evt = new Compliance_Event__c();
                    evt.Event_Type__c = chainBroken
                        ? 'CHAIN_BREAK_DETECTED'
                        : 'TAMPER_DETECTED';
                    evt.Severity__c = 'CRITICAL';
                    evt.Related_Certificate__c = cert.Id;
                    evt.Related_Job__c = cert.Quantum_Job__c;
                    Map<String, Object> detail = new Map<String, Object>{
                        'hashTampered' => hashTampered,
                        'chainBroken' => chainBroken,
                        'certificateId' => cert.Id,
                        'chainPosition' => cert.Chain_Position__c
                    };
                    evt.Detail__c = JSON.serialize(detail);
                    events.add(evt);
                } else {
                    passCount++;
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }

            // Log any compliance events for tampered/chain-broken certs
            if (!events.isEmpty()) {
                ComplianceEventLogger.logBulk(events);
            }

            // Chain to next batch if we got a full batch
            if (certs.size() == BATCH_SIZE && !Test.isRunningTest()) {
                Id lastId = certs[certs.size() - 1].Id;
                System.enqueueJob(new IntegrityVerificationWorker(lastId));
            }
        }
    }
}
