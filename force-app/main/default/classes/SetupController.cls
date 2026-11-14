/**
 * LWC controller for admin setup and general quantum operations.
 * Handles connection testing, backend listing, settings management, and job submission.
 */
public with sharing class SetupController {
    /**
     * Security model:
     * - 'with sharing': row-level sharing is enforced on all queries and DML.
     * - Authorization (B6): privileged methods call requireAdmin(), which
     *   checks the QuantumFair_Administer custom permission (granted only by
     *   the QuantumFair_Admin permission set) via FeatureManagement.
     * - CRUD/FLS (H-S2): Salesforce does NOT automatically enforce CRUD/FLS
     *   for @AuraEnabled Apex. Read methods that return record data either
     *   run their SOQL WITH USER_MODE, or (for DTO builders) query in system
     *   mode and pass the rows through
     *   Security.stripInaccessible(AccessType.READABLE) so fields the running
     *   user cannot read come back null instead of throwing.
     * - User-initiated writes are preceded by explicit isUpdateable() checks
     *   and throw AuraHandledException when the user lacks update rights.
     * - Deliberate system-mode paths (provider seeding, pipeline status sync,
     *   schedule management) are commented inline with the reason.
     */

    private static final String NO_PERMISSION_MSG = 'You do not have permission to perform this action.';

    /**
     * Test seam: FeatureManagement.checkPermission() returns false in test
     * context unless the permission is assigned to the running user. Tests
     * that exercise privileged paths set this to true; tests that assert the
     * denial path leave it false.
     */
    @TestVisible
    private static Boolean adminOverrideForTests = false;

    /**
     * Authorization gate (B6) for privileged operations: saving settings,
     * managing scheduled jobs, syncing providers/backends, submitting
     * verification jobs, and exporting compliance evidence.
     */
    private static void requireAdmin() {
        if (adminOverrideForTests) {
            return;
        }
        if (!FeatureManagement.checkPermission('QuantumFair_Administer')) {
            throw new AuraHandledException(NO_PERMISSION_MSG);
        }
    }

    /**
     * Null-safe conversion of a populated-field-map value (Decimal at
     * runtime for SOQL numeric fields) to Integer.
     */
    private static Integer toInteger(Object value) {
        return value == null ? null : ((Decimal) value).intValue();
    }

    /**
     * Extract a parent relationship's Name from a populated-field map entry.
     */
    private static String parentName(Object parentRecord) {
        return parentRecord == null
            ? null
            : (String) ((SObject) parentRecord).get('Name');
    }

    // ── DTOs ────────────────────────────────────────────────────────

    public class BackendHealthDTO {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Integer qubits;
        @AuraEnabled
        public Integer queueLength;
        @AuraEnabled
        public Boolean isSimulator;
        @AuraEnabled
        public String processorFamily;
        @AuraEnabled
        public String processorRevision;
        @AuraEnabled
        public Integer maxShots;
        @AuraEnabled
        public Decimal avgT1;
        @AuraEnabled
        public Decimal avgT2;
        @AuraEnabled
        public Decimal gateError;
        @AuraEnabled
        public Decimal readoutError;
        @AuraEnabled
        public DateTime lastCalibration;
        @AuraEnabled
        public DateTime lastSynced;
        @AuraEnabled
        public String provider;
        @AuraEnabled
        public Decimal chshSValue;
        @AuraEnabled
        public DateTime chshVerifiedAt;
        @AuraEnabled
        public Boolean quantumVerified;
        @AuraEnabled
        public String chshJobId;
        @AuraEnabled
        public String recordId;
    }

    public class JobSummaryDTO {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String externalJobId;
        @AuraEnabled
        public String backend;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String jobType;
        @AuraEnabled
        public Boolean useBellTest;
        @AuraEnabled
        public Integer shots;
        @AuraEnabled
        public Integer numQubits;
        @AuraEnabled
        public String purpose;
        @AuraEnabled
        public DateTime submittedAt;
        @AuraEnabled
        public DateTime completedAt;
        @AuraEnabled
        public Decimal executionTimeMs;
        @AuraEnabled
        public Decimal qpuTimeSeconds;
        @AuraEnabled
        public String requestedByName;
        @AuraEnabled
        public String errorMessage;
    }

    public class JobStatusDTO {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String externalJobId;
        @AuraEnabled
        public String backend;
        @AuraEnabled
        public String provider;
        @AuraEnabled
        public Integer shots;
        @AuraEnabled
        public Integer numQubits;
        @AuraEnabled
        public String purpose;
        @AuraEnabled
        public Boolean useBellTest;
        @AuraEnabled
        public String assignmentType;
        @AuraEnabled
        public String jobType;
        @AuraEnabled
        public DateTime submittedAt;
        @AuraEnabled
        public DateTime completedAt;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public Integer pollCount;
        @AuraEnabled
        public Decimal executionTimeMs;
        @AuraEnabled
        public Decimal queueTimeMs;
        @AuraEnabled
        public String rawResults;
        @AuraEnabled
        public String debiasedResults;
        @AuraEnabled
        public String resultFingerprint;
    }

    public class AuditTrailDTO {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String externalJobId;
        @AuraEnabled
        public String backend;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String purpose;
        @AuraEnabled
        public Decimal chshSValue;
        @AuraEnabled
        public DateTime createdDate;
        @AuraEnabled
        public Id quantumJobId;
        @AuraEnabled
        public Boolean tampered;
        @AuraEnabled
        public String createdByUser;
    }

    public class CertificateDTO {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String externalJobId;
        @AuraEnabled
        public String backend;
        @AuraEnabled
        public String circuitQasm;
        @AuraEnabled
        public String rawBitstringHash;
        @AuraEnabled
        public String debiasedBitstringHash;
        @AuraEnabled
        public String assignmentHash;
        @AuraEnabled
        public String validationResults;
        @AuraEnabled
        public Decimal chshSValue;
        @AuraEnabled
        public String createdByUser;
        @AuraEnabled
        public String purpose;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Id quantumJobId;
        @AuraEnabled
        public DateTime createdDate;
        @AuraEnabled
        public Boolean tampered;
        @AuraEnabled
        public DateTime lastIntegrityCheck;
        @AuraEnabled
        public Boolean backendVerified;
        @AuraEnabled
        public DateTime backendVerifiedAt;
    }

    // ── Methods ─────────────────────────────────────────────────────

    /**
     * Run all randomness validation tests on demand for a completed job.
     * Runs both critical (frequency, runs, chi-squared) and extended
     * (approximate entropy, serial, CUSUM, longest run) tests synchronously.
     * Returns the merged results as a map.
     */
    @AuraEnabled
    public static Map<String, Object> runValidationTests(Id jobId) {
        // H-S2: user-initiated write — read-only personas (e.g. auditors)
        // must not be able to trigger DML through this path.
        if (
            !Schema.sObjectType.Quantum_Job__c.isUpdateable() ||
            !Schema.sObjectType.Quantum_Job__c.fields.Validation_Results__c.isUpdateable() ||
            !Schema.sObjectType.Fairness_Certificate__c.isUpdateable() ||
            !Schema.sObjectType.Fairness_Certificate__c.fields.Validation_Results__c.isUpdateable() ||
            !Schema.sObjectType.Fairness_Certificate__c.fields.CHSH_S_Value__c.isUpdateable()
        ) {
            throw new AuraHandledException(NO_PERMISSION_MSG);
        }

        Quantum_Job__c job = [
            SELECT
                Id,
                Status__c,
                Debiased_Results__c,
                Raw_Results__c,
                Use_Bell_Test__c,
                Num_Qubits__c,
                Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            WITH USER_MODE
            LIMIT 1
        ];

        if (job.Status__c != 'Completed') {
            throw new QuantumException(
                'Cannot run validation on a job that has not completed.'
            );
        }
        if (String.isBlank(job.Debiased_Results__c)) {
            throw new QuantumException(
                'No debiased results available for validation.'
            );
        }

        // Decode hex-encoded debiased results back to binary for validation
        String debiasedBits = ResultParser.decodeRawResults(
            job.Debiased_Results__c
        );

        // Run critical tests
        Map<String, Object> results = RandomnessValidator.validate(
            debiasedBits
        );

        // Run extended tests
        Map<String, Object> extendedResults = RandomnessValidator.validateExtended(
            debiasedBits
        );
        results.putAll(extendedResults);

        // Add CHSH if Bell test
        if (
            job.Use_Bell_Test__c == true &&
            String.isNotBlank(job.Raw_Results__c)
        ) {
            Integer numQubits = job.Num_Qubits__c != null
                ? (Integer) job.Num_Qubits__c
                : 8;
            Integer numPairs = numQubits / 2;
            // Re-parse raw results to get individual bitstrings for CHSH
            // Raw results may be hex-encoded — decode before splitting
            String raw = ResultParser.decodeRawResults(job.Raw_Results__c);
            List<String> bitstrings = new List<String>();
            for (Integer i = 0; i + numQubits <= raw.length(); i += numQubits) {
                bitstrings.add(raw.substring(i, i + numQubits));
            }
            Map<String, Object> chshStats = RandomnessValidator.calculateCHSHWithStats(
                bitstrings,
                numPairs
            );
            results.putAll(chshStats);
        }

        results.put('allTestsCompleted', true);
        results.put('manualRunTimestamp', DateTime.now().format());

        // Store on job
        String resultsJson = JSON.serialize(results);
        job.Validation_Results__c = resultsJson;
        update job;

        // Update certificate too
        List<Fairness_Certificate__c> certs = [
            SELECT Id
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :jobId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!certs.isEmpty()) {
            certs[0].Validation_Results__c = resultsJson;
            if (results.containsKey('chshSValue')) {
                certs[0].CHSH_S_Value__c = (Double) results.get('chshSValue');
            }
            update certs;
        }

        return results;
    }

    /**
     * Get validation results for a job (from stored JSON).
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getValidationResults(Id jobId) {
        Quantum_Job__c job = [
            SELECT Id, Validation_Results__c, Job_Type__c, Circuit_QASM__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            WITH USER_MODE
            LIMIT 1
        ];

        Map<String, Object> result;
        if (String.isNotBlank(job.Validation_Results__c)) {
            result = (Map<String, Object>) JSON.deserializeUntyped(
                job.Validation_Results__c
            );
        } else {
            result = new Map<String, Object>();
        }
        result.put('jobType', job.Job_Type__c);
        result.put('circuitQasm', job.Circuit_QASM__c);
        return result;
    }

    /**
     * Get job status data as a DTO for the record page LWC.
     * FLS (H-S2): the row is passed through stripInaccessible so fields the
     * running user cannot read (e.g. Raw_Results__c / Debiased_Results__c for
     * auditors) come back null in the DTO instead of leaking or throwing.
     */
    @AuraEnabled(cacheable=true)
    public static JobStatusDTO getJobStatusDTO(Id jobId) {
        Quantum_Job__c job = [
            SELECT
                Name,
                Status__c,
                External_Job_ID__c,
                Backend__c,
                Provider__c,
                Shots__c,
                Num_Qubits__c,
                Purpose__c,
                Use_Bell_Test__c,
                Assignment_Type__c,
                Submitted_At__c,
                Completed_At__c,
                Error_Message__c,
                Poll_Count__c,
                Execution_Time_ms__c,
                Queue_Time_ms__c,
                Raw_Results__c,
                Debiased_Results__c,
                Result_Fingerprint__c,
                Job_Type__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        Map<String, Object> f = Security.stripInaccessible(
                    AccessType.READABLE,
                    new List<Quantum_Job__c>{ job }
                )
                .getRecords()[0]
            .getPopulatedFieldsAsMap();

        JobStatusDTO dto = new JobStatusDTO();
        dto.name = (String) f.get('Name');
        dto.status = (String) f.get('Status__c');
        dto.externalJobId = (String) f.get('External_Job_ID__c');
        dto.backend = (String) f.get('Backend__c');
        dto.provider = (String) f.get('Provider__c');
        dto.shots = toInteger(f.get('Shots__c'));
        dto.numQubits = toInteger(f.get('Num_Qubits__c'));
        dto.purpose = (String) f.get('Purpose__c');
        dto.useBellTest = (Boolean) f.get('Use_Bell_Test__c');
        dto.assignmentType = (String) f.get('Assignment_Type__c');
        dto.submittedAt = (DateTime) f.get('Submitted_At__c');
        dto.completedAt = (DateTime) f.get('Completed_At__c');
        dto.errorMessage = (String) f.get('Error_Message__c');
        Integer pollCount = toInteger(f.get('Poll_Count__c'));
        dto.pollCount = pollCount != null ? pollCount : 0;
        dto.executionTimeMs = (Decimal) f.get('Execution_Time_ms__c');
        dto.queueTimeMs = (Decimal) f.get('Queue_Time_ms__c');
        dto.rawResults = (String) f.get('Raw_Results__c');
        dto.debiasedResults = (String) f.get('Debiased_Results__c');
        dto.resultFingerprint = (String) f.get('Result_Fingerprint__c');
        dto.jobType = (String) f.get('Job_Type__c');
        return dto;
    }

    /**
     * Test the quantum provider connection using stored credentials.
     */
    @AuraEnabled
    public static Map<String, Object> testConnection() {
        Map<String, Object> result = new Map<String, Object>();
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            Boolean connected = provider.testConnection();
            result.put('connected', connected);
            result.put(
                'message',
                connected
                    ? 'Connected to ' + provider.getProviderName()
                    : 'Connection failed - check your API key in the QuantumFair Setup tab'
            );
        } catch (Exception e) {
            result.put('connected', false);
            result.put('message', 'Error: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Get available quantum backends from the active provider.
     * Admin-only (B6): syncs (writes) Quantum_Provider__c and
     * Quantum_Backend__c records and consumes API callouts. The writes below
     * intentionally run in system mode: they seed/refresh shared org-wide
     * provider and backend cache records on behalf of the org, not the user.
     * Regular users read the cached copies via getSettings/getAllBackendHealth.
     */
    @AuraEnabled
    public static List<Map<String, Object>> getAvailableBackends() {
        requireAdmin();
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            List<Map<String, Object>> backends = provider.listBackends();

            // Ensure the IBM provider record exists
            Quantum_Provider__c ibmProvider = ensureIBMProvider();

            // Cache backends as Quantum_Backend__c records (child of Provider)
            List<Quantum_Backend__c> backendRecords = new List<Quantum_Backend__c>();
            for (Map<String, Object> b : backends) {
                String backendName = (String) b.get('name');
                // Extract status — could be a string or {"name":"online"} map
                Object statusObj = b.get('status');
                String statusStr;
                if (statusObj instanceof Map<String, Object>) {
                    statusStr = (String) ((Map<String, Object>) statusObj)
                        .get('name');
                } else {
                    statusStr = String.valueOf(statusObj);
                }

                Quantum_Backend__c rec = new Quantum_Backend__c(
                    Name = backendName,
                    Backend_Key__c = 'ibm:' + backendName,
                    Provider__c = ibmProvider.Id,
                    Status__c = statusStr,
                    Num_Qubits__c = b.get('qubits') != null
                        ? Integer.valueOf(String.valueOf(b.get('qubits')))
                        : 0,
                    Queue_Length__c = b.get('queueLength') != null
                        ? Integer.valueOf(String.valueOf(b.get('queueLength')))
                        : null,
                    Is_Simulator__c = b.get('isSimulator') == true,
                    Processor_Family__c = b.get('processorFamily') != null
                        ? String.valueOf(b.get('processorFamily'))
                        : null,
                    Processor_Revision__c = b.get('processorRevision') != null
                        ? String.valueOf(b.get('processorRevision'))
                        : null,
                    Last_Synced__c = DateTime.now()
                );
                backendRecords.add(rec);
            }
            if (!backendRecords.isEmpty()) {
                upsert backendRecords Backend_Key__c;
            }

            // Update provider last synced timestamp
            ibmProvider.Last_Synced__c = DateTime.now();
            ibmProvider.Status__c = 'Connected';
            update ibmProvider;

            return backends;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to get backends: ' + e.getMessage()
            );
        }
    }

    /**
     * Discover provider-specific instances (e.g. IBM CRNs, IonQ projects).
     * Auto-saves CRN if only one instance found.
     * Admin-only (B6): writes Quantum_Settings__c (org-wide custom setting).
     */
    @AuraEnabled
    public static List<Map<String, String>> discoverInstances() {
        requireAdmin();
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            List<Map<String, String>> instances = provider.discoverInstances();

            // Auto-save if single instance
            if (instances.size() == 1) {
                Quantum_Settings__c settings = Quantum_Settings__c.getOrgDefaults();
                if (settings.Id == null) {
                    settings = new Quantum_Settings__c(
                        SetupOwnerId = UserInfo.getOrganizationId()
                    );
                }
                settings.Instance_CRN__c = instances[0].get('crn');
                upsert settings;
            }

            return instances;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to discover instances: ' + e.getMessage()
            );
        }
    }

    /**
     * Get backend properties summary (T1, T2, errors, queue).
     */
    @AuraEnabled
    public static Map<String, Object> getBackendHealth(String backendName) {
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            Map<String, Object> props = provider.getBackendProperties(
                backendName
            );
            Map<String, Object> summary = new Map<String, Object>();

            // Extract qubit properties for averages
            List<Object> qubits = (List<Object>) props.get('qubits');
            if (qubits != null && !qubits.isEmpty()) {
                Double totalT1 = 0;
                Double totalT2 = 0;
                Double totalReadoutError = 0;
                Integer qubitCount = 0;

                for (Object qubitObj : qubits) {
                    List<Object> qubitProps = (List<Object>) qubitObj;
                    for (Object propObj : qubitProps) {
                        Map<String, Object> prop = (Map<String, Object>) propObj;
                        String name = (String) prop.get('name');
                        Object val = prop.get('value');
                        if (val == null) {
                            continue;
                        }
                        Double value = Double.valueOf(String.valueOf(val));

                        if (name == 'T1') {
                            totalT1 += value;
                        } else if (name == 'T2') {
                            totalT2 += value;
                        } else if (name == 'readout_error') {
                            totalReadoutError += value;
                        }
                    }
                    qubitCount++;
                }

                if (qubitCount > 0) {
                    summary.put('avgT1', totalT1 / qubitCount);
                    summary.put('avgT2', totalT2 / qubitCount);
                    summary.put(
                        'avgReadoutError',
                        totalReadoutError / qubitCount
                    );
                }
                summary.put('qubitCount', qubitCount);
            }

            // Extract gate errors
            List<Object> gates = (List<Object>) props.get('gates');
            if (gates != null && !gates.isEmpty()) {
                Double totalGateError = 0;
                Integer gateCount = 0;

                for (Object gateObj : gates) {
                    Map<String, Object> gate = (Map<String, Object>) gateObj;
                    List<Object> gateParams = (List<Object>) gate.get(
                        'parameters'
                    );
                    if (gateParams != null) {
                        for (Object paramObj : gateParams) {
                            Map<String, Object> param = (Map<String, Object>) paramObj;
                            if (param.get('name') == 'gate_error') {
                                Object val = param.get('value');
                                if (val != null) {
                                    totalGateError += Double.valueOf(
                                        String.valueOf(val)
                                    );
                                    gateCount++;
                                }
                            }
                        }
                    }
                }

                if (gateCount > 0) {
                    summary.put('avgGateError', totalGateError / gateCount);
                }
            }

            summary.put('backendName', backendName);
            summary.put('lastUpdate', (String) props.get('last_update_date'));

            return summary;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to get backend health: ' + e.getMessage()
            );
        }
    }

    /**
     * Get all backend health data from stored Quantum_Backend__c records.
     * FLS (H-S2): rows are passed through stripInaccessible before the DTO
     * is built, so inaccessible fields come back null.
     */
    @AuraEnabled
    public static List<BackendHealthDTO> getAllBackendHealth() {
        List<Quantum_Backend__c> records = [
            SELECT
                Id,
                Name,
                Backend_Key__c,
                Status__c,
                Num_Qubits__c,
                Queue_Length__c,
                Is_Simulator__c,
                Processor_Family__c,
                Processor_Revision__c,
                Max_Shots__c,
                Avg_T1_us__c,
                Avg_T2_us__c,
                Median_Gate_Error__c,
                Median_Readout_Error__c,
                Last_Calibration__c,
                Last_Synced__c,
                Provider__r.Name,
                CHSH_S_Value__c,
                CHSH_Verified_At__c,
                CHSH_Job_Id__c,
                Quantum_Verified__c
            FROM Quantum_Backend__c
            WHERE Provider__r.Is_Active__c = TRUE
            ORDER BY Queue_Length__c ASC NULLS LAST
        ];

        List<BackendHealthDTO> result = new List<BackendHealthDTO>();
        for (
            SObject stripped : Security.stripInaccessible(
                    AccessType.READABLE,
                    records
                )
                .getRecords()
        ) {
            result.add(toDTO(stripped));
        }
        return result;
    }

    private static BackendHealthDTO toDTO(SObject rec) {
        Map<String, Object> f = rec.getPopulatedFieldsAsMap();
        BackendHealthDTO dto = new BackendHealthDTO();
        dto.id = rec.Id;
        dto.name = (String) f.get('Name');
        dto.status = (String) f.get('Status__c');
        Integer qubits = toInteger(f.get('Num_Qubits__c'));
        dto.qubits = qubits != null ? qubits : 0;
        dto.queueLength = toInteger(f.get('Queue_Length__c'));
        dto.isSimulator = (Boolean) f.get('Is_Simulator__c');
        dto.processorFamily = (String) f.get('Processor_Family__c');
        dto.processorRevision = (String) f.get('Processor_Revision__c');
        dto.maxShots = toInteger(f.get('Max_Shots__c'));
        dto.avgT1 = (Decimal) f.get('Avg_T1_us__c');
        dto.avgT2 = (Decimal) f.get('Avg_T2_us__c');
        dto.gateError = (Decimal) f.get('Median_Gate_Error__c');
        dto.readoutError = (Decimal) f.get('Median_Readout_Error__c');
        dto.lastCalibration = (DateTime) f.get('Last_Calibration__c');
        dto.lastSynced = (DateTime) f.get('Last_Synced__c');
        dto.provider = parentName(f.get('Provider__r'));
        dto.chshSValue = (Decimal) f.get('CHSH_S_Value__c');
        dto.chshVerifiedAt = (DateTime) f.get('CHSH_Verified_At__c');
        dto.quantumVerified = (Boolean) f.get('Quantum_Verified__c');
        dto.chshJobId = (String) f.get('CHSH_Job_Id__c');
        dto.recordId = rec.Id;
        return dto;
    }

    /**
     * Refresh health data for all backends from IBM API.
     * Fetches properties for each backend and updates Quantum_Backend__c records.
     * Governor limits: 2 callouts per backend (auth cached after first).
     * Admin-only (B6): writes Quantum_Backend__c cache records and consumes
     * API callouts. Writes run in system mode (shared org-wide cache).
     */
    @AuraEnabled
    public static List<BackendHealthDTO> refreshAllBackendHealth() {
        requireAdmin();
        try {
            // Ensure backends are synced first
            Integer backendCount = [
                SELECT COUNT()
                FROM Quantum_Backend__c
            ];
            if (backendCount == 0) {
                // Sync backends from IBM
                getAvailableBackends();
            }

            List<Quantum_Backend__c> backends = [
                SELECT
                    Id,
                    Name,
                    Backend_Key__c,
                    Status__c,
                    Num_Qubits__c,
                    Queue_Length__c,
                    Is_Simulator__c,
                    Processor_Family__c,
                    Processor_Revision__c,
                    Max_Shots__c,
                    Avg_T1_us__c,
                    Avg_T2_us__c,
                    Median_Gate_Error__c,
                    Median_Readout_Error__c,
                    Last_Calibration__c,
                    Last_Synced__c,
                    Provider__r.Name
                FROM Quantum_Backend__c
                WHERE
                    Provider__r.Is_Active__c = TRUE
                    AND Is_Simulator__c = FALSE
                ORDER BY Name
                LIMIT 10
            ];

            List<Quantum_Backend__c> toUpdate = new List<Quantum_Backend__c>();
            for (Quantum_Backend__c backend : backends) {
                try {
                    QuantumProvider prov = QuantumProviderFactory.getActiveProvider();
                    Map<String, Object> props = prov.getBackendProperties(
                        backend.Name
                    );
                    updateBackendFromProperties(backend, props);
                    toUpdate.add(backend);
                } catch (Exception e) {
                    // Skip backends that fail — don't block the rest
                    System.debug(
                        'Failed to refresh ' +
                            backend.Name +
                            ': ' +
                            e.getMessage()
                    );
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }

            return getAllBackendHealth();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to refresh backend health: ' + e.getMessage()
            );
        }
    }

    private static void updateBackendFromProperties(
        Quantum_Backend__c backend,
        Map<String, Object> props
    ) {
        List<Object> qubits = (List<Object>) props.get('qubits');
        if (qubits != null && !qubits.isEmpty()) {
            Double totalT1 = 0;
            Double totalT2 = 0;
            Double totalReadoutError = 0;
            Integer qubitCount = 0;

            for (Object qubitObj : qubits) {
                List<Object> qubitProps = (List<Object>) qubitObj;
                for (Object propObj : qubitProps) {
                    Map<String, Object> prop = (Map<String, Object>) propObj;
                    String name = (String) prop.get('name');
                    Object val = prop.get('value');
                    if (val == null) {
                        continue;
                    }
                    Double value = Double.valueOf(String.valueOf(val));
                    if (name == 'T1') {
                        totalT1 += value;
                    } else if (name == 'T2') {
                        totalT2 += value;
                    } else if (name == 'readout_error') {
                        totalReadoutError += value;
                    }
                }
                qubitCount++;
            }

            if (qubitCount > 0) {
                backend.Avg_T1_us__c = totalT1 / qubitCount;
                backend.Avg_T2_us__c = totalT2 / qubitCount;
                backend.Median_Readout_Error__c =
                    totalReadoutError / qubitCount;
            }
        }

        List<Object> gates = (List<Object>) props.get('gates');
        if (gates != null && !gates.isEmpty()) {
            Double totalGateError = 0;
            Integer gateCount = 0;
            for (Object gateObj : gates) {
                Map<String, Object> gate = (Map<String, Object>) gateObj;
                List<Object> gateParams = (List<Object>) gate.get('parameters');
                if (gateParams != null) {
                    for (Object paramObj : gateParams) {
                        Map<String, Object> param = (Map<String, Object>) paramObj;
                        if (param.get('name') == 'gate_error') {
                            Object val = param.get('value');
                            if (val != null) {
                                totalGateError += Double.valueOf(
                                    String.valueOf(val)
                                );
                                gateCount++;
                            }
                        }
                    }
                }
            }
            if (gateCount > 0) {
                backend.Median_Gate_Error__c = totalGateError / gateCount;
            }
        }

        String lastUpdate = (String) props.get('last_update_date');
        if (String.isNotBlank(lastUpdate)) {
            try {
                backend.Last_Calibration__c = DateTime.valueOf(
                    lastUpdate.replace('T', ' ').substring(0, 19)
                );
            } catch (Exception e) {
                // Ignore date parse errors
            }
        }
        backend.Last_Synced__c = DateTime.now();
    }

    /**
     * Get current settings
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSettings() {
        Map<String, Object> settings = new Map<String, Object>();
        Quantum_Settings__c s = Quantum_Settings__c.getInstance();

        if (s != null) {
            settings.put('hasApiKey', String.isNotBlank(s.IBM_API_Key__c));
            settings.put('hasCRN', String.isNotBlank(s.Instance_CRN__c));
            settings.put('crnValue', s.Instance_CRN__c);
            settings.put('defaultBackend', s.Default_Backend__c);
            settings.put('defaultShots', s.Default_Shots__c);
            settings.put('useBellTest', s.Use_Bell_Test__c);
            settings.put('useLeastBusy', s.Use_Least_Busy__c);
            settings.put('pollIntervalMinutes', s.Poll_Interval_Minutes__c);
            settings.put('complianceEmail', s.Compliance_Email__c);
        } else {
            settings.put('hasApiKey', false);
            settings.put('hasCRN', false);
            settings.put('defaultBackend', '');
            settings.put('defaultShots', 1024);
            settings.put('useBellTest', false);
            settings.put('useLeastBusy', false);
            settings.put('pollIntervalMinutes', 5);
            settings.put('complianceEmail', '');
        }
        settings.put('sweeperActive', JobSweeper.isScheduled());
        settings.put(
            'integrityCheckActive',
            IntegrityVerificationJob.isScheduled()
        );
        settings.put(
            'integrityCheckHour',
            s != null &&
                s.Integrity_Check_Hour__c != null
                ? s.Integrity_Check_Hour__c
                : 2
        );

        // Load cached backends from Quantum_Backend__c records.
        // FLS (H-S2): stripInaccessible so inaccessible fields come back null.
        List<SObject> cachedBackends = Security.stripInaccessible(
                AccessType.READABLE,
                [
                    SELECT
                        Name,
                        Backend_Key__c,
                        Status__c,
                        Num_Qubits__c,
                        Provider__c,
                        Provider__r.Name,
                        Queue_Length__c,
                        Is_Simulator__c,
                        Processor_Family__c,
                        Processor_Revision__c,
                        Max_Shots__c,
                        Avg_T1_us__c,
                        Avg_T2_us__c,
                        Median_Gate_Error__c,
                        Median_Readout_Error__c,
                        Last_Calibration__c,
                        Last_Synced__c
                    FROM Quantum_Backend__c
                    ORDER BY Name
                ]
            )
            .getRecords();
        if (!cachedBackends.isEmpty()) {
            List<Map<String, Object>> backendList = new List<Map<String, Object>>();
            for (SObject cb : cachedBackends) {
                Map<String, Object> f = cb.getPopulatedFieldsAsMap();
                Map<String, Object> bMap = new Map<String, Object>();
                bMap.put('name', f.get('Name'));
                bMap.put('status', f.get('Status__c'));
                bMap.put('qubits', f.get('Num_Qubits__c'));
                bMap.put('provider', parentName(f.get('Provider__r')));
                bMap.put('maxShots', f.get('Max_Shots__c'));
                bMap.put('queueLength', f.get('Queue_Length__c'));
                bMap.put('isSimulator', f.get('Is_Simulator__c'));
                bMap.put('processorFamily', f.get('Processor_Family__c'));
                backendList.add(bMap);
            }
            settings.put('cachedBackends', backendList);
        }

        return settings;
    }

    /**
     * Save settings. Admin-only (B6), enforced via requireAdmin().
     * Writes to Quantum_Settings__c run in system mode by design: it is an
     * org-wide (hierarchy) custom setting owned by the org, and access is
     * gated by the QuantumFair_Administer custom permission above.
     *
     * Side effects (B7):
     * - Logs a SETTINGS_CHANGED Compliance_Event__c naming the changed
     *   fields (never the API key value itself).
     * - Auto-schedules JobSweeper and IntegrityVerificationJob once an API
     *   key is configured, and ComplianceDigestJob while a compliance email
     *   is configured (unscheduled when the email is cleared). Scheduling
     *   failures never block the save; they are logged as SCHEDULING_FAILED
     *   compliance events.
     */
    @AuraEnabled
    public static void saveSettings(
        String apiKey,
        String instanceCRN,
        String defaultBackend,
        Integer defaultShots,
        Boolean useBellTest,
        Boolean useLeastBusy,
        Integer pollIntervalMinutes,
        String complianceEmail
    ) {
        requireAdmin();

        Quantum_Settings__c settings = Quantum_Settings__c.getOrgDefaults();

        if (settings.Id == null) {
            settings = new Quantum_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }

        List<String> changedFields = new List<String>();
        if (String.isNotBlank(apiKey)) {
            settings.IBM_API_Key__c = apiKey;
            // Never log the key itself — only the fact that it changed.
            changedFields.add('API key updated');
        }
        if (String.isNotBlank(instanceCRN)) {
            if (instanceCRN != settings.Instance_CRN__c) {
                changedFields.add('Instance_CRN__c');
            }
            settings.Instance_CRN__c = instanceCRN;
        }
        if (String.isNotBlank(defaultBackend)) {
            if (defaultBackend != settings.Default_Backend__c) {
                changedFields.add('Default_Backend__c');
            }
            settings.Default_Backend__c = defaultBackend;
        }
        if (defaultShots != null) {
            if (settings.Default_Shots__c != defaultShots) {
                changedFields.add('Default_Shots__c');
            }
            settings.Default_Shots__c = defaultShots;
        }
        if (useBellTest != null) {
            if (settings.Use_Bell_Test__c != useBellTest) {
                changedFields.add('Use_Bell_Test__c');
            }
            settings.Use_Bell_Test__c = useBellTest;
        }
        if (useLeastBusy != null) {
            if (settings.Use_Least_Busy__c != useLeastBusy) {
                changedFields.add('Use_Least_Busy__c');
            }
            settings.Use_Least_Busy__c = useLeastBusy;
        }
        if (pollIntervalMinutes != null && pollIntervalMinutes > 0) {
            if (settings.Poll_Interval_Minutes__c != pollIntervalMinutes) {
                changedFields.add('Poll_Interval_Minutes__c');
            }
            settings.Poll_Interval_Minutes__c = pollIntervalMinutes;
        }
        if (complianceEmail != null) {
            if (settings.Compliance_Email__c != complianceEmail) {
                changedFields.add('Compliance_Email__c');
            }
            settings.Compliance_Email__c = complianceEmail;
        }

        upsert settings;

        // Clear auth cache since API key may have changed
        IBMQuantumAuth.clearCache();

        logSettingsChange(changedFields);
        applyAutoScheduling(settings, complianceEmail);
    }

    /**
     * Audit trail (B6): record which settings fields changed and by whom.
     * ComplianceEventLogger stamps Actor__c with the running user. The API
     * key value itself is never written to the log. Logging failures must
     * never roll back the settings save itself.
     */
    private static void logSettingsChange(List<String> changedFields) {
        if (changedFields.isEmpty()) {
            return;
        }
        try {
            ComplianceEventLogger.log(
                'SETTINGS_CHANGED',
                'INFO',
                null,
                null,
                new Map<String, Object>{
                    'changedFields' => changedFields,
                    'actorUsername' => UserInfo.getUserName()
                }
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Failed to log settings change: ' + e.getMessage()
            );
        }
    }

    /**
     * B7: keep the background machinery alive without requiring the admin to
     * find each toggle. Called after every successful saveSettings.
     * Failures are logged as SCHEDULING_FAILED compliance events instead of
     * being thrown, so a schedule hiccup never blocks a settings save. The
     * explicit start/stop toggle methods DO surface failures to the admin.
     */
    private static void applyAutoScheduling(
        Quantum_Settings__c settings,
        String complianceEmailParam
    ) {
        try {
            if (String.isNotBlank(settings.IBM_API_Key__c)) {
                if (!JobSweeper.isScheduled()) {
                    JobSweeper.scheduleDefault();
                }
                if (!IntegrityVerificationJob.isScheduled()) {
                    IntegrityVerificationJob.scheduleDefault();
                }
            }
            if (String.isNotBlank(settings.Compliance_Email__c)) {
                if (!ComplianceDigestJob.isScheduled()) {
                    ComplianceDigestJob.scheduleDefault();
                }
            } else if (complianceEmailParam != null) {
                // Admin explicitly cleared the compliance email — stop the
                // daily digest so no further emails are attempted.
                ComplianceDigestJob.unschedule();
            }
        } catch (Exception e) {
            try {
                ComplianceEventLogger.log(
                    'SCHEDULING_FAILED',
                    'WARNING',
                    null,
                    null,
                    new Map<String, Object>{
                        'error' => e.getMessage(),
                        'context' => 'saveSettings auto-scheduling'
                    }
                );
            } catch (Exception logEx) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Auto-scheduling failed and could not be logged: ' +
                        e.getMessage() +
                        ' / ' +
                        logEx.getMessage()
                );
            }
        }
    }

    /**
     * Export compliance evidence package as JSON for a given framework and date range.
     * Admin-only (B6): gated on QuantumFair_Administer only. Auditors do not
     * get direct export access — an admin runs the export and hands the
     * evidence package to the auditor (auditors retain read access to the
     * underlying records via the QuantumFair_Auditor permission set).
     */
    @AuraEnabled
    public static String exportComplianceEvidence(
        String framework,
        String startDate,
        String endDate
    ) {
        requireAdmin();
        Date sDate = Date.valueOf(startDate);
        Date eDate = Date.valueOf(endDate);
        return ComplianceEvidenceExporter.exportForFramework(
            framework,
            sDate,
            eDate
        );
    }

    /**
     * Start the background job sweeper. Admin-only (B6).
     * Explicit toggle: scheduling failures ARE surfaced to the admin.
     */
    @AuraEnabled
    public static void startSweeper() {
        requireAdmin();
        try {
            JobSweeper.scheduleDefault();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to start the job sweeper: ' + e.getMessage()
            );
        }
    }

    /**
     * Stop the background job sweeper. Admin-only (B6).
     */
    @AuraEnabled
    public static void stopSweeper() {
        requireAdmin();
        try {
            JobSweeper.unschedule();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to stop the job sweeper: ' + e.getMessage()
            );
        }
    }

    /**
     * Start the nightly integrity verification job. Admin-only (B6).
     * Explicit toggle: scheduling failures ARE surfaced to the admin.
     */
    @AuraEnabled
    public static void startIntegrityCheck() {
        requireAdmin();
        try {
            IntegrityVerificationJob.scheduleDefault();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to start the integrity check: ' + e.getMessage()
            );
        }
    }

    /**
     * Stop the nightly integrity verification job. Admin-only (B6).
     */
    @AuraEnabled
    public static void stopIntegrityCheck() {
        requireAdmin();
        try {
            IntegrityVerificationJob.unschedule();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to stop the integrity check: ' + e.getMessage()
            );
        }
    }

    /**
     * Submit a CHSH verification job for a backend.
     * Delegates to the active provider's verification implementation.
     * For IBM: uses Estimator V2 with optimal CHSH measurement angles.
     *
     * Governor limits: 3-4 callouts (provider-dependent)
     * Admin-only (B6): consumes real QPU time on the org's provider account.
     */
    @AuraEnabled
    public static Id verifyBackendQuantum(String backendName) {
        requireAdmin();
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            return provider.submitVerificationJob(backendName, 4096);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Backend verification failed: ' + e.getMessage()
            );
        }
    }

    /**
     * Submit a quantum job from LWC.
     * Uses the active provider's circuit building and job submission.
     */
    @AuraEnabled
    public static Id submitQuantumJob(
        String backend,
        Integer numQubits,
        Integer shots,
        String purpose,
        Boolean useBellTest
    ) {
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            Quantum_Settings__c settings = Quantum_Settings__c.getInstance();

            String backendName;
            if (String.isNotBlank(backend)) {
                backendName = backend;
            } else if (settings != null && settings.Use_Least_Busy__c == true) {
                backendName = provider.getLeastBusyBackend();
            }
            if (String.isBlank(backendName) && settings != null) {
                backendName = settings.Default_Backend__c;
            }

            Integer numQ = numQubits != null ? numQubits : 8;
            Integer numShots = shots != null
                ? shots
                : (settings != null &&
                      settings.Default_Shots__c != null
                      ? (Integer) settings.Default_Shots__c
                      : 1024);
            Boolean bell = useBellTest != null ? useBellTest : false;

            // Build circuit via provider (handles qubit selection, topology)
            String qasm = provider.buildCircuit(numQ, backendName, bell);

            return provider.submitTrackedJob(
                qasm,
                backendName,
                numShots,
                purpose,
                bell,
                numQ
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Get recent quantum jobs.
     * FLS (H-S2): rows are passed through stripInaccessible before the DTO
     * is built, so inaccessible fields come back null.
     */
    @AuraEnabled(cacheable=true)
    public static List<JobSummaryDTO> getRecentJobs() {
        List<Quantum_Job__c> jobs = [
            SELECT
                Id,
                Name,
                External_Job_ID__c,
                Backend__c,
                Status__c,
                Shots__c,
                Num_Qubits__c,
                Purpose__c,
                Use_Bell_Test__c,
                Job_Type__c,
                Submitted_At__c,
                Completed_At__c,
                Execution_Time_ms__c,
                QPU_Time_seconds__c,
                Requested_By__c,
                Requested_By__r.Name,
                Error_Message__c
            FROM Quantum_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
        List<JobSummaryDTO> result = new List<JobSummaryDTO>();
        for (
            SObject stripped : Security.stripInaccessible(
                    AccessType.READABLE,
                    jobs
                )
                .getRecords()
        ) {
            Map<String, Object> f = stripped.getPopulatedFieldsAsMap();
            JobSummaryDTO dto = new JobSummaryDTO();
            dto.id = stripped.Id;
            dto.name = (String) f.get('Name');
            dto.externalJobId = (String) f.get('External_Job_ID__c');
            dto.backend = (String) f.get('Backend__c');
            dto.status = (String) f.get('Status__c');
            dto.jobType = (String) f.get('Job_Type__c');
            dto.useBellTest = (Boolean) f.get('Use_Bell_Test__c');
            dto.shots = toInteger(f.get('Shots__c'));
            dto.numQubits = toInteger(f.get('Num_Qubits__c'));
            dto.purpose = (String) f.get('Purpose__c');
            dto.submittedAt = (DateTime) f.get('Submitted_At__c');
            dto.completedAt = (DateTime) f.get('Completed_At__c');
            dto.executionTimeMs = (Decimal) f.get('Execution_Time_ms__c');
            dto.qpuTimeSeconds = (Decimal) f.get('QPU_Time_seconds__c');
            dto.requestedByName = parentName(f.get('Requested_By__r'));
            dto.errorMessage = (String) f.get('Error_Message__c');
            result.add(dto);
        }
        return result;
    }

    /**
     * Get job details with related data.
     * FLS (H-S2): the returned record is passed through stripInaccessible,
     * so fields the user cannot read (e.g. Raw_Results__c for auditors) are
     * simply absent from the response instead of leaking.
     */
    @AuraEnabled(cacheable=true)
    public static Quantum_Job__c getJobDetails(Id jobId) {
        Quantum_Job__c job = [
            SELECT
                Id,
                Name,
                External_Job_ID__c,
                Backend__c,
                Status__c,
                Circuit_QASM__c,
                Shots__c,
                Num_Qubits__c,
                Raw_Results__c,
                Debiased_Results__c,
                Purpose__c,
                Use_Bell_Test__c,
                Submitted_At__c,
                Completed_At__c,
                Requested_By__c,
                Error_Message__c,
                Execution_Time_ms__c,
                Queue_Time_ms__c,
                Poll_Count__c,
                Assignment_Type__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];
        return (Quantum_Job__c) Security.stripInaccessible(
                AccessType.READABLE,
                new List<Quantum_Job__c>{ job }
            )
            .getRecords()[0];
    }

    /**
     * Get certificate as a DTO for the fairness certificate LWC.
     */
    @AuraEnabled(cacheable=true)
    public static CertificateDTO getCertificateDTO(Id certificateId) {
        Fairness_Certificate__c cert = [
            SELECT
                Id,
                Name,
                External_Job_ID__c,
                Backend__c,
                Circuit_QASM__c,
                Raw_Bitstring_Hash__c,
                Debiased_Bitstring_Hash__c,
                Assignment_Hash__c,
                Validation_Results__c,
                CHSH_S_Value__c,
                Created_By_User__c,
                Purpose__c,
                Status__c,
                Quantum_Job__c,
                CreatedDate,
                Tampered__c,
                Last_Integrity_Check__c,
                Backend_Verified__c,
                Backend_Verified_At__c
            FROM Fairness_Certificate__c
            WHERE Id = :certificateId
            LIMIT 1
        ];

        // FLS (H-S2): strip fields the running user cannot read.
        Map<String, Object> f = Security.stripInaccessible(
                    AccessType.READABLE,
                    new List<Fairness_Certificate__c>{ cert }
                )
                .getRecords()[0]
            .getPopulatedFieldsAsMap();

        CertificateDTO dto = new CertificateDTO();
        dto.name = (String) f.get('Name');
        dto.externalJobId = (String) f.get('External_Job_ID__c');
        dto.backend = (String) f.get('Backend__c');
        dto.circuitQasm = (String) f.get('Circuit_QASM__c');
        dto.rawBitstringHash = (String) f.get('Raw_Bitstring_Hash__c');
        dto.debiasedBitstringHash = (String) f.get(
            'Debiased_Bitstring_Hash__c'
        );
        dto.assignmentHash = (String) f.get('Assignment_Hash__c');
        dto.validationResults = (String) f.get('Validation_Results__c');
        dto.chshSValue = (Decimal) f.get('CHSH_S_Value__c');
        dto.createdByUser = (String) f.get('Created_By_User__c');
        dto.purpose = (String) f.get('Purpose__c');
        dto.status = (String) f.get('Status__c');
        dto.quantumJobId = (Id) f.get('Quantum_Job__c');
        dto.createdDate = (DateTime) f.get('CreatedDate');
        dto.tampered = (Boolean) f.get('Tampered__c');
        dto.lastIntegrityCheck = (DateTime) f.get('Last_Integrity_Check__c');
        dto.backendVerified = (Boolean) f.get('Backend_Verified__c');
        dto.backendVerifiedAt = (DateTime) f.get('Backend_Verified_At__c');
        return dto;
    }

    /**
     * Get certificate by job ID
     */
    @AuraEnabled(cacheable=true)
    public static Fairness_Certificate__c getCertificateByJobId(Id jobId) {
        List<Fairness_Certificate__c> certs = [
            SELECT
                Id,
                Name,
                External_Job_ID__c,
                Backend__c,
                Circuit_QASM__c,
                Raw_Bitstring_Hash__c,
                Debiased_Bitstring_Hash__c,
                Assignment_Hash__c,
                Validation_Results__c,
                CHSH_S_Value__c,
                Created_By_User__c,
                Purpose__c,
                Status__c,
                Quantum_Job__c,
                CreatedDate
            FROM Fairness_Certificate__c
            WHERE Quantum_Job__c = :jobId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (certs.isEmpty()) {
            return null;
        }
        // FLS (H-S2): strip fields the running user cannot read.
        return (Fairness_Certificate__c) Security.stripInaccessible(
                AccessType.READABLE,
                certs
            )
            .getRecords()[0];
    }

    /**
     * Get assignments for a job.
     * FLS (H-S2): records are passed through stripInaccessible.
     */
    @AuraEnabled(cacheable=true)
    public static List<Quantum_Assignment__c> getAssignments(Id jobId) {
        return (List<Quantum_Assignment__c>) Security.stripInaccessible(
                AccessType.READABLE,
                [
                    SELECT
                        Id,
                        Name,
                        Assigned_Record_ID__c,
                        Assigned_To_ID__c,
                        Assignment_Index__c,
                        Random_Value__c,
                        Certificate__c
                    FROM Quantum_Assignment__c
                    WHERE Quantum_Job__c = :jobId
                    ORDER BY Assignment_Index__c
                ]
            )
            .getRecords();
    }

    /**
     * Get assignments for a job as plain maps for LWC consumption.
     * Contract (stable keys, all values null when the field is not readable
     * by the running user):
     *   id          → Quantum_Assignment__c record Id
     *   name        → Name
     *   index       → Assignment_Index__c
     *   recordId    → Assigned_Record_ID__c
     *   assigneeId  → Assigned_To_ID__c
     *   randomValue → Random_Value__c
     * FLS (H-S2): records are passed through stripInaccessible.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAssignmentsDTO(Id jobId) {
        List<SObject> stripped = Security.stripInaccessible(
                AccessType.READABLE,
                [
                    SELECT
                        Id,
                        Name,
                        Assigned_Record_ID__c,
                        Assigned_To_ID__c,
                        Assignment_Index__c,
                        Random_Value__c
                    FROM Quantum_Assignment__c
                    WHERE Quantum_Job__c = :jobId
                    ORDER BY Assignment_Index__c
                ]
            )
            .getRecords();

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (SObject s : stripped) {
            Map<String, Object> f = s.getPopulatedFieldsAsMap();
            result.add(
                new Map<String, Object>{
                    'id' => s.Id,
                    'name' => f.get('Name'),
                    'index' => f.get('Assignment_Index__c'),
                    'recordId' => f.get('Assigned_Record_ID__c'),
                    'assigneeId' => f.get('Assigned_To_ID__c'),
                    'randomValue' => f.get('Random_Value__c')
                }
            );
        }
        return result;
    }

    /**
     * Get audit trail as DTOs for the LWC audit trail component.
     */
    @AuraEnabled(cacheable=true)
    public static List<AuditTrailDTO> getAuditTrailDTO() {
        List<Fairness_Certificate__c> certs = [
            SELECT
                Id,
                Name,
                External_Job_ID__c,
                Backend__c,
                Status__c,
                Purpose__c,
                CHSH_S_Value__c,
                CreatedDate,
                Quantum_Job__c,
                Created_By_User__c,
                Tampered__c
            FROM Fairness_Certificate__c
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];

        // FLS (H-S2): strip fields the running user cannot read.
        List<AuditTrailDTO> dtos = new List<AuditTrailDTO>();
        for (
            SObject stripped : Security.stripInaccessible(
                    AccessType.READABLE,
                    certs
                )
                .getRecords()
        ) {
            Map<String, Object> f = stripped.getPopulatedFieldsAsMap();
            AuditTrailDTO dto = new AuditTrailDTO();
            dto.recordId = stripped.Id;
            dto.name = (String) f.get('Name');
            dto.externalJobId = (String) f.get('External_Job_ID__c');
            dto.backend = (String) f.get('Backend__c');
            dto.status = (String) f.get('Status__c');
            dto.purpose = (String) f.get('Purpose__c');
            dto.chshSValue = (Decimal) f.get('CHSH_S_Value__c');
            dto.createdDate = (DateTime) f.get('CreatedDate');
            dto.quantumJobId = (Id) f.get('Quantum_Job__c');
            dto.createdByUser = (String) f.get('Created_By_User__c');
            dto.tampered = (Boolean) f.get('Tampered__c');
            dtos.add(dto);
        }
        return dtos;
    }

    /**
     * Verify certificate integrity.
     * H-S2: user-initiated write — the delegated service records the
     * verification outcome (Tampered__c, verification timestamps) on the
     * certificate, so require explicit update rights up front. Read-only
     * personas (auditors) view integrity state instead of re-running checks.
     */
    @AuraEnabled
    public static Map<String, Object> verifyCertificate(Id certificateId) {
        if (!Schema.sObjectType.Fairness_Certificate__c.isUpdateable()) {
            throw new AuraHandledException(NO_PERMISSION_MSG);
        }
        try {
            return FairnessCertificateService.verifyCertificate(certificateId);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Verification failed: ' + e.getMessage()
            );
        }
    }

    /**
     * Manually refresh job status from IBM Quantum.
     * Useful for debugging or when the poller has stopped.
     * H-S2: user-initiated write — require update rights on Quantum_Job__c.
     * The status sync itself intentionally runs in system mode: it mirrors
     * the async polling pipeline (JobPoller/JobSweeper), which must update
     * pipeline-managed fields regardless of per-field FLS. Row access is
     * still constrained by 'with sharing'.
     */
    @AuraEnabled
    public static Map<String, Object> refreshJobStatus(Id jobId) {
        if (!Schema.sObjectType.Quantum_Job__c.isUpdateable()) {
            throw new AuraHandledException(NO_PERMISSION_MSG);
        }
        try {
            Quantum_Job__c job = [
                SELECT Id, External_Job_ID__c, Status__c
                FROM Quantum_Job__c
                WHERE Id = :jobId
                LIMIT 1
            ];

            if (String.isBlank(job.External_Job_ID__c)) {
                throw new QuantumException(
                    'No external job ID — cannot check status.'
                );
            }

            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            Map<String, Object> ibmStatus = provider.getJobStatus(
                job.External_Job_ID__c
            );

            // Extract and normalize via shared utility
            String rawStatus = IBMResponseParser.extractStatus(ibmStatus);
            String normalizedStatus = IBMResponseParser.normalizeStatus(
                rawStatus
            );

            // Update job record — capture error details or clear if healthy.
            // 'Unknown' is not a valid Status__c picklist value: keep the
            // stored status and let the poller/sweeper treat it as transient.
            if (normalizedStatus != 'Unknown') {
                job.Status__c = normalizedStatus;
            }
            if (normalizedStatus == 'Failed') {
                job.Error_Message__c = IBMResponseParser.buildErrorMessage(
                    rawStatus,
                    ibmStatus
                );
            } else {
                job.Error_Message__c = null;
            }

            update job;

            Map<String, Object> result = new Map<String, Object>();
            result.put('status', normalizedStatus);
            result.put('ibmStatus', rawStatus);
            result.put('jobId', jobId);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to refresh status: ' + e.getMessage()
            );
        }
    }

    /**
     * Manually retrieve results for a completed job.
     * Delegates to JobProcessor for the actual parsing and certification pipeline.
     * H-S2: user-initiated write — require update rights on Quantum_Job__c.
     * The downstream JobProcessor pipeline (results, certification, events)
     * intentionally runs in system mode, same as when invoked by the async
     * poller/sweeper. Row access is still constrained by 'with sharing'.
     */
    @AuraEnabled
    public static Map<String, Object> retrieveJobResults(Id jobId) {
        if (!Schema.sObjectType.Quantum_Job__c.isUpdateable()) {
            throw new AuraHandledException(NO_PERMISSION_MSG);
        }
        try {
            Quantum_Job__c job = [
                SELECT
                    Id,
                    External_Job_ID__c,
                    Status__c,
                    Backend__c,
                    Circuit_QASM__c,
                    Shots__c,
                    Num_Qubits__c,
                    Purpose__c,
                    Use_Bell_Test__c,
                    Submitted_At__c,
                    Raw_Results__c,
                    Program_Id__c,
                    Validation_Results__c
                FROM Quantum_Job__c
                WHERE Id = :jobId
                LIMIT 1
            ];

            if (String.isBlank(job.External_Job_ID__c)) {
                throw new QuantumException(
                    'No external job ID on this record.'
                );
            }

            // Fetch results and status via provider
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            String resultsJson = provider.getJobResults(job.External_Job_ID__c);
            Map<String, Object> ibmStatus = provider.getJobStatus(
                job.External_Job_ID__c
            );

            // Delegate to shared processor
            JobProcessor.ProcessingResult pr;
            if (job.Program_Id__c == 'estimator') {
                pr = JobProcessor.processEstimatorCompletion(
                    job,
                    resultsJson,
                    ibmStatus
                );
            } else {
                pr = JobProcessor.processSamplerCompletion(
                    job,
                    resultsJson,
                    ibmStatus
                );
            }

            Map<String, Object> result = new Map<String, Object>();
            result.put('status', pr.status);
            result.put('certificateId', pr.certificateId);
            result.put('chshSValue', pr.chshSValue);
            result.put('bellTestPassed', pr.bellTestPassed);
            result.put('rawBitsLength', pr.rawBitsLength);
            result.put('debiasedBitsLength', pr.debiasedBitsLength);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to retrieve results: ' + e.getMessage()
            );
        }
    }

    /**
     * Ensure the IBM Quantum provider record exists, creating it if needed.
     * Returns the Quantum_Provider__c record for IBM.
     * System-mode by design: this seeds a shared org-wide provider record.
     * Only reachable via admin-gated methods (getAvailableBackends), which
     * call requireAdmin() before reaching this path.
     */
    private static Quantum_Provider__c ensureIBMProvider() {
        List<Quantum_Provider__c> providers = [
            SELECT Id, Name, Provider_Key__c, Status__c, Last_Synced__c
            FROM Quantum_Provider__c
            WHERE Provider_Key__c = 'ibm'
            LIMIT 1
        ];
        if (!providers.isEmpty()) {
            return providers[0];
        }
        Quantum_Provider__c ibm = new Quantum_Provider__c(
            Name = 'IBM Quantum',
            Provider_Key__c = 'ibm',
            Provider_Class__c = 'IBMQuantumService',
            Auth_Endpoint__c = 'https://iam.cloud.ibm.com/identity/token',
            API_Base_URL__c = 'https://quantum.cloud.ibm.com/api',
            Is_Active__c = true,
            Status__c = 'Connected'
        );
        insert ibm;
        return ibm;
    }

    /**
     * Get usage statistics.
     * H-S2: counts run WITH USER_MODE so they reflect only records the
     * running user can actually see.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUsageStats() {
        Map<String, Object> stats = new Map<String, Object>();

        stats.put(
            'totalJobs',
            [SELECT COUNT() FROM Quantum_Job__c WITH USER_MODE]
        );
        stats.put(
            'completedJobs',
            [
                SELECT COUNT()
                FROM Quantum_Job__c
                WHERE Status__c = 'Completed'
                WITH USER_MODE
            ]
        );
        stats.put(
            'failedJobs',
            [
                SELECT COUNT()
                FROM Quantum_Job__c
                WHERE Status__c = 'Failed'
                WITH USER_MODE
            ]
        );
        stats.put(
            'totalCertificates',
            [
                SELECT COUNT()
                FROM Fairness_Certificate__c
                WHERE Status__c = 'Certified'
                WITH USER_MODE
            ]
        );
        stats.put(
            'totalAssignments',
            [SELECT COUNT() FROM Quantum_Assignment__c WITH USER_MODE]
        );

        return stats;
    }
}
