/**
 * Daily compliance hash digest email.
 * Sends the current chain head hash and daily summary to the configured compliance email.
 * Scheduled to run daily.
 * Governor budget: ~5 SOQL, 1 email, 0 DML.
 */
public with sharing class ComplianceDigestJob implements Schedulable {
    public static final String JOB_NAME = 'QuantumFair Compliance Digest';
    // Daily at 06:00 org time
    @TestVisible
    private static final String CRON_DAILY_6AM = '0 0 6 * * ?';

    /**
     * Schedule the daily digest at 06:00 org time.
     * Removes any existing schedule first (idempotent).
     */
    public static void scheduleDefault() {
        unschedule();
        System.schedule(JOB_NAME, CRON_DAILY_6AM, new ComplianceDigestJob());
    }

    /**
     * Remove the digest schedule.
     */
    public static void unschedule() {
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
        ];
        for (CronTrigger ct : existing) {
            System.abortJob(ct.Id);
        }
    }

    /**
     * Check if the digest is currently scheduled.
     */
    public static Boolean isScheduled() {
        return [
                SELECT COUNT()
                FROM CronTrigger
                WHERE CronJobDetail.Name = :JOB_NAME
            ] > 0;
    }

    public void execute(SchedulableContext ctx) {
        Quantum_Settings__c settings = Quantum_Settings__c.getOrgDefaults();
        String complianceEmail = settings.Compliance_Email__c;
        if (String.isBlank(complianceEmail)) {
            return; // No compliance email configured, skip
        }

        // Query today's certificates
        Date today = Date.today();
        DateTime startOfDay = DateTime.newInstance(
            today,
            Time.newInstance(0, 0, 0, 0)
        );
        DateTime endOfDay = startOfDay.addDays(1);

        List<Fairness_Certificate__c> todayCerts = [
            SELECT Id, Chain_Hash__c, Chain_Position__c, Status__c, CreatedDate
            FROM Fairness_Certificate__c
            WHERE CreatedDate >= :startOfDay AND CreatedDate < :endOfDay
            ORDER BY Chain_Position__c ASC
        ];

        // Query latest chain head
        List<Fairness_Certificate__c> chainHead = [
            SELECT Id, Chain_Hash__c, Chain_Position__c
            FROM Fairness_Certificate__c
            WHERE Chain_Hash__c != NULL
            ORDER BY Chain_Position__c DESC
            LIMIT 1
        ];

        // Query today's compliance events
        List<Compliance_Event__c> todayEvents = [
            SELECT Id, Event_Type__c, Severity__c, Detail__c, CreatedDate
            FROM Compliance_Event__c
            WHERE CreatedDate >= :startOfDay AND CreatedDate < :endOfDay
            ORDER BY CreatedDate ASC
        ];

        // Build daily root hash (SHA-256 of all chain hashes concatenated)
        String concatenatedHashes = '';
        for (Fairness_Certificate__c cert : todayCerts) {
            if (cert.Chain_Hash__c != null) {
                concatenatedHashes += cert.Chain_Hash__c;
            }
        }
        String dailyRootHash = concatenatedHashes.length() > 0
            ? FairnessCertificateService.computeSHA256(concatenatedHashes)
            : 'NO_CERTIFICATES_TODAY';

        // Build email body
        String body = buildDigestBody(
            todayCerts,
            chainHead,
            todayEvents,
            dailyRootHash
        );

        // Send email
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ complianceEmail });
        mail.setSubject(
            'QuantumFair Daily Compliance Digest - ' + today.format()
        );
        mail.setPlainTextBody(body);
        mail.setSaveAsActivity(false);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
    }

    @TestVisible
    private String buildDigestBody(
        List<Fairness_Certificate__c> todayCerts,
        List<Fairness_Certificate__c> chainHead,
        List<Compliance_Event__c> todayEvents,
        String dailyRootHash
    ) {
        String orgId = UserInfo.getOrganizationId();
        String body = '';
        body += '=== QUANTUMFAIR DAILY COMPLIANCE DIGEST ===\n';
        body += 'date: ' + Date.today().format() + '\n';
        body += 'org_id: ' + orgId + '\n';
        body += 'certificates_today: ' + todayCerts.size() + '\n';
        body += 'daily_root_hash: ' + dailyRootHash + '\n';

        if (!chainHead.isEmpty()) {
            body += 'chain_head_hash: ' + chainHead[0].Chain_Hash__c + '\n';
            body +=
                'chain_head_position: ' +
                String.valueOf(chainHead[0].Chain_Position__c) +
                '\n';
        } else {
            body += 'chain_head_hash: NO_CHAIN\n';
            body += 'chain_head_position: 0\n';
        }

        body += 'anomaly_events_today: ' + todayEvents.size() + '\n';
        body += '\n';

        if (!todayEvents.isEmpty()) {
            body += '--- ANOMALY EVENTS ---\n';
            for (Compliance_Event__c evt : todayEvents) {
                body +=
                    evt.CreatedDate.format() +
                    ' | ' +
                    evt.Severity__c +
                    ' | ' +
                    evt.Event_Type__c +
                    '\n';
                if (evt.Detail__c != null) {
                    body += '  Detail: ' + evt.Detail__c.left(200) + '\n';
                }
            }
            body += '\n';
        }

        if (!todayCerts.isEmpty()) {
            body += '--- CERTIFICATES ---\n';
            for (Fairness_Certificate__c cert : todayCerts) {
                body +=
                    'Position ' +
                    String.valueOf(cert.Chain_Position__c) +
                    ' | Status: ' +
                    cert.Status__c +
                    ' | Hash: ' +
                    cert.Chain_Hash__c +
                    '\n';
            }
        }

        body += '\n=== END DIGEST ===\n';
        body += 'This email is machine-generated for out-of-band audit verification.\n';
        body += 'Archive this email — the hashes can be compared against Salesforce records to detect tampering.\n';

        return body;
    }
}
