/**
 * Flow-compatible invocable action for quantum random assignment.
 * Enables admins to use QuantumFair from Flow Builder with zero code.
 */
public with sharing class QuantumRandomAssignment {
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
            description='Whether the job was submitted successfully'
        )
        public Boolean success;

        @InvocableVariable(
            label='Error Message'
            description='Error message if submission failed'
        )
        public String errorMessage;
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

        for (AssignmentRequest req : requests) {
            AssignmentResult result = new AssignmentResult();

            try {
                // Get settings
                QRNG_Settings__c settings = QRNG_Settings__c.getInstance();
                String backendName = String.isNotBlank(req.backend)
                    ? req.backend
                    : (settings != null &&
                          String.isNotBlank(settings.Default_Backend__c)
                          ? settings.Default_Backend__c
                          : 'ibm_kingston');
                Integer numQubits = req.numQubits != null ? req.numQubits : 8;
                Integer shots = settings != null &&
                    settings.Default_Shots__c != null
                    ? (Integer) settings.Default_Shots__c
                    : 1024;
                Boolean useBellTest = req.useBellTest != null
                    ? req.useBellTest
                    : false;

                // Build circuit
                String qasm;
                if (useBellTest) {
                    qasm = QRNGCircuitBuilder.buildBellTestCircuit(
                        numQubits / 2
                    );
                } else {
                    qasm = QRNGCircuitBuilder.buildStandardCircuit(numQubits);
                }

                // Submit job (async - results come via Platform Event)
                Id jobId = IBMQuantumService.submitJob(
                    qasm,
                    backendName,
                    shots,
                    req.purpose,
                    useBellTest,
                    numQubits
                );

                // Store assignment parameters on the job for processing after completion
                Quantum_Job__c job = new Quantum_Job__c(
                    Id = jobId,
                    Assignment_Type__c = req.assignmentType
                );
                update job;

                result.jobId = jobId;
                result.success = true;
            } catch (Exception e) {
                result.success = false;
                result.errorMessage = e.getMessage();
            }

            results.add(result);
        }

        return results;
    }
}
