/**
 * LWC controller for admin setup and general QRNG operations.
 * Handles connection testing, backend listing, settings management, and job submission.
 */
public with sharing class QRNGSetupController {
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

        // Run critical tests
        Map<String, Object> results = QRNGValidator.validate(
            job.Debiased_Results__c
        );

        // Run extended tests
        Map<String, Object> extendedResults = QRNGValidator.validateExtended(
            job.Debiased_Results__c
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
            // Raw results is concatenated — split into shot-sized chunks
            String raw = job.Raw_Results__c;
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
            SELECT Id, Validation_Results__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];

        if (String.isNotBlank(job.Validation_Results__c)) {
            return (Map<String, Object>) JSON.deserializeUntyped(
                job.Validation_Results__c
            );
        }
        return new Map<String, Object>();
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
        dto.jobType = job.Job_Type__c;
        return dto;
    }

    /**
     * Test the IBM Quantum connection
     */
    @AuraEnabled
    public static Map<String, Object> testConnection() {
        Map<String, Object> result = new Map<String, Object>();
        try {
            Boolean connected = IBMQuantumAuth.testApiKey();
            result.put('connected', connected);
            result.put(
                'message',
                connected
                    ? 'Connected to IBM Quantum'
                    : 'Connection failed - check API key'
            );
        } catch (Exception e) {
            result.put('connected', false);
            result.put('message', 'Error: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Get available IBM Quantum backends
     */
    @AuraEnabled
    public static List<Map<String, Object>> getAvailableBackends() {
        try {
            String backendsJson = IBMQuantumService.getBackends();
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
                backendsJson
            );

            List<Map<String, Object>> backends = new List<Map<String, Object>>();

            // Parse response - structure may be {"devices": [...]} or direct array
            List<Object> devices;
            if (response.containsKey('devices')) {
                devices = (List<Object>) response.get('devices');
            } else if (response.containsKey('backends')) {
                devices = (List<Object>) response.get('backends');
            } else {
                devices = new List<Object>();
            }

            for (Object device : devices) {
                Map<String, Object> deviceMap = (Map<String, Object>) device;
                Map<String, Object> backend = new Map<String, Object>();
                backend.put('name', deviceMap.get('name'));
                backend.put(
                    'status',
                    deviceMap.containsKey('status')
                        ? deviceMap.get('status')
                        : 'unknown'
                );
                backend.put(
                    'qubits',
                    deviceMap.containsKey('qubits')
                        ? deviceMap.get('qubits')
                        : (deviceMap.containsKey('num_qubits')
                              ? deviceMap.get('num_qubits')
                              : 0)
                );
                // Queue length
                if (deviceMap.containsKey('pending_jobs')) {
                    backend.put('queueLength', deviceMap.get('pending_jobs'));
                } else if (deviceMap.containsKey('queue_length')) {
                    backend.put('queueLength', deviceMap.get('queue_length'));
                }
                // Simulator flag
                if (deviceMap.containsKey('is_simulator')) {
                    backend.put('isSimulator', deviceMap.get('is_simulator'));
                }
                // Processor info
                if (deviceMap.containsKey('processor_type')) {
                    Map<String, Object> proc = (Map<String, Object>) deviceMap.get(
                        'processor_type'
                    );
                    if (proc != null) {
                        backend.put('processorFamily', proc.get('family'));
                        backend.put('processorRevision', proc.get('revision'));
                    }
                }
                backends.add(backend);
            }

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
     * Discover IBM Quantum instances and their CRNs.
     * Auto-saves CRN if only one instance found.
     */
    @AuraEnabled
    public static List<Map<String, String>> discoverInstances() {
        try {
            List<Map<String, String>> instances = IBMQuantumAuth.discoverInstances();

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
            Map<String, Object> props = IBMQuantumService.getBackendProperties(
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
                    Map<String, Object> props = IBMQuantumService.getBackendProperties(
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
        } else {
            settings.put('hasApiKey', false);
            settings.put('hasCRN', false);
            settings.put('defaultBackend', '');
            settings.put('defaultShots', 1024);
            settings.put('useBellTest', false);
            settings.put('useLeastBusy', false);
            settings.put('pollIntervalMinutes', 5);
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
        Integer pollIntervalMinutes
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

        upsert settings;

        // Clear auth cache since API key may have changed
        IBMQuantumAuth.clearCache();
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
     * Submit a CHSH verification job for a backend using Estimator V2.
     * Builds 4 Bell state circuits with optimal measurement basis rotations
     * (Ry(-2θ) trick) and submits each with a ZZ observable. The Estimator
     * returns E(a,b) for each setting directly. Uses resilience_level=0
     * (no mitigation) so the raw result is an honest proof of quantumness.
     *
     * Governor limits: 3-4 callouts (readout errors, gate errors, coupling map, submit)
     */
    @AuraEnabled
    public static Id verifyBackendQuantum(String backendName) {
        try {
            // Fetch calibration data for best pair selection
            List<List<Integer>> couplingMap = IBMQuantumService.getCouplingMap(
                backendName
            );
            Map<Integer, Double> readoutErrors;
            try {
                readoutErrors = IBMQuantumService.getReadoutErrors(backendName);
            } catch (Exception ex) {
                readoutErrors = null;
            }
            Map<String, Double> gateErrors;
            try {
                gateErrors = IBMQuantumService.getGateErrors(backendName);
            } catch (Exception ex) {
                gateErrors = null;
            }

            // Select the single best qubit pair
            QRNGCircuitBuilder.CoupledPair bestPair = QRNGCircuitBuilder.selectBestPair(
                couplingMap,
                readoutErrors,
                gateErrors
            );

            // Build 4 circuits with optimal CHSH measurement angles
            List<String> circuits = QRNGCircuitBuilder.buildCHSHVerificationCircuits(
                bestPair.q0,
                bestPair.q1
            );

            // Observable: ZZ on the active qubit pair
            Integer numCircuitQubits = Math.max(bestPair.q0, bestPair.q1) + 1;
            String zzObservable = buildPauliString(
                numCircuitQubits,
                bestPair.q0,
                bestPair.q1,
                'Z',
                'Z'
            );

            return IBMQuantumService.submitCHSHEstimatorJob(
                circuits,
                zzObservable,
                backendName,
                4096,
                'CHSH backend verification'
            );
        } catch (Exception e) {
            throw new AuraHandledException(
                'Backend verification failed: ' + e.getMessage()
            );
        }
    }

    /**
     * Build an N-qubit Pauli string with operators on two specific qubits.
     * Pauli strings use reverse qubit order (rightmost = qubit 0).
     * All other positions are filled with 'I' (identity).
     */
    @TestVisible
    private static String buildPauliString(
        Integer numQubits,
        Integer qubitA,
        Integer qubitB,
        String opA,
        String opB
    ) {
        List<String> chars = new List<String>();
        for (Integer i = 0; i < numQubits; i++) {
            chars.add('I');
        }
        chars.set(qubitA, opA);
        chars.set(qubitB, opB);
        // Reverse so rightmost = qubit 0 (Pauli string convention)
        List<String> reversed = new List<String>();
        for (Integer i = numQubits - 1; i >= 0; i--) {
            reversed.add(chars.get(i));
        }
        return String.join(reversed, '');
    }

    /**
     * Submit a QRNG job from LWC
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
            QRNG_Settings__c settings = QRNG_Settings__c.getInstance();
            String backendName;
            if (String.isNotBlank(backend)) {
                backendName = backend;
            } else if (settings != null && settings.Use_Least_Busy__c == true) {
                // Always call live API for real-time queue data
                backendName = IBMQuantumService.getLeastBusyBackend();
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

            // Fetch backend topology and calibration for qubit selection
            Map<Integer, Double> readoutErrors;
            try {
                readoutErrors = IBMQuantumService.getReadoutErrors(backendName);
            } catch (Exception ex) {
                readoutErrors = null;
            }

            String qasm;
            if (bell) {
                List<List<Integer>> couplingMap = IBMQuantumService.getCouplingMap(
                    backendName
                );
                qasm = QRNGCircuitBuilder.buildBellTestCircuit(
                    numQ / 2,
                    couplingMap,
                    readoutErrors
                );
            } else {
                qasm = QRNGCircuitBuilder.buildStandardCircuit(
                    numQ,
                    readoutErrors
                );
            }

            return IBMQuantumService.submitJob(
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
    public static List<Quantum_Job__c> getRecentJobs() {
        return [
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
                Submitted_At__c,
                Completed_At__c,
                Requested_By__c,
                Error_Message__c
            FROM Quantum_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
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

            Map<String, Object> ibmStatus = IBMQuantumService.getJobStatus(
                job.External_Job_ID__c
            );

            // Extract status from response (handles nested state.status or top-level status)
            String status;
            if (ibmStatus.containsKey('state')) {
                Map<String, Object> state = (Map<String, Object>) ibmStatus.get(
                    'state'
                );
                status = (String) state.get('status');
            } else {
                status = (String) ibmStatus.get('status');
            }

            // Normalize status
            String normalizedStatus = normalizeIBMStatus(status);

            // Update job record — capture error details or clear if healthy
            job.Status__c = normalizedStatus;
            if (normalizedStatus == 'Failed') {
                job.Error_Message__c = buildVerboseError(status, ibmStatus);
            } else {
                job.Error_Message__c = null;
            }

            update job;

            Map<String, Object> result = new Map<String, Object>();
            result.put('status', normalizedStatus);
            result.put('ibmStatus', status);
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
     * Re-runs the result parsing and certificate creation pipeline.
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

            // Fetch results from IBM
            String resultsJson = IBMQuantumService.getJobResults(
                job.External_Job_ID__c
            );

            // Route based on program type
            if (job.Program_Id__c == 'estimator') {
                return retrieveEstimatorResults(job, resultsJson);
            }
            return retrieveSamplerResults(job, resultsJson);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to retrieve results: ' + e.getMessage()
            );
        }
    }

    private static Map<String, Object> retrieveEstimatorResults(
        Quantum_Job__c job,
        String resultsJson
    ) {
        // Parse individual expectation values (one per PUB/observable)
        List<Double> evs = QRNGResultParser.parseAllEstimatorResults(
            resultsJson
        );
        List<Double> stds = QRNGResultParser.parseAllEstimatorStds(
            resultsJson
        );

        // Retrieve observable labels stored at submission time
        List<String> labels = new List<String>();
        Map<String, Double> coeffs = new Map<String, Double>();
        if (String.isNotBlank(job.Validation_Results__c)) {
            Map<String, Object> meta = (Map<String, Object>) JSON.deserializeUntyped(
                job.Validation_Results__c
            );
            if (meta.containsKey('observableLabels')) {
                for (
                    Object lbl : (List<Object>) meta.get('observableLabels')
                ) {
                    labels.add((String) lbl);
                }
            }
            if (meta.containsKey('observableCoeffs')) {
                Map<String, Object> rawCoeffs = (Map<String, Object>) meta.get(
                    'observableCoeffs'
                );
                for (String k : rawCoeffs.keySet()) {
                    coeffs.put(
                        k,
                        Double.valueOf(String.valueOf(rawCoeffs.get(k)))
                    );
                }
            }
        }

        // Fallback for old jobs without observable metadata
        if (labels.isEmpty() && !evs.isEmpty()) {
            Double fallbackS = Math.abs(evs[0]);
            Map<String, Object> vr = new Map<String, Object>();
            vr.put('chshSValue', fallbackS);
            vr.put('bellTestPassed', fallbackS > 2.0);
            vr.put('passed', fallbackS > 2.0);
            vr.put('programId', 'estimator');
            job.Raw_Results__c = 'S-Value (legacy single-PUB): ' + fallbackS;
            job.Validation_Results__c = JSON.serialize(vr);
            job.Status__c = 'Completed';
            job.Completed_At__c = DateTime.now();
            if (job.Submitted_At__c != null) {
                job.Execution_Time_ms__c =
                    DateTime.now().getTime() -
                    job.Submitted_At__c.getTime();
            }
            update job;

            List<QRNG_Backend__c> bkFb = [
                SELECT Id
                FROM QRNG_Backend__c
                WHERE Name = :job.Backend__c
                LIMIT 1
            ];
            if (!bkFb.isEmpty()) {
                bkFb[0].CHSH_S_Value__c = fallbackS;
                bkFb[0].CHSH_Verified_At__c = DateTime.now();
                bkFb[0].CHSH_Job_Id__c = job.Id;
                update bkFb[0];
            }

            Map<String, Object> fbResult = new Map<String, Object>();
            fbResult.put('status', 'Completed');
            fbResult.put('chshSValue', fallbackS);
            fbResult.put('bellTestPassed', fallbackS > 2.0);
            return fbResult;
        }

        // Compute S = Σ(coefficient × expectation value) per term
        Double sValue = 0;
        Map<String, Object> termBreakdown = new Map<String, Object>();
        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String label = labels[i];
            Double ev = evs[i];
            Double coeff = coeffs.containsKey(label)
                ? coeffs.get(label)
                : 1.0;
            sValue += coeff * ev;

            String shortLabel = label.replaceAll('I', '');
            Map<String, Object> term = new Map<String, Object>();
            term.put('expectationValue', ev);
            term.put('coefficient', coeff);
            term.put('contribution', coeff * ev);
            if (i < stds.size() && stds[i] != null) {
                term.put('std', stds[i]);
            }
            termBreakdown.put(shortLabel, term);
        }
        Double sValueAbs = Math.abs(sValue);

        // Build validation results with full breakdown
        Map<String, Object> validationResults = new Map<String, Object>();
        validationResults.put('chshSValue', sValueAbs);
        validationResults.put('bellTestPassed', sValueAbs > 2.0);
        validationResults.put('passed', sValueAbs > 2.0);
        validationResults.put('programId', 'estimator');
        validationResults.put('termBreakdown', termBreakdown);

        // Build human-readable summary
        String summary = '=== CHSH Bell Test Results ===\n\n';
        summary += 'S-Value:           ' + sValueAbs + '\n';
        summary += 'Classical Bound:   2.0\n';
        summary += 'Quantum Maximum:   2.828 (2\u221A2)\n';
        summary +=
            'Result:            ' +
            (sValueAbs > 2.0
                ? 'PASS - Quantum behavior confirmed'
                : 'FAIL - Below classical bound') +
            '\n';

        summary += '\n=== Per-Observable Breakdown ===\n';
        summary += 'S = ';
        List<String> formulaParts = new List<String>();
        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String shortLabel = labels[i].replaceAll('I', '');
            Double coeff = coeffs.containsKey(labels[i])
                ? coeffs.get(labels[i])
                : 1.0;
            String sign = coeff >= 0 ? '+' : '-';
            if (i == 0 && coeff >= 0) {
                sign = '';
            }
            formulaParts.add(sign + '<' + shortLabel + '>');
        }
        summary += String.join(formulaParts, ' ') + '\n\n';

        for (Integer i = 0; i < evs.size() && i < labels.size(); i++) {
            String shortLabel = labels[i].replaceAll('I', '');
            Double coeff = coeffs.containsKey(labels[i])
                ? coeffs.get(labels[i])
                : 1.0;
            String coeffStr = coeff == 1.0
                ? '+1'
                : (coeff == -1.0 ? '-1' : String.valueOf(coeff));
            summary += '<' + shortLabel + '> = ' + evs[i];
            if (i < stds.size() && stds[i] != null) {
                summary += '  (std: ' + stds[i] + ')';
            }
            summary +=
                '  [coeff: ' +
                coeffStr +
                ', contribution: ' +
                (coeff * evs[i]) +
                ']\n';
        }
        summary += '\nS = ' + sValueAbs + '\n';

        job.Raw_Results__c = summary;

        String validationJson = JSON.serialize(validationResults);

        // Update job
        job.Status__c = 'Completed';
        job.Completed_At__c = DateTime.now();
        job.Validation_Results__c = validationJson;
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c =
                DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
        update job;

        // Update backend verification
        List<QRNG_Backend__c> backends = [
            SELECT Id
            FROM QRNG_Backend__c
            WHERE Name = :job.Backend__c
            LIMIT 1
        ];
        if (!backends.isEmpty()) {
            backends[0].CHSH_S_Value__c = sValueAbs;
            backends[0].CHSH_Verified_At__c = DateTime.now();
            backends[0].CHSH_Job_Id__c = job.Id;
            update backends[0];
        }

        Map<String, Object> result = new Map<String, Object>();
        result.put('status', 'Completed');
        result.put('chshSValue', sValueAbs);
        result.put('bellTestPassed', sValueAbs > 2.0);
        return result;
    }

    private static Map<String, Object> retrieveSamplerResults(
        Quantum_Job__c job,
        String resultsJson
    ) {
        Integer numQubits = job.Num_Qubits__c != null
            ? (Integer) job.Num_Qubits__c
            : 8;
        List<String> bitstrings = QRNGResultParser.parseSamplerResults(
            resultsJson,
            numQubits
        );
        String rawBits = QRNGResultParser.concatenateBitstrings(bitstrings);
        String debiasedBits = QRNGResultParser.vonNeumannDebias(rawBits);

        // Get queue time from IBM status
        Map<String, Object> ibmStatus = IBMQuantumService.getJobStatus(
            job.External_Job_ID__c
        );

        // Update job
        job.Status__c = 'Completed';
        job.Completed_At__c = DateTime.now();
        job.Raw_Results__c = rawBits.left(131072);
        job.Debiased_Results__c = debiasedBits.left(131072);
        if (job.Submitted_At__c != null) {
            job.Execution_Time_ms__c =
                DateTime.now().getTime() - job.Submitted_At__c.getTime();
        }
        job.Queue_Time_ms__c = extractQueueTimeMs(ibmStatus);
        update job;

        // Validate and create certificate
        Map<String, Object> validation = QRNGValidator.validate(debiasedBits);
        String validationJson = JSON.serialize(validation);
        Boolean passed = validation.containsKey('passed')
            ? (Boolean) validation.get('passed')
            : true;
        String certStatus = passed ? 'Certified' : 'Failed';
        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            validationJson,
            certStatus
        );

        Map<String, Object> result = new Map<String, Object>();
        result.put('status', 'Completed');
        result.put('certificateId', certId);
        result.put('rawBitsLength', rawBits.length());
        result.put('debiasedBitsLength', debiasedBits.length());
        return result;
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

    private static String buildVerboseError(
        String status,
        Map<String, Object> statusResponse
    ) {
        String msg = 'IBM job status: ' + status;
        if (statusResponse == null) {
            return msg;
        }
        if (statusResponse.containsKey('error')) {
            Object errObj = statusResponse.get('error');
            if (errObj instanceof Map<String, Object>) {
                Map<String, Object> error = (Map<String, Object>) errObj;
                if (error.containsKey('code')) {
                    msg += '\nError code: ' + error.get('code');
                }
                if (error.containsKey('message')) {
                    msg += '\nError message: ' + (String) error.get('message');
                }
                if (error.containsKey('solution')) {
                    msg += '\nSolution: ' + (String) error.get('solution');
                }
                if (error.containsKey('more_info')) {
                    msg += '\nMore info: ' + (String) error.get('more_info');
                }
            } else {
                msg += '\nError: ' + String.valueOf(errObj);
            }
        }
        if (statusResponse.containsKey('state')) {
            Object stateObj = statusResponse.get('state');
            if (stateObj instanceof Map<String, Object>) {
                Map<String, Object> state = (Map<String, Object>) stateObj;
                if (state.containsKey('reason')) {
                    msg += '\nReason: ' + (String) state.get('reason');
                }
                if (state.containsKey('reason_code')) {
                    msg += '\nReason code: ' + state.get('reason_code');
                }
            }
        }
        return msg;
    }

    private static Decimal extractQueueTimeMs(
        Map<String, Object> statusResponse
    ) {
        if (
            statusResponse == null || !statusResponse.containsKey('timestamps')
        ) {
            return null;
        }
        Object tsObj = statusResponse.get('timestamps');
        if (!(tsObj instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> timestamps = (Map<String, Object>) tsObj;
        String created = (String) timestamps.get('created');
        String running = (String) timestamps.get('running');
        if (String.isBlank(created) || String.isBlank(running)) {
            return null;
        }
        try {
            DateTime createdDt = DateTime.valueOf(
                created.replace('T', ' ').replace('Z', '')
            );
            DateTime runningDt = DateTime.valueOf(
                running.replace('T', ' ').replace('Z', '')
            );
            return runningDt.getTime() - createdDt.getTime();
        } catch (Exception e) {
            return null;
        }
    }

    private static String normalizeIBMStatus(String ibmStatus) {
        if (ibmStatus == null)
            return 'Pending';
        String lower = ibmStatus.toLowerCase();
        if (lower == 'completed' || lower == 'result_ready')
            return 'Completed';
        if (lower == 'running')
            return 'Running';
        if (lower == 'queued' || lower == 'pending_in_queue')
            return 'Queued';
        if (lower == 'failed' || lower == 'cancelled' || lower == 'canceled')
            return 'Failed';
        return 'Submitted';
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
