/**
 * LWC controller for admin setup and general QRNG operations.
 * Handles connection testing, backend listing, settings management, and job submission.
 */
public with sharing class QRNGSetupController {
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
    public static List<Map<String, Object>> getAllBackendHealth() {
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
                Provider__r.Name
            FROM QRNG_Backend__c
            WHERE Provider__r.Is_Active__c = TRUE
            ORDER BY Queue_Length__c ASC NULLS LAST
        ];

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (QRNG_Backend__c b : records) {
            Map<String, Object> m = new Map<String, Object>();
            m.put('id', b.Id);
            m.put('name', b.Name);
            m.put('status', b.Status__c);
            m.put('qubits', b.Num_Qubits__c);
            m.put('queueLength', b.Queue_Length__c);
            m.put('isSimulator', b.Is_Simulator__c);
            m.put('processorFamily', b.Processor_Family__c);
            m.put('processorRevision', b.Processor_Revision__c);
            m.put('maxShots', b.Max_Shots__c);
            m.put('avgT1', b.Avg_T1_us__c);
            m.put('avgT2', b.Avg_T2_us__c);
            m.put('gateError', b.Median_Gate_Error__c);
            m.put('readoutError', b.Median_Readout_Error__c);
            m.put('lastCalibration', b.Last_Calibration__c);
            m.put('lastSynced', b.Last_Synced__c);
            m.put('provider', b.Provider__r.Name);
            result.add(m);
        }
        return result;
    }

    /**
     * Refresh health data for all backends from IBM API.
     * Fetches properties for each backend and updates QRNG_Backend__c records.
     * Governor limits: 2 callouts per backend (auth cached after first).
     */
    @AuraEnabled
    public static List<Map<String, Object>> refreshAllBackendHealth() {
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

            String qasm;
            if (bell) {
                qasm = QRNGCircuitBuilder.buildBellTestCircuit(numQ / 2);
            } else {
                qasm = QRNGCircuitBuilder.buildStandardCircuit(numQ);
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
     * Get certificate for a job
     */
    @AuraEnabled(cacheable=true)
    public static Fairness_Certificate__c getCertificate(Id certificateId) {
        return [
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
            WHERE Id = :certificateId
            LIMIT 1
        ];
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
     * Get audit trail - all certificates with job info
     */
    @AuraEnabled(cacheable=true)
    public static List<Fairness_Certificate__c> getAuditTrail() {
        return [
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
                Created_By_User__c
            FROM Fairness_Certificate__c
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
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

            // Update job record — clear error if status is healthy
            job.Status__c = normalizedStatus;
            if (normalizedStatus != 'Failed') {
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
                    Raw_Results__c
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

            // Parse results
            List<String> bitstrings = QRNGResultParser.parseSamplerResults(
                resultsJson
            );
            String rawBits = QRNGResultParser.concatenateBitstrings(bitstrings);
            String debiasedBits = QRNGResultParser.vonNeumannDebias(rawBits);

            // Update job
            job.Status__c = 'Completed';
            job.Completed_At__c = DateTime.now();
            job.Raw_Results__c = rawBits.left(131072);
            job.Debiased_Results__c = debiasedBits.left(131072);
            if (job.Submitted_At__c != null) {
                job.Execution_Time_ms__c =
                    DateTime.now().getTime() - job.Submitted_At__c.getTime();
            }
            update job;

            // Validate and create certificate
            Map<String, Object> validation = QRNGValidator.validate(
                debiasedBits
            );
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
