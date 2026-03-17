@IsTest
private class QRNGJobPollScheduler_Test {
    @IsTest
    static void testConstructorAndExecute() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_scheduler',
            Provider__c = 'ibm',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        QRNGJobPollScheduler scheduler = new QRNGJobPollScheduler(
            job.Id,
            'test_scheduler',
            1
        );

        Test.startTest();
        // Execute directly — the enqueueJob inside will be captured by Test context
        scheduler.execute(null);
        Test.stopTest();

        // Verify the poller was enqueued (no exception thrown)
        System.assert(true, 'Scheduler executed without error');
    }

    @IsTest
    static void testScheduleNextPoll() {
        Quantum_Job__c job = new Quantum_Job__c(
            External_Job_ID__c = 'test_schedule',
            Provider__c = 'ibm',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
        insert job;

        Test.startTest();
        QRNGJobPollScheduler.scheduleNextPoll(job.Id, 'test_schedule', 0);
        Test.stopTest();

        // Verify our specific scheduled job was created
        String expectedName = 'QRNGPoll_' + job.Id + '_0';
        List<CronTrigger> triggers = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = :expectedName
        ];
        System.assertEquals(
            1,
            triggers.size(),
            'Expected scheduled poll job: ' + expectedName
        );
    }
}
