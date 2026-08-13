/**
 * Flow-compatible invocable action for quantum random assignment.
 * Enables admins to use QuantumFair from Flow Builder with zero code.
 *
 * Bulk-safe and trigger-safe: this method performs NO callouts. For each
 * request it inserts a Quantum_Job__c in Status__c = 'Pending' with the
 * full request persisted as JSON in Assignment_Request__c, then enqueues
 * a single QuantumSubmissionQueueable that submits the pending jobs to
 * IBM Quantum one at a time (callout-then-update, chained). This makes
 * the action safe to call with up to 200 Flow interviews per bulk
 * invocation and from RecordAfterSave record-triggered flows.
 *
 * success = true means the job was QUEUED for submission; results arrive
 * asynchronously via Quantum_Job_Complete__e / Quantum_Job_Failed__e.
 * 'Pending' jobs that are never submitted (e.g. queueable failure) are
 * failed by the JobSweeper after 15 minutes.
 */
public with sharing class QuantumRandomAssignment {
    /**
     * Maximum length of the LongTextArea fields that store encoded results
     * (Raw_Results__c / Debiased_Results__c). Configurations whose encoded
     * raw bitstring cannot fit are rejected at submission time — truncating
     * would break the audit chain (H-R3).
     */
    public static final Integer MAX_STORED_RESULT_CHARS = 131072;

    public class AssignmentRequest {
        @InvocableVariable(
            label='Record IDs'
            description='List of record IDs to assign'
            required=true
        )
        public List<String> recordIds;

        @InvocableVariable(
            label='Assignee IDs'
            description='List of User or Queue IDs to assign to'
        )
        public List<String> assigneeIds;

        @InvocableVariable(
            label='Assignment Type'
            description='Uniform, Weighted, or Subset'
            required=true
        )
        public String assignmentType;

        @InvocableVariable(
            label='Weights'
            description='Comma-separated weight values for Weighted mode'
        )
        public String weights;

        @InvocableVariable(
            label='Sample Size'
            description='Number of records to select for Subset mode'
        )
        public Integer sampleSize;

        @InvocableVariable(
            label='Purpose'
            description='Description for the fairness certificate'
            required=true
        )
        public String purpose;

        @InvocableVariable(
            label='Use Bell Test'
            description='Whether to use stronger Bell-test certification'
        )
        public Boolean useBellTest;

        @InvocableVariable(
            label='Number of Qubits'
            description='Number of qubits (default: 8)'
        )
        public Integer numQubits;

        @InvocableVariable(
            label='Backend'
            description='IBM backend name (default: from settings)'
        )
        public String backend;
    }

    public class AssignmentResult {
        @InvocableVariable(label='Job ID' description='Quantum Job record ID')
        public Id jobId;

        @InvocableVariable(
            label='Success'
            description='Whether the job was queued for submission'
        )
        public Boolean success;

        @InvocableVariable(
            label='Error Message'
            description='Error message if queueing failed'
        )
        public String errorMessage;
    }

    /**
     * Persisted representation of an assignment request. Stored as JSON in
     * Quantum_Job__c.Assignment_Request__c at submission time, consumed by
     * QuantumSubmissionQueueable (circuit build + IBM submission) and
     * replayed by JobProcessor when the job completes (assignment creation).
     */
    public class AssignmentRequestData {
        public List<String> recordIds;
        public List<String> assigneeIds;
        public List<Double> weights;
        public Integer sampleSize;
        public String assignmentType;
        public String purpose;
        public Boolean useBellTest;
        public String backend;
        public Integer numQubits;
        public Integer shots;
    }

    @InvocableMethod(
        label='Quantum Random Assignment'
        description='Assigns records using quantum-certified randomness from IBM Quantum hardware'
        category='QuantumFair'
    )
    public static List<AssignmentResult> execute(
        List<AssignmentRequest> requests
    ) {
        List<AssignmentResult> results = new List<AssignmentResult>();
        List<Quantum_Job__c> jobsToInsert = new List<Quantum_Job__c>();
        // Maps position in jobsToInsert → position in results
        List<Integer> resultIndexForJob = new List<Integer>();

        Quantum_Settings__c settings = Quantum_Settings__c.getInstance();
        Integer defaultShots = settings != null &&
            settings.Default_Shots__c != null
            ? (Integer) settings.Default_Shots__c
            : 1024;
        String defaultBackend = settings != null &&
            String.isNotBlank(settings.Default_Backend__c)
            ? settings.Default_Backend__c
            : null;

        for (Integer r = 0; r < requests.size(); r++) {
            AssignmentRequest req = requests[r];
            AssignmentResult result = new AssignmentResult();
            results.add(result);

            try {
                AssignmentRequestData data = buildRequestData(
                    req,
                    defaultShots,
                    defaultBackend
                );

                // Reject configurations whose raw results could not be
                // stored without truncation (which would break the audit
                // chain). Encoded size = ceil(bits/4) hex chars + '0x'.
                Long totalBits = (Long) data.numQubits * (Long) data.shots;
                Long encodedChars = ((totalBits + 3) / 4) + 2;
                if (encodedChars > MAX_STORED_RESULT_CHARS) {
                    throw new QuantumException(
                        'Configuration produces ' +
                            totalBits +
                            ' bits (' +
                            encodedChars +
                            ' encoded chars), exceeding the storable maximum of ' +
                            MAX_STORED_RESULT_CHARS +
                            ' chars. Lower qubits x shots so that ceil(qubits*shots/4) + 2 <= ' +
                            MAX_STORED_RESULT_CHARS +
                            '.'
                    );
                }

                jobsToInsert.add(
                    new Quantum_Job__c(
                        Status__c = 'Pending',
                        Backend__c = data.backend,
                        Shots__c = data.shots,
                        Num_Qubits__c = data.numQubits,
                        Purpose__c = data.purpose,
                        Use_Bell_Test__c = data.useBellTest,
                        Job_Type__c = 'Quantum',
                        Provider__c = 'ibm',
                        Requested_By__c = UserInfo.getUserId(),
                        Submitted_At__c = DateTime.now(),
                        Assignment_Type__c = data.assignmentType,
                        Assignment_Request__c = JSON.serialize(data)
                    )
                );
                resultIndexForJob.add(r);
            } catch (Exception e) {
                result.success = false;
                result.errorMessage = e.getMessage();
            }
        }

        // Single bulk DML — no callouts have happened in this transaction
        if (!jobsToInsert.isEmpty()) {
            insert jobsToInsert;

            List<Id> pendingJobIds = new List<Id>();
            for (Integer i = 0; i < jobsToInsert.size(); i++) {
                pendingJobIds.add(jobsToInsert[i].Id);
                AssignmentResult result = results[resultIndexForJob[i]];
                result.jobId = jobsToInsert[i].Id;
                result.success = true;
            }

            // One queueable submits all pending jobs (one per execution,
            // chained) so callouts never follow DML in the same transaction.
            System.enqueueJob(new QuantumSubmissionQueueable(pendingJobIds));
        }

        return results;
    }

    /**
     * Validate a Flow request and convert it to the persisted DTO.
     * Throws QuantumException on invalid input (no job record is created).
     */
    @TestVisible
    private static AssignmentRequestData buildRequestData(
        AssignmentRequest req,
        Integer defaultShots,
        String defaultBackend
    ) {
        if (req.recordIds == null || req.recordIds.isEmpty()) {
            throw new QuantumException('Record IDs are required');
        }
        if (String.isBlank(req.assignmentType)) {
            throw new QuantumException('Assignment Type is required');
        }

        AssignmentRequestData data = new AssignmentRequestData();
        data.recordIds = req.recordIds;
        data.assigneeIds = req.assigneeIds;
        data.sampleSize = req.sampleSize;
        data.assignmentType = req.assignmentType;
        data.purpose = req.purpose;
        data.useBellTest = req.useBellTest != null ? req.useBellTest : false;
        data.backend = String.isNotBlank(req.backend)
            ? req.backend
            : defaultBackend;
        data.numQubits = req.numQubits != null ? req.numQubits : 8;
        data.shots = defaultShots;

        if (req.assignmentType == 'Uniform') {
            if (req.assigneeIds == null || req.assigneeIds.isEmpty()) {
                throw new QuantumException(
                    'Assignee IDs are required for Uniform assignment'
                );
            }
        } else if (req.assignmentType == 'Weighted') {
            if (req.assigneeIds == null || req.assigneeIds.isEmpty()) {
                throw new QuantumException(
                    'Assignee IDs are required for Weighted assignment'
                );
            }
            data.weights = parseWeights(req.weights);
            if (data.weights.size() != req.assigneeIds.size()) {
                throw new QuantumException(
                    'Number of weights (' +
                        data.weights.size() +
                        ') must match number of assignees (' +
                        req.assigneeIds.size() +
                        ')'
                );
            }
        } else if (req.assignmentType == 'Subset') {
            if (req.sampleSize == null || req.sampleSize <= 0) {
                throw new QuantumException(
                    'Sample Size is required for Subset selection'
                );
            }
            if (req.sampleSize > req.recordIds.size()) {
                throw new QuantumException(
                    'Sample size (' +
                        req.sampleSize +
                        ') exceeds population (' +
                        req.recordIds.size() +
                        ')'
                );
            }
        } else {
            throw new QuantumException(
                'Unknown assignment type: ' +
                    req.assignmentType +
                    '. Expected Uniform, Weighted, or Subset.'
            );
        }

        return data;
    }

    /**
     * Parse a comma-separated weight string into positive Doubles.
     */
    @TestVisible
    private static List<Double> parseWeights(String weights) {
        if (String.isBlank(weights)) {
            throw new QuantumException(
                'Weights are required for Weighted assignment'
            );
        }
        List<Double> parsed = new List<Double>();
        for (String part : weights.split(',')) {
            String trimmed = part.trim();
            Double value;
            try {
                value = Double.valueOf(trimmed);
            } catch (Exception e) {
                throw new QuantumException('Invalid weight value: ' + trimmed);
            }
            if (value <= 0) {
                throw new QuantumException(
                    'Weights must be positive, got: ' + trimmed
                );
            }
            parsed.add(value);
        }
        return parsed;
    }
}
