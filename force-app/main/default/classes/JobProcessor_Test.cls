@IsTest
private class JobProcessor_Test {
    // ── Sampler completion ──────────────────────────────────────────

    @IsTest
    static void testProcessSamplerCompletion() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_s1',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 8,
            Num_Qubits__c = 8,
            Use_Bell_Test__c = false,
            Submitted_At__c = DateTime.now().addMinutes(-5)
        );
        insert job;

        String resultsJson = '{"results":[{"data":{"meas":{"samples":["0x66","0x99","0xe3","0x35","0xaa","0x55","0xcc","0x3c"]}}}]}';
        Map<String, Object> statusResponse = new Map<String, Object>{
            'timestamps' => new Map<String, Object>{
                'created' => '2026-03-17T10:00:00Z',
                'running' => '2026-03-17T10:00:05Z'
            }
        };

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processSamplerCompletion(
            job,
            resultsJson,
            statusResponse
        );
        Test.stopTest();

        System.assertEquals('Completed', result.status);
        System.assertNotEquals(null, result.certificateId);
        System.assert(result.rawBitsLength > 0, 'Should have raw bits');
        System.assert(
            result.debiasedBitsLength >= 0,
            'Should have debiased bits'
        );

        // Verify job was updated
        Quantum_Job__c updated = [
            SELECT
                Status__c,
                Queue_Time_ms__c,
                Raw_Results__c,
                Debiased_Results__c,
                Result_Fingerprint__c,
                Completed_At__c,
                Execution_Time_ms__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals('Completed', updated.Status__c);
        System.assertEquals(5000, updated.Queue_Time_ms__c);
        System.assertNotEquals(null, updated.Raw_Results__c);
        System.assertNotEquals(null, updated.Result_Fingerprint__c);
        System.assertNotEquals(null, updated.Completed_At__c);
        System.assertNotEquals(null, updated.Execution_Time_ms__c);
    }

    @IsTest
    static void testProcessSamplerCompletionNullStatusResponse() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_s2',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 4,
            Num_Qubits__c = 4,
            Use_Bell_Test__c = false,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        String resultsJson = '{"results":[{"data":{"meas":{"samples":["0110","1001","1110","0011"]}}}]}';

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processSamplerCompletion(
            job,
            resultsJson,
            null
        );
        Test.stopTest();

        System.assertEquals('Completed', result.status);
        // Queue time should be null when no status response
        Quantum_Job__c updated = [
            SELECT Queue_Time_ms__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(null, updated.Queue_Time_ms__c);
    }

    @IsTest
    static void testProcessSamplerCompletionWithBellTest() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_bell',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 8,
            Num_Qubits__c = 8,
            Use_Bell_Test__c = true,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        String resultsJson = '{"results":[{"data":{"meas":{"samples":["0x66","0x99","0xe3","0x35","0xaa","0x55","0xcc","0x3c"]}}}]}';

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processSamplerCompletion(
            job,
            resultsJson,
            null
        );
        Test.stopTest();

        System.assertEquals('Completed', result.status);
        System.assertNotEquals(null, result.chshSValue);
        System.assertNotEquals(null, result.bellTestPassed);
    }

    @IsTest
    static void testProcessSamplerCompletionNullNumQubits() {
        // Tests the default numQubits = 8 path
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_nq',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 4,
            Use_Bell_Test__c = false,
            Submitted_At__c = DateTime.now()
        );
        insert job;

        String resultsJson = '{"results":[{"data":{"meas":{"samples":["0x66","0x99","0xe3","0x35"]}}}]}';

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processSamplerCompletion(
            job,
            resultsJson,
            null
        );
        Test.stopTest();

        System.assertEquals('Completed', result.status);
    }

    // ── Estimator completion ────────────────────────────────────────

    @IsTest
    static void testProcessEstimatorCompletionLegacy() {
        Quantum_Provider__c provider = new Quantum_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        Quantum_Backend__c backend = new Quantum_Backend__c(
            Name = 'test_est_backend',
            Backend_Key__c = 'ibm:test_est_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 127
        );
        insert backend;

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_e1',
            Backend__c = 'test_est_backend',
            Status__c = 'Submitted',
            Program_Id__c = 'estimator',
            Submitted_At__c = DateTime.now()
        );
        insert job;

        // Single-PUB format (legacy — no observable metadata)
        String resultsJson = '{"results":[{"data":{"evs":[2.61],"stds":[0.04]}}]}';

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processEstimatorCompletion(
            job,
            resultsJson,
            null
        );
        Test.stopTest();

        System.assertEquals('Completed', result.status);
        System.assertEquals(2.61, result.chshSValue);
        System.assertEquals(true, result.bellTestPassed);

        // Verify backend was updated
        Quantum_Backend__c updatedBk = [
            SELECT CHSH_S_Value__c, CHSH_Verified_At__c
            FROM Quantum_Backend__c
            WHERE Id = :backend.Id
        ];
        System.assertEquals(2.61, updatedBk.CHSH_S_Value__c);
        System.assertNotEquals(null, updatedBk.CHSH_Verified_At__c);
    }

    @IsTest
    static void testProcessEstimatorCompletionWithMetadata() {
        Quantum_Provider__c provider = new Quantum_Provider__c(
            Name = 'IBM',
            Provider_Key__c = 'ibm',
            Is_Active__c = true
        );
        insert provider;

        Quantum_Backend__c backend = new Quantum_Backend__c(
            Name = 'test_meta_backend',
            Backend_Key__c = 'ibm:test_meta_backend',
            Provider__c = provider.Id,
            Status__c = 'online',
            Num_Qubits__c = 127
        );
        insert backend;

        // Store observable metadata on the job (as set during submission)
        Map<String, Object> meta = new Map<String, Object>();
        meta.put(
            'observableLabels',
            new List<String>{ 'ZZ', 'ZX', 'XZ', 'XX' }
        );
        meta.put(
            'observableCoeffs',
            new Map<String, Object>{
                'ZZ' => 1.0,
                'ZX' => 1.0,
                'XZ' => -1.0,
                'XX' => 1.0
            }
        );

        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_e2',
            Backend__c = 'test_meta_backend',
            Status__c = 'Submitted',
            Program_Id__c = 'estimator',
            Submitted_At__c = DateTime.now(),
            Validation_Results__c = JSON.serialize(meta)
        );
        insert job;

        // Multi-PUB results: one per observable
        String resultsJson =
            '{"results":[' +
            '{"data":{"evs":[0.71],"stds":[0.02]}},' +
            '{"data":{"evs":[0.72],"stds":[0.03]}},' +
            '{"data":{"evs":[0.69],"stds":[0.02]}},' +
            '{"data":{"evs":[0.68],"stds":[0.03]}}' +
            ']}';

        Map<String, Object> statusResponse = new Map<String, Object>{
            'timestamps' => new Map<String, Object>{
                'created' => '2026-03-17T10:00:00Z',
                'running' => '2026-03-17T10:00:03Z'
            }
        };

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processEstimatorCompletion(
            job,
            resultsJson,
            statusResponse
        );
        Test.stopTest();

        System.assertEquals('Completed', result.status);
        // S = 1*0.71 + 1*0.72 + (-1)*0.69 + 1*0.68 = 1.42
        System.assert(result.chshSValue != null, 'Should have S-value');

        // Verify job has summary in raw results
        Quantum_Job__c updated = [
            SELECT Raw_Results__c, Validation_Results__c, Queue_Time_ms__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assert(
            updated.Raw_Results__c.contains('CHSH Bell Test'),
            'Should have summary'
        );
        System.assertEquals(3000, updated.Queue_Time_ms__c);
    }

    @IsTest
    static void testProcessEstimatorCompletionFailingBellTest() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_e3',
            Backend__c = 'nonexistent_backend',
            Status__c = 'Submitted',
            Program_Id__c = 'estimator',
            Submitted_At__c = DateTime.now()
        );
        insert job;

        // S-value below classical bound
        String resultsJson = '{"results":[{"data":{"evs":[1.5],"stds":[0.1]}}]}';

        Test.startTest();
        JobProcessor.ProcessingResult result = JobProcessor.processEstimatorCompletion(
            job,
            resultsJson,
            null
        );
        Test.stopTest();

        System.assertEquals(false, result.bellTestPassed);
        System.assertEquals(1.5, result.chshSValue);
    }

    // ── buildEstimatorSummary ───────────────────────────────────────

    @IsTest
    static void testBuildEstimatorSummary() {
        List<Double> evs = new List<Double>{ 0.71, 0.72, 0.69, 0.68 };
        List<Double> stds = new List<Double>{ 0.02, 0.03, 0.02, 0.03 };
        List<String> labels = new List<String>{ 'ZZ', 'ZX', 'XZ', 'XX' };
        Map<String, Double> coeffs = new Map<String, Double>{
            'ZZ' => 1.0,
            'ZX' => 1.0,
            'XZ' => -1.0,
            'XX' => 1.0
        };

        String summary = JobProcessor.buildEstimatorSummary(
            (Double) 2.61,
            evs,
            stds,
            labels,
            coeffs
        );

        System.assert(summary.contains('CHSH Bell Test'), 'Should have title');
        System.assert(summary.contains('2.61'), 'Should have S-value');
        System.assert(summary.contains('PASS'), 'Should show PASS for S>2');
        System.assert(
            summary.contains('Per-Observable'),
            'Should have breakdown'
        );
    }

    @IsTest
    static void testBuildEstimatorSummaryFailing() {
        List<Double> evs = new List<Double>{ 0.5 };
        List<Double> stds = new List<Double>{ 0.1 };
        List<String> labels = new List<String>{ 'ZZ' };
        Map<String, Double> coeffs = new Map<String, Double>{ 'ZZ' => 1.0 };

        String summary = JobProcessor.buildEstimatorSummary(
            (Double) 1.5,
            evs,
            stds,
            labels,
            coeffs
        );

        System.assert(summary.contains('FAIL'), 'Should show FAIL for S<2');
    }

    // ── updateBackendVerification ───────────────────────────────────

    @IsTest
    static void testUpdateBackendVerificationNoBackend() {
        // Should not throw when backend doesn't exist
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'job_proc_nobk',
            Backend__c = 'nonexistent',
            Status__c = 'Submitted'
        );
        insert job;

        Test.startTest();
        JobProcessor.updateBackendVerification(
            'nonexistent',
            (Double) 2.5,
            job.Id
        );
        Test.stopTest();

        // No exception means success
        System.assert(true, 'Should handle missing backend gracefully');
    }

    // ── ProcessingResult DTO ────────────────────────────────────────

    @IsTest
    static void testProcessingResultDTO() {
        JobProcessor.ProcessingResult pr = new JobProcessor.ProcessingResult();
        pr.status = 'Completed';
        pr.chshSValue = 2.61;
        pr.bellTestPassed = true;
        pr.rawBitsLength = 1024;
        pr.debiasedBitsLength = 256;
        System.assertEquals('Completed', pr.status);
        System.assertEquals(2.61, pr.chshSValue);
    }
}
