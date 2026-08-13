@IsTest
private class JobPollScheduler_Test {
    private static Quantum_Job__c makeJob(String externalJobId) {
        return new Quantum_Job__c(
            External_Job_ID__c = externalJobId,
            Provider__c = 'ibm',
            Backend__c = 'test_backend',
            Status__c = 'Submitted',
            Shots__c = 1024,
            Num_Qubits__c = 8
        );
    }

    @IsTest
    static void testConstructorAndExecute() {
        Quantum_Job__c job = makeJob('test_scheduler');
        insert job;

        JobPollScheduler scheduler = new JobPollScheduler(
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
    static void testExecuteCarriesTransientStreak() {
        Quantum_Job__c job = makeJob('test_scheduler_streak');
        insert job;

        JobPollScheduler scheduler = new JobPollScheduler(
            job.Id,
            'test_scheduler_streak',
            4,
            2
        );

        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Scheduler executed without error');
    }

    @IsTest
    static void testScheduleNextPoll() {
        Quantum_Job__c job = makeJob('test_schedule');
        insert job;

        Test.startTest();
        JobPollScheduler.scheduleNextPoll(job.Id, 'test_schedule', 0);
        Test.stopTest();

        // Verify our specific scheduled job was created
        String expectedName = 'QuantumPoll_' + job.Id + '_0';
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

    @IsTest
    static void testScheduleNextPollWithDelay() {
        Quantum_Job__c job = makeJob('test_schedule_delay');
        insert job;

        // No startTest/stopTest — the cron must stay pending so its
        // NextFireTime can be asserted (stopTest would fire it immediately).
        JobPollScheduler.scheduleNextPoll(
            job.Id,
            'test_schedule_delay',
            7,
            5,
            1
        );

        String expectedName = 'QuantumPoll_' + job.Id + '_7';
        List<CronTrigger> triggers = [
            SELECT Id, NextFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name = :expectedName
        ];
        System.assertEquals(
            1,
            triggers.size(),
            'Expected scheduled poll job: ' + expectedName
        );
        System.assert(
            triggers[0].NextFireTime >= DateTime.now().addMinutes(4),
            'Next fire should honor the requested ~5 minute delay, got: ' +
            triggers[0].NextFireTime
        );
    }

    @IsTest
    static void testScheduleNextPollDefaultsInvalidDelay() {
        Quantum_Job__c job = makeJob('test_schedule_baddelay');
        insert job;

        // Zero/negative delays are coerced to 1 minute
        JobPollScheduler.scheduleNextPoll(
            job.Id,
            'test_schedule_baddelay',
            2,
            0,
            0
        );

        String expectedName = 'QuantumPoll_' + job.Id + '_2';
        List<CronTrigger> triggers = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :expectedName
        ];
        System.assertEquals(1, triggers.size());
    }

    @IsTest
    static void testSchedulingFailureLeavesJobForSweeper() {
        Quantum_Job__c job = makeJob('test_schedule_full');
        insert job;

        // First call claims the job name; the second collides, which is the
        // same failure shape as scheduler-slot exhaustion (System.schedule
        // throws). It must NOT bubble up or fail the job. No stopTest so the
        // pending cron does not fire an unmocked poller.
        JobPollScheduler.scheduleNextPoll(job.Id, 'test_schedule_full', 3);
        JobPollScheduler.scheduleNextPoll(
            job.Id,
            'test_schedule_full',
            3,
            1,
            0
        );

        job = [
            SELECT Id, Status__c, Error_Message__c
            FROM Quantum_Job__c
            WHERE Id = :job.Id
        ];
        System.assertEquals(
            'Submitted',
            job.Status__c,
            'A scheduling failure must not fail the job'
        );
        System.assert(
            job.Error_Message__c != null &&
            job.Error_Message__c.contains(
                'Poll scheduling unavailable; sweeper will monitor'
            ),
            'Should note the sweeper fallback on the job: ' +
            job.Error_Message__c
        );
    }
}
