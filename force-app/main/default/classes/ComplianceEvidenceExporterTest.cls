@IsTest
private class ComplianceEvidenceExporterTest {
    @TestSetup
    static void setup() {
        QRNG_Settings__c settings = new QRNG_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );
        insert settings;
    }

    @IsTest
    static void testExportForFrameworkWithNoCertificates() {
        Test.startTest();
        String result = ComplianceEvidenceExporter.exportForFramework(
            'ISO_27001',
            Date.today().addDays(-30),
            Date.today()
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Export should return non-null JSON'
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            result
        );
        System.assert(
            parsed.containsKey('exportMetadata'),
            'Should contain exportMetadata'
        );
        System.assert(
            parsed.containsKey('controlMappings'),
            'Should contain controlMappings'
        );
        System.assert(
            parsed.containsKey('chainIntegrity'),
            'Should contain chainIntegrity'
        );
        System.assert(
            parsed.containsKey('certificates'),
            'Should contain certificates'
        );
        System.assert(
            parsed.containsKey('complianceEvents'),
            'Should contain complianceEvents'
        );

        Map<String, Object> integrity = (Map<String, Object>) parsed.get(
            'chainIntegrity'
        );
        System.assertEquals(
            0,
            integrity.get('totalCertificates'),
            'Should have 0 certificates'
        );
        System.assertEquals(
            true,
            integrity.get('chainIntact'),
            'Chain should be intact with no certs'
        );
    }

    @IsTest
    static void testExportForAllFrameworks() {
        Test.startTest();
        String result = ComplianceEvidenceExporter.exportForFramework(
            'ALL',
            Date.today().addDays(-30),
            Date.today()
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Export should return non-null JSON'
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            result
        );
        Map<String, Object> meta = (Map<String, Object>) parsed.get(
            'exportMetadata'
        );
        System.assertEquals(
            'ALL',
            meta.get('framework'),
            'Framework should be ALL'
        );
    }

    @IsTest
    static void testExportCertificateEvidence() {
        // Create a job and certificate
        Quantum_Job__c job = new Quantum_Job__c(
            Status__c = 'Completed',
            Raw_Results__c = '0xABCD',
            Debiased_Results__c = '0x12'
        );
        insert job;

        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{"passed": true}',
            'Certified'
        );

        Test.startTest();
        String result = ComplianceEvidenceExporter.exportCertificateEvidence(
            certId
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Export should return non-null JSON'
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            result
        );
        System.assert(
            parsed.containsKey('certificate'),
            'Should contain certificate'
        );
        Map<String, Object> certData = (Map<String, Object>) parsed.get(
            'certificate'
        );
        System.assertEquals(
            'Certified',
            certData.get('status'),
            'Should be Certified'
        );
    }
}
