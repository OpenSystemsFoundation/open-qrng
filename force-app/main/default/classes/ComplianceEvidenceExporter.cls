/**
 * Assembles structured evidence packages for compliance audits.
 * Framework-agnostic: same evidence, mapped to any framework at query time.
 *
 * Governor budget: ~8 SOQL, 0 DML, 0 callouts
 */
public with sharing class ComplianceEvidenceExporter {
    /**
     * Generate a full evidence package for a specific framework and date range.
     * Returns a JSON string suitable for download.
     */
    public static String exportForFramework(
        String framework,
        Date startDate,
        Date endDate
    ) {
        DateTime startDT = DateTime.newInstance(
            startDate,
            Time.newInstance(0, 0, 0, 0)
        );
        DateTime endDT = DateTime.newInstance(
            endDate.addDays(1),
            Time.newInstance(0, 0, 0, 0)
        );

        // 1. Export metadata
        Map<String, Object> exportMeta = new Map<String, Object>{
            'generatedAt' => DateTime.now().format(),
            'generatedBy' => UserInfo.getUserEmail(),
            'framework' => framework,
            'dateRange' => new Map<String, String>{
                'start' => String.valueOf(startDate),
                'end' => String.valueOf(endDate)
            },
            'orgId' => UserInfo.getOrganizationId()
        };

        // 2. Control mappings
        List<Compliance_Control__mdt> controls;
        if (framework == 'ALL') {
            controls = ComplianceControlService.getFullMatrix();
        } else {
            controls = ComplianceControlService.getControlsForFramework(
                framework
            );
        }
        List<Map<String, String>> controlMappings = new List<Map<String, String>>();
        for (Compliance_Control__mdt ctrl : controls) {
            controlMappings.add(
                new Map<String, String>{
                    'controlKey' => ctrl.Control_Key__c,
                    'framework' => ctrl.Framework__c,
                    'frameworkReference' => ctrl.Framework_Reference__c,
                    'description' => ctrl.Control_Description__c,
                    'evidenceType' => ctrl.Evidence_Type__c
                }
            );
        }

        // 3. Certificate summaries
        List<Fairness_Certificate__c> certs = [
            SELECT
                Id,
                Name,
                Status__c,
                Chain_Hash__c,
                Chain_Position__c,
                Tampered__c,
                Last_Integrity_Check__c,
                CHSH_S_Value__c,
                Backend__c,
                Backend_Verified__c,
                CreatedDate,
                Verified_By__c,
                Verified_At__c
            FROM Fairness_Certificate__c
            WHERE CreatedDate >= :startDT AND CreatedDate < :endDT
            ORDER BY Chain_Position__c ASC
        ];

        Integer totalCerts = certs.size();
        Integer tamperedCount = 0;
        Integer certifiedCount = 0;
        List<Map<String, Object>> certSummaries = new List<Map<String, Object>>();
        for (Fairness_Certificate__c cert : certs) {
            if (cert.Tampered__c)
                tamperedCount++;
            if (cert.Status__c == 'Certified')
                certifiedCount++;
            certSummaries.add(
                new Map<String, Object>{
                    'id' => cert.Name,
                    'status' => cert.Status__c,
                    'chainHash' => cert.Chain_Hash__c,
                    'chainPosition' => cert.Chain_Position__c,
                    'tampered' => cert.Tampered__c,
                    'lastIntegrityCheck' => cert.Last_Integrity_Check__c != null
                        ? cert.Last_Integrity_Check__c.format()
                        : null,
                    'chshSValue' => cert.CHSH_S_Value__c,
                    'backend' => cert.Backend__c,
                    'backendVerified' => cert.Backend_Verified__c,
                    'createdDate' => cert.CreatedDate.format(),
                    'verifiedAt' => cert.Verified_At__c != null
                        ? cert.Verified_At__c.format()
                        : null
                }
            );
        }

        // 4. Chain integrity
        Map<String, Object> chainIntegrity = new Map<String, Object>{
            'totalCertificates' => totalCerts,
            'certifiedCount' => certifiedCount,
            'tamperedCount' => tamperedCount,
            'chainIntact' => tamperedCount == 0
        };

        // 5. Compliance events in range
        List<Compliance_Event__c> events = [
            SELECT
                Id,
                Name,
                Event_Type__c,
                Severity__c,
                Detail__c,
                Detail_Hash__c,
                CreatedDate
            FROM Compliance_Event__c
            WHERE CreatedDate >= :startDT AND CreatedDate < :endDT
            ORDER BY CreatedDate ASC
        ];
        List<Map<String, Object>> eventList = new List<Map<String, Object>>();
        for (Compliance_Event__c evt : events) {
            eventList.add(
                new Map<String, Object>{
                    'eventId' => evt.Name,
                    'eventType' => evt.Event_Type__c,
                    'severity' => evt.Severity__c,
                    'detail' => evt.Detail__c,
                    'detailHash' => evt.Detail_Hash__c,
                    'createdDate' => evt.CreatedDate.format()
                }
            );
        }

        // 6. Entropy source profiles
        List<Quantum_Backend__c> backends = [
            SELECT
                Name,
                Noise_Source_Type__c,
                Conditioning_Component__c,
                Health_Test_Parameters__c,
                Last_Health_Test_At__c,
                Health_Test_Passed__c,
                CHSH_S_Value__c,
                CHSH_Verified_At__c,
                Quantum_Verified__c
            FROM Quantum_Backend__c
            WHERE Quantum_Verified__c = TRUE
            ORDER BY Name
        ];
        List<Map<String, Object>> entropyProfiles = new List<Map<String, Object>>();
        for (Quantum_Backend__c be : backends) {
            entropyProfiles.add(
                new Map<String, Object>{
                    'backend' => be.Name,
                    'noiseSourceType' => be.Noise_Source_Type__c,
                    'conditioningComponent' => be.Conditioning_Component__c,
                    'healthTestParameters' => be.Health_Test_Parameters__c,
                    'lastHealthTestAt' => be.Last_Health_Test_At__c != null
                        ? be.Last_Health_Test_At__c.format()
                        : null,
                    'healthTestPassed' => be.Health_Test_Passed__c,
                    'chshSValue' => be.CHSH_S_Value__c,
                    'quantumVerified' => be.Quantum_Verified__c
                }
            );
        }

        // Assemble the package
        Map<String, Object> evidencePackage = new Map<String, Object>{
            'exportMetadata' => exportMeta,
            'controlMappings' => controlMappings,
            'chainIntegrity' => chainIntegrity,
            'certificates' => certSummaries,
            'complianceEvents' => eventList,
            'entropySourceProfiles' => entropyProfiles
        };

        // Log the export as a compliance event
        ComplianceEventLogger.log(
            'EVIDENCE_EXPORTED',
            'INFO',
            null,
            null,
            new Map<String, Object>{
                'framework' => framework,
                'startDate' => String.valueOf(startDate),
                'endDate' => String.valueOf(endDate),
                'certificateCount' => totalCerts,
                'eventCount' => events.size()
            }
        );

        return JSON.serializePretty(evidencePackage);
    }

    /**
     * Generate evidence for a single certificate.
     */
    public static String exportCertificateEvidence(Id certificateId) {
        Fairness_Certificate__c cert = [
            SELECT
                Id,
                Name,
                Status__c,
                Quantum_Job__c,
                External_Job_ID__c,
                Backend__c,
                Circuit_QASM__c,
                Raw_Bitstring_Hash__c,
                Debiased_Bitstring_Hash__c,
                Assignment_Hash__c,
                Chain_Hash__c,
                Chain_Position__c,
                Previous_Certificate_Hash__c,
                Tampered__c,
                Last_Integrity_Check__c,
                Validation_Results__c,
                CHSH_S_Value__c,
                Backend_Verified__c,
                Backend_Verified_At__c,
                Created_By_User__c,
                Purpose__c,
                CreatedDate,
                Verified_By__c,
                Verified_At__c
            FROM Fairness_Certificate__c
            WHERE Id = :certificateId
            LIMIT 1
        ];

        // Get all framework mappings for context
        List<Compliance_Control__mdt> allControls = ComplianceControlService.getFullMatrix();

        Map<String, Object> evidence = new Map<String, Object>{
            'exportMetadata' => new Map<String, Object>{
                'generatedAt' => DateTime.now().format(),
                'generatedBy' => UserInfo.getUserEmail(),
                'type' => 'SINGLE_CERTIFICATE'
            },
            'certificate' => new Map<String, Object>{
                'id' => cert.Name,
                'status' => cert.Status__c,
                'externalJobId' => cert.External_Job_ID__c,
                'backend' => cert.Backend__c,
                'rawBitstringHash' => cert.Raw_Bitstring_Hash__c,
                'debiasedBitstringHash' => cert.Debiased_Bitstring_Hash__c,
                'assignmentHash' => cert.Assignment_Hash__c,
                'chainHash' => cert.Chain_Hash__c,
                'chainPosition' => cert.Chain_Position__c,
                'previousCertificateHash' => cert.Previous_Certificate_Hash__c,
                'tampered' => cert.Tampered__c,
                'lastIntegrityCheck' => cert.Last_Integrity_Check__c != null
                    ? cert.Last_Integrity_Check__c.format()
                    : null,
                'validationResults' => cert.Validation_Results__c,
                'chshSValue' => cert.CHSH_S_Value__c,
                'backendVerified' => cert.Backend_Verified__c,
                'backendVerifiedAt' => cert.Backend_Verified_At__c != null
                    ? cert.Backend_Verified_At__c.format()
                    : null,
                'purpose' => cert.Purpose__c,
                'createdDate' => cert.CreatedDate.format(),
                'verifiedAt' => cert.Verified_At__c != null
                    ? cert.Verified_At__c.format()
                    : null
            }
        };

        return JSON.serializePretty(evidence);
    }
}
