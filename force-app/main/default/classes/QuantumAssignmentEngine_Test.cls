@IsTest
private class QuantumAssignmentEngine_Test {
    @IsTest
    static void testAssignUniform() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_uniform',
            Backend__c = 'ibm_kingston',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{"passed":true}',
            'Certified'
        );

        List<String> recordIds = new List<String>{
            '001000000000001',
            '001000000000002',
            '001000000000003'
        };
        List<String> assigneeIds = new List<String>{
            '005000000000001',
            '005000000000002'
        };
        // Need ceil(log2(2)) = 1 bit per record, 3 records = 3 bits minimum
        String randomBits = '01101001110001010110';

        List<QRNG_Assignment__c> assignments = QuantumAssignmentEngine.assignUniform(
            recordIds,
            assigneeIds,
            randomBits,
            job.Id,
            certId
        );

        System.assertEquals(3, assignments.size());
        for (QRNG_Assignment__c a : assignments) {
            System.assertNotEquals(null, a.Assigned_To_ID__c);
            System.assertNotEquals(null, a.Random_Value__c);
        }
    }

    @IsTest
    static void testAssignWeighted() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_weighted',
            Backend__c = 'ibm_kingston',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{"passed":true}',
            'Certified'
        );

        List<String> recordIds = new List<String>{
            '001000000000001',
            '001000000000002'
        };
        List<String> assigneeIds = new List<String>{
            '005000000000001',
            '005000000000002'
        };
        List<Double> weights = new List<Double>{ 70.0, 30.0 };
        // 10 bits per selection, 2 records = 20 bits
        String randomBits = '01101001110001010110100111000101';

        List<QRNG_Assignment__c> assignments = QuantumAssignmentEngine.assignWeighted(
            recordIds,
            assigneeIds,
            weights,
            randomBits,
            job.Id,
            certId
        );

        System.assertEquals(2, assignments.size());
    }

    @IsTest
    static void testSelectSubset() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_subset',
            Backend__c = 'ibm_kingston',
            Status__c = 'Completed',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Id certId = FairnessCertificateService.createCertificate(
            job.Id,
            '{"passed":true}',
            'Certified'
        );

        List<String> recordIds = new List<String>{
            '001000000000001',
            '001000000000002',
            '001000000000003',
            '001000000000004',
            '001000000000005'
        };
        // Need ceil(log2(5)) = 3 bits per swap, 4 swaps = 12 bits minimum
        String randomBits = '011010011100010101101001110001010110';

        List<QRNG_Assignment__c> assignments = QuantumAssignmentEngine.selectSubset(
            recordIds,
            2,
            randomBits,
            job.Id,
            certId
        );

        System.assertEquals(2, assignments.size());
    }

    @IsTest
    static void testSelectSubsetTooLarge() {
        try {
            QuantumAssignmentEngine.selectSubset(
                new List<String>{ '001000000000001' },
                5,
                '01101001',
                null,
                null
            );
            System.assert(false, 'Should throw');
        } catch (QRNGException e) {
            System.assert(
                e.getMessage().contains('exceeds'),
                'Should mention size exceeds'
            );
        }
    }

    @IsTest
    static void testCeilLog2() {
        System.assertEquals(1, QuantumAssignmentEngine.ceilLog2(1));
        System.assertEquals(1, QuantumAssignmentEngine.ceilLog2(2));
        System.assertEquals(2, QuantumAssignmentEngine.ceilLog2(3));
        System.assertEquals(2, QuantumAssignmentEngine.ceilLog2(4));
        System.assertEquals(3, QuantumAssignmentEngine.ceilLog2(5));
        System.assertEquals(3, QuantumAssignmentEngine.ceilLog2(8));
        System.assertEquals(4, QuantumAssignmentEngine.ceilLog2(9));
    }
}
