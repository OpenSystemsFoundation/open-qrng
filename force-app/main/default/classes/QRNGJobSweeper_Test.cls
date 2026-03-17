@IsTest
private class QRNGJobSweeper_Test {
    @IsTest
    static void testScheduleAndUnschedule() {
        Test.startTest();
        QRNGJobSweeper.scheduleDefault();
        Test.stopTest();

        System.assertEquals(
            true,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be scheduled'
        );

        QRNGJobSweeper.unschedule();
        System.assertEquals(
            false,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be unscheduled'
        );
    }

    @IsTest
    static void testSweeperWithNoJobs() {
        QRNGJobSweeper.QRNGJobSweeperWorker worker = new QRNGJobSweeper.QRNGJobSweeperWorker();

        Test.startTest();
        worker.execute(null);
        Test.stopTest();

        // No jobs to process — should complete without error
        System.assert(true, 'Worker executed without error');
    }

    @IsTest
    static void testSweeperControllerMethods() {
        Test.startTest();
        QRNGSetupController.startSweeper();
        Test.stopTest();

        System.assertEquals(
            true,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be active after startSweeper'
        );

        QRNGSetupController.stopSweeper();
        System.assertEquals(
            false,
            QRNGJobSweeper.isScheduled(),
            'Sweeper should be inactive after stopSweeper'
        );
    }
}
