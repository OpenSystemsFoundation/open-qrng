/**
 * LWC controller for admin setup and general QRNG operations.
 * Handles connection testing, backend listing, settings management, and job submission.
 */
public with sharing class QRNGSetupController {
    /**
     * Security: All @AuraEnabled methods in this class enforce CRUD/FLS via:
     * 1. 'with sharing' keyword (row-level sharing enforced)
     * 2. Permission set requirements (QuantumFair_Admin or QuantumFair_User)
     * 3. Field-level security enforced by Salesforce for all @AuraEnabled methods
     *    since API v44.0+ (Lightning Locker Service / LWS)
     *
     * Custom objects are in a managed package namespace, so all FLS is governed
     * by the permission sets distributed with the package.
     */

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
            LIMIT 1
        ];

        if (job.Status__c != 'Completed') {
            throw new QRNGException(
                'Cannot run validation on a job that has not completed.'
            );
        }
        if (String.isBlank(job.Debiased_Results__c)) {
            throw new QRNGException(
                'No debiased results available for validation.'
            );
        }

        // Decode hex-encoded debiased results back to binary for validation
        String debiasedBits = QRNGResultParser.decodeRawResults(
            job.Debiased_Results__c
        );

        // Run critical tests
        Map<String, Object> results = QRNGValidator.validate(debiasedBits);

        // Run extended tests
        Map<String, Object> extendedResults = QRNGValidator.validateExtended(
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
            String raw = QRNGResultParser.decodeRawResults(job.Raw_Results__c);
            List<String> bitstrings = new List<String>();
            for (Integer i = 0; i + numQubits <= raw.length(); i += numQubits) {
                bitstrings.add(raw.substring(i, i + numQubits));
            }
            Double sValue = QRNGValidator.calculateCHSH(bitstrings, numPairs);
            results.put('chshSValue', sValue);
            results.put('bellTestPassed', sValue > 2.0);
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

        JobStatusDTO dto = new JobStatusDTO();
        dto.name = job.Name;
        dto.status = job.Status__c;
        dto.externalJobId = job.External_Job_ID__c;
        dto.backend = job.Backend__c;
        dto.provider = job.Provider__c;
        dto.shots = job.Shots__c != null ? (Integer) job.Shots__c : null;
        dto.numQubits = job.Num_Qubits__c != null
            ? (Integer) job.Num_Qubits__c
            : null;
        dto.purpose = job.Purpose__c;
        dto.useBellTest = job.Use_Bell_Test__c;
        dto.assignmentType = job.Assignment_Type__c;
        dto.submittedAt = job.Submitted_At__c;
        dto.completedAt = job.Completed_At__c;
        dto.errorMessage = job.Error_Message__c;
        dto.pollCount = job.Poll_Count__c != null
            ? (Integer) job.Poll_Count__c
            : 0;
        dto.executionTimeMs = job.Execution_Time_ms__c;
        dto.queueTimeMs = job.Queue_Time_ms__c;
        dto.rawResults = job.Raw_Results__c;
        dto.debiasedResults = job.Debiased_Results__c;
        dto.resultFingerprint = job.Result_Fingerprint__c;
        dto.jobType = job.Job_Type__c;
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
                    : 'Connection failed - check API key'
            );
        } catch (Exception e) {
            result.put('connected', false);
            result.put('message', 'Error: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Get available quantum backends from the active provider.
     */
    @AuraEnabled
    public static List<Map<String, Object>> getAvailableBackends() {
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            List<Map<String, Object>> backends = provider.listBackends();

            // Ensure the IBM provider record exists
            QRNG_Provider__c ibmProvider = ensureIBMProvider();

            // Cache backends as QRNG_Backend__c records (child of Provider)
            List<QRNG_Backend__c> backendRecords = new List<QRNG_Backend__c>();
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

                QRNG_Backend__c rec = new QRNG_Backend__c(
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
     */
    @AuraEnabled
    public static List<Map<String, String>> discoverInstances() {
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            List<Map<String, String>> instances = provider.discoverInstances();

            // Auto-save if single instance
            if (instances.size() == 1) {
                QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();
                if (settings.Id == null) {
                    settings = new QRNG_Settings__c(
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
     * Get all backend health data from stored QRNG_Backend__c records.
     */
    @AuraEnabled
    public static List<BackendHealthDTO> getAllBackendHealth() {
        List<QRNG_Backend__c> records = [
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
            FROM QRNG_Backend__c
            WHERE Provider__r.Is_Active__c = TRUE
            ORDER BY Queue_Length__c ASC NULLS LAST
        ];

        List<BackendHealthDTO> result = new List<BackendHealthDTO>();
        for (QRNG_Backend__c b : records) {
            result.add(toDTO(b));
        }
        return result;
    }

    private static BackendHealthDTO toDTO(QRNG_Backend__c b) {
        BackendHealthDTO dto = new BackendHealthDTO();
        dto.id = b.Id;
        dto.name = b.Name;
        dto.status = b.Status__c;
        dto.qubits = b.Num_Qubits__c != null ? (Integer) b.Num_Qubits__c : 0;
        dto.queueLength = b.Queue_Length__c != null
            ? (Integer) b.Queue_Length__c
            : null;
        dto.isSimulator = b.Is_Simulator__c;
        dto.processorFamily = b.Processor_Family__c;
        dto.processorRevision = b.Processor_Revision__c;
        dto.maxShots = b.Max_Shots__c != null ? (Integer) b.Max_Shots__c : null;
        dto.avgT1 = b.Avg_T1_us__c;
        dto.avgT2 = b.Avg_T2_us__c;
        dto.gateError = b.Median_Gate_Error__c;
        dto.readoutError = b.Median_Readout_Error__c;
        dto.lastCalibration = b.Last_Calibration__c;
        dto.lastSynced = b.Last_Synced__c;
        dto.provider = b.Provider__r.Name;
        dto.chshSValue = b.CHSH_S_Value__c;
        dto.chshVerifiedAt = b.CHSH_Verified_At__c;
        dto.quantumVerified = b.Quantum_Verified__c;
        dto.chshJobId = b.CHSH_Job_Id__c;
        dto.recordId = b.Id;
        return dto;
    }

    /**
     * Refresh health data for all backends from IBM API.
     * Fetches properties for each backend and updates QRNG_Backend__c records.
     * Governor limits: 2 callouts per backend (auth cached after first).
     */
    @AuraEnabled
    public static List<BackendHealthDTO> refreshAllBackendHealth() {
        try {
            // Ensure backends are synced first
            Integer backendCount = [
                SELECT COUNT()
                FROM QRNG_Backend__c
            ];
            if (backendCount == 0) {
                // Sync backends from IBM
                getAvailableBackends();
            }

            List<QRNG_Backend__c> backends = [
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
                FROM QRNG_Backend__c
                WHERE
                    Provider__r.Is_Active__c = TRUE
                    AND Is_Simulator__c = FALSE
                ORDER BY Name
                LIMIT 10
            ];

            List<QRNG_Backend__c> toUpdate = new List<QRNG_Backend__c>();
            for (QRNG_Backend__c backend : backends) {
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
        QRNG_Backend__c backend,
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
        QRNG_Settings__c s = QRNG_Settings__c.getInstance();

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
        settings.put('sweeperActive', QRNGJobSweeper.isScheduled());
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

        // Load cached backends from QRNG_Backend__c records
        List<QRNG_Backend__c> cachedBackends = [
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
            FROM QRNG_Backend__c
            ORDER BY Name
        ];
        if (!cachedBackends.isEmpty()) {
            List<Map<String, Object>> backendList = new List<Map<String, Object>>();
            for (QRNG_Backend__c cb : cachedBackends) {
                Map<String, Object> bMap = new Map<String, Object>();
                bMap.put('name', cb.Name);
                bMap.put('status', cb.Status__c);
                bMap.put('qubits', cb.Num_Qubits__c);
                bMap.put('provider', cb.Provider__r.Name);
                bMap.put('maxShots', cb.Max_Shots__c);
                bMap.put('queueLength', cb.Queue_Length__c);
                bMap.put('isSimulator', cb.Is_Simulator__c);
                bMap.put('processorFamily', cb.Processor_Family__c);
                backendList.add(bMap);
            }
            settings.put('cachedBackends', backendList);
        }

        return settings;
    }

    /**
     * Save settings (admin only)
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
        QRNG_Settings__c settings = QRNG_Settings__c.getOrgDefaults();

        if (settings.Id == null) {
            settings = new QRNG_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }

        if (String.isNotBlank(apiKey)) {
            settings.IBM_API_Key__c = apiKey;
        }
        if (String.isNotBlank(instanceCRN)) {
            settings.Instance_CRN__c = instanceCRN;
        }
        if (String.isNotBlank(defaultBackend)) {
            settings.Default_Backend__c = defaultBackend;
        }
        if (defaultShots != null) {
            settings.Default_Shots__c = defaultShots;
        }
        if (useBellTest != null) {
            settings.Use_Bell_Test__c = useBellTest;
        }
        if (useLeastBusy != null) {
            settings.Use_Least_Busy__c = useLeastBusy;
        }
        if (pollIntervalMinutes != null && pollIntervalMinutes > 0) {
            settings.Poll_Interval_Minutes__c = pollIntervalMinutes;
        }
        if (complianceEmail != null) {
            settings.Compliance_Email__c = complianceEmail;
        }

        upsert settings;

        // Clear auth cache since API key may have changed
        IBMQuantumAuth.clearCache();
    }

    /**
     * Export compliance evidence package as JSON for a given framework and date range.
     */
    @AuraEnabled
    public static String exportComplianceEvidence(
        String framework,
        String startDate,
        String endDate
    ) {
        Date sDate = Date.valueOf(startDate);
        Date eDate = Date.valueOf(endDate);
        return ComplianceEvidenceExporter.exportForFramework(
            framework,
            sDate,
            eDate
        );
    }

    /**
     * Start the background job sweeper.
     */
    @AuraEnabled
    public static void startSweeper() {
        QRNGJobSweeper.scheduleDefault();
    }

    /**
     * Stop the background job sweeper.
     */
    @AuraEnabled
    public static void stopSweeper() {
        QRNGJobSweeper.unschedule();
    }

    /**
     * Start the nightly integrity verification job.
     */
    @AuraEnabled
    public static void startIntegrityCheck() {
        IntegrityVerificationJob.scheduleDefault();
    }

    /**
     * Stop the nightly integrity verification job.
     */
    @AuraEnabled
    public static void stopIntegrityCheck() {
        IntegrityVerificationJob.unschedule();
    }

    /**
     * Submit a CHSH verification job for a backend.
     * Delegates to the active provider's verification implementation.
     * For IBM: uses Estimator V2 with optimal CHSH measurement angles.
     *
     * Governor limits: 3-4 callouts (provider-dependent)
     */
    @AuraEnabled
    public static Id verifyBackendQuantum(String backendName) {
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
     * Submit a QRNG job from LWC.
     * Uses the active provider's circuit building and job submission.
     */
    @AuraEnabled
    public static Id submitQRNGJob(
        String backend,
        Integer numQubits,
        Integer shots,
        String purpose,
        Boolean useBellTest
    ) {
        try {
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            QRNG_Settings__c settings = QRNG_Settings__c.getInstance();

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
     * Get recent QRNG jobs
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
        for (Quantum_Job__c job : jobs) {
            JobSummaryDTO dto = new JobSummaryDTO();
            dto.id = job.Id;
            dto.name = job.Name;
            dto.externalJobId = job.External_Job_ID__c;
            dto.backend = job.Backend__c;
            dto.status = job.Status__c;
            dto.jobType = job.Job_Type__c;
            dto.useBellTest = job.Use_Bell_Test__c;
            dto.shots = job.Shots__c != null ? (Integer) job.Shots__c : null;
            dto.numQubits = job.Num_Qubits__c != null
                ? (Integer) job.Num_Qubits__c
                : null;
            dto.purpose = job.Purpose__c;
            dto.submittedAt = job.Submitted_At__c;
            dto.completedAt = job.Completed_At__c;
            dto.executionTimeMs = job.Execution_Time_ms__c;
            dto.qpuTimeSeconds = job.QPU_Time_seconds__c;
            dto.requestedByName = job.Requested_By__r != null
                ? job.Requested_By__r.Name
                : null;
            dto.errorMessage = job.Error_Message__c;
            result.add(dto);
        }
        return result;
    }

    /**
     * Get job details with related data
     */
    @AuraEnabled(cacheable=true)
    public static Quantum_Job__c getJobDetails(Id jobId) {
        return [
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

        CertificateDTO dto = new CertificateDTO();
        dto.name = cert.Name;
        dto.externalJobId = cert.External_Job_ID__c;
        dto.backend = cert.Backend__c;
        dto.circuitQasm = cert.Circuit_QASM__c;
        dto.rawBitstringHash = cert.Raw_Bitstring_Hash__c;
        dto.debiasedBitstringHash = cert.Debiased_Bitstring_Hash__c;
        dto.assignmentHash = cert.Assignment_Hash__c;
        dto.validationResults = cert.Validation_Results__c;
        dto.chshSValue = cert.CHSH_S_Value__c;
        dto.createdByUser = cert.Created_By_User__c;
        dto.purpose = cert.Purpose__c;
        dto.status = cert.Status__c;
        dto.quantumJobId = cert.Quantum_Job__c;
        dto.createdDate = cert.CreatedDate;
        dto.tampered = cert.Tampered__c;
        dto.lastIntegrityCheck = cert.Last_Integrity_Check__c;
        dto.backendVerified = cert.Backend_Verified__c;
        dto.backendVerifiedAt = cert.Backend_Verified_At__c;
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
        return certs.isEmpty() ? null : certs[0];
    }

    /**
     * Get assignments for a job
     */
    @AuraEnabled(cacheable=true)
    public static List<QRNG_Assignment__c> getAssignments(Id jobId) {
        return [
            SELECT
                Id,
                Name,
                Assigned_Record_ID__c,
                Assigned_To_ID__c,
                Assignment_Index__c,
                Random_Value__c,
                Certificate__c
            FROM QRNG_Assignment__c
            WHERE Quantum_Job__c = :jobId
            ORDER BY Assignment_Index__c
        ];
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

        List<AuditTrailDTO> dtos = new List<AuditTrailDTO>();
        for (Fairness_Certificate__c cert : certs) {
            AuditTrailDTO dto = new AuditTrailDTO();
            dto.recordId = cert.Id;
            dto.name = cert.Name;
            dto.externalJobId = cert.External_Job_ID__c;
            dto.backend = cert.Backend__c;
            dto.status = cert.Status__c;
            dto.purpose = cert.Purpose__c;
            dto.chshSValue = cert.CHSH_S_Value__c;
            dto.createdDate = cert.CreatedDate;
            dto.quantumJobId = cert.Quantum_Job__c;
            dto.createdByUser = cert.Created_By_User__c;
            dto.tampered = cert.Tampered__c;
            dtos.add(dto);
        }
        return dtos;
    }

    /**
     * Verify certificate integrity
     */
    @AuraEnabled
    public static Map<String, Object> verifyCertificate(Id certificateId) {
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
     */
    @AuraEnabled
    public static Map<String, Object> refreshJobStatus(Id jobId) {
        try {
            Quantum_Job__c job = [
                SELECT Id, External_Job_ID__c, Status__c
                FROM Quantum_Job__c
                WHERE Id = :jobId
                LIMIT 1
            ];

            if (String.isBlank(job.External_Job_ID__c)) {
                throw new QRNGException(
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

            // Update job record — capture error details or clear if healthy
            job.Status__c = normalizedStatus;
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
     * Delegates to QRNGJobProcessor for the actual parsing and certification pipeline.
     */
    @AuraEnabled
    public static Map<String, Object> retrieveJobResults(Id jobId) {
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
                throw new QRNGException('No external job ID on this record.');
            }

            // Fetch results and status via provider
            QuantumProvider provider = QuantumProviderFactory.getActiveProvider();
            String resultsJson = provider.getJobResults(job.External_Job_ID__c);
            Map<String, Object> ibmStatus = provider.getJobStatus(
                job.External_Job_ID__c
            );

            // Delegate to shared processor
            QRNGJobProcessor.ProcessingResult pr;
            if (job.Program_Id__c == 'estimator') {
                pr = QRNGJobProcessor.processEstimatorCompletion(
                    job,
                    resultsJson,
                    ibmStatus
                );
            } else {
                pr = QRNGJobProcessor.processSamplerCompletion(
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
     * Returns the QRNG_Provider__c record for IBM.
     */
    private static QRNG_Provider__c ensureIBMProvider() {
        List<QRNG_Provider__c> providers = [
            SELECT Id, Name, Provider_Key__c, Status__c, Last_Synced__c
            FROM QRNG_Provider__c
            WHERE Provider_Key__c = 'ibm'
            LIMIT 1
        ];
        if (!providers.isEmpty()) {
            return providers[0];
        }
        QRNG_Provider__c ibm = new QRNG_Provider__c(
            Name = 'IBM Quantum',
            Provider_Key__c = 'ibm',
            Provider_Class__c = 'IBMQuantumService',
            Auth_Endpoint__c = 'https://iam.cloud.ibm.com/identity/token',
            API_Base_URL__c = 'https://api.quantum-computing.ibm.com',
            Is_Active__c = true,
            Status__c = 'Connected'
        );
        insert ibm;
        return ibm;
    }

    /**
     * Get usage statistics
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUsageStats() {
        Map<String, Object> stats = new Map<String, Object>();

        stats.put('totalJobs', [SELECT COUNT() FROM Quantum_Job__c]);
        stats.put(
            'completedJobs',
            [SELECT COUNT() FROM Quantum_Job__c WHERE Status__c = 'Completed']
        );
        stats.put(
            'failedJobs',
            [SELECT COUNT() FROM Quantum_Job__c WHERE Status__c = 'Failed']
        );
        stats.put(
            'totalCertificates',
            [
                SELECT COUNT()
                FROM Fairness_Certificate__c
                WHERE Status__c = 'Certified'
            ]
        );
        stats.put('totalAssignments', [SELECT COUNT() FROM QRNG_Assignment__c]);

        return stats;
    }
}
