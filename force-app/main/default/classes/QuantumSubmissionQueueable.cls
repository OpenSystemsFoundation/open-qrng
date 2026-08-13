/**
 * Submits 'Pending' Quantum_Job__c records to IBM Quantum, one job per
 * queueable execution, chaining to the next with System.enqueueJob so
 * callout-then-update ordering is always safe (each job's callouts happen
 * before any DML in its own transaction).
 *
 * Flow: QuantumRandomAssignment inserts pending jobs (no callouts), then
 * enqueues this class with the pending job Ids. Each execution:
 *   1. Loads the first pending job (skips it if no longer 'Pending' —
 *      e.g. already failed by the JobSweeper).
 *   2. Resolves the backend (request → settings default → least busy).
 *   3. Builds the QRNG circuit (standard or Bell test) with calibration.
 *   4. Submits to IBM via IBMQuantumService.callSubmitJob.
 *   5. Updates the job to Status__c = 'Submitted' and starts polling via
 *      JobPollScheduler.scheduleNextPoll (same as IBMQuantumService.submitJob,
 *      but scheduled — a queueable may only enqueue one child, which is
 *      reserved for the submission chain).
 *   6. On error: marks the job Failed, publishes Quantum_Job_Failed__e,
 *      and continues the chain with the remaining jobs.
 *
 * Governor limits per execution: up to 5 callouts (auth, backends,
 * properties, configuration, submit), ~2 SOQL, 1 DML.
 */
public with sharing class QuantumSubmissionQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> pendingJobIds;

    public QuantumSubmissionQueueable(List<Id> pendingJobIds) {
        this.pendingJobIds = pendingJobIds != null
            ? pendingJobIds
            : new List<Id>();
    }

    public void execute(QueueableContext context) {
        if (pendingJobIds.isEmpty()) {
            return;
        }

        Id jobId = pendingJobIds[0];
        List<Id> remaining = new List<Id>();
        for (Integer i = 1; i < pendingJobIds.size(); i++) {
            remaining.add(pendingJobIds[i]);
        }

        try {
            submitPendingJob(jobId);
        } catch (Exception e) {
            markJobFailed(jobId, e.getMessage());
        }

        // Chain to the next pending job in a fresh transaction
        if (!remaining.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new QuantumSubmissionQueueable(remaining));
        }
    }

    /**
     * Perform all callouts for one pending job, then update it.
     * Callouts strictly precede DML within this transaction.
     */
    @TestVisible
    private static void submitPendingJob(Id jobId) {
        List<Quantum_Job__c> jobs = [
            SELECT
                Id,
                Status__c,
                Backend__c,
                Shots__c,
                Num_Qubits__c,
                Use_Bell_Test__c
            FROM Quantum_Job__c
            WHERE Id = :jobId
            LIMIT 1
        ];
        if (jobs.isEmpty()) {
            return;
        }
        Quantum_Job__c job = jobs[0];
        if (job.Status__c != 'Pending') {
            // Already handled (e.g. swept to Failed) — nothing to submit
            return;
        }

        Integer numQubits = job.Num_Qubits__c != null
            ? (Integer) job.Num_Qubits__c
            : 8;
        Integer shots = job.Shots__c != null ? (Integer) job.Shots__c : 1024;
        Boolean useBellTest = job.Use_Bell_Test__c == true;

        // Resolve backend: job value (request or settings default persisted
        // at queue time) → least busy operational backend (callout)
        String backendName = job.Backend__c;
        if (String.isBlank(backendName)) {
            backendName = IBMQuantumService.getLeastBusyBackend();
        }
        if (String.isBlank(backendName)) {
            throw new QuantumException(
                'No backend specified and no operational backend found'
            );
        }

        // Fetch calibration data (non-fatal if unavailable)
        Map<Integer, Double> readoutErrors;
        try {
            readoutErrors = IBMQuantumService.getReadoutErrors(backendName);
        } catch (Exception ex) {
            readoutErrors = null;
        }

        // Build circuit
        String qasm;
        if (useBellTest) {
            List<List<Integer>> couplingMap = IBMQuantumService.getCouplingMap(
                backendName
            );
            qasm = CircuitBuilder.buildBellTestCircuit(
                numQubits / 2,
                couplingMap,
                readoutErrors
            );
        } else {
            qasm = CircuitBuilder.buildStandardCircuit(
                numQubits,
                readoutErrors
            );
        }

        // Submit to IBM (final callout)
        String ibmJobId = IBMQuantumService.callSubmitJob(
            qasm,
            backendName,
            shots
        );

        // DML after all callouts succeeded
        job.External_Job_ID__c = ibmJobId;
        job.Status__c = 'Submitted';
        job.Backend__c = backendName;
        job.Circuit_QASM__c = qasm;
        job.Submitted_At__c = DateTime.now();
        update job;

        // Start the polling chain (Schedulable — the one allowed child
        // queueable is reserved for chaining submission of remaining jobs)
        if (!Test.isRunningTest()) {
            JobPollScheduler.scheduleNextPoll(job.Id, ibmJobId, 0);
        }
    }

    /**
     * Mark a pending job as Failed and publish the failure event.
     */
    @TestVisible
    private static void markJobFailed(Id jobId, String errorMessage) {
        try {
            Quantum_Job__c job = new Quantum_Job__c(
                Id = jobId,
                Status__c = 'Failed',
                Error_Message__c = ('Job submission failed: ' + errorMessage)
                    .left(32768),
                Completed_At__c = DateTime.now()
            );
            update job;

            EventBus.publish(
                new Quantum_Job_Failed__e(
                    Job_Id__c = jobId,
                    Error_Message__c = ('Job submission failed: ' +
                        errorMessage)
                        .left(255)
                )
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'QuantumSubmissionQueueable: failed to mark job ' +
                    jobId +
                    ' as Failed: ' +
                    e.getMessage()
            );
        }
    }
}
