/**
 * Converts quantum random bits into fair assignments.
 * Supports uniform, weighted, and subset selection modes.
 * Each assignment is deterministically derived from the quantum bits.
 */
public with sharing class QuantumAssignmentEngine {

    /**
     * Uniform assignment: distribute records evenly across assignees.
     * For each record, consume ceil(log2(assigneeCount)) bits and mod to select.
     */
    public static List<QRNG_Assignment__c> assignUniform(
        List<String> recordIds,
        List<String> assigneeIds,
        String randomBits,
        Id jobId,
        Id certificateId
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new QRNGException('No records to assign');
        }
        if (assigneeIds == null || assigneeIds.isEmpty()) {
            throw new QRNGException('No assignees provided');
        }

        Integer bitsNeeded = ceilLog2(assigneeIds.size());
        List<QRNG_Assignment__c> assignments = new List<QRNG_Assignment__c>();
        Integer bitOffset = 0;

        for (Integer i = 0; i < recordIds.size(); i++) {
            String bits = QRNGResultParser.consumeBits(randomBits, bitOffset, bitsNeeded);
            Integer value = QRNGResultParser.bitsToInteger(bits);
            Integer assigneeIndex = Math.mod(value, assigneeIds.size());

            assignments.add(
                new QRNG_Assignment__c(
                    Quantum_Job__c = jobId,
                    Certificate__c = certificateId,
                    Assigned_Record_ID__c = recordIds[i],
                    Assigned_To_ID__c = assigneeIds[assigneeIndex],
                    Assignment_Index__c = i,
                    Random_Value__c = bits
                )
            );

            bitOffset += bitsNeeded;
        }

        return assignments;
    }

    /**
     * Weighted assignment: distribute records according to weight proportions.
     * Uses CDF-based selection with quantum random values.
     */
    public static List<QRNG_Assignment__c> assignWeighted(
        List<String> recordIds,
        List<String> assigneeIds,
        List<Double> weights,
        String randomBits,
        Id jobId,
        Id certificateId
    ) {
        if (weights == null || weights.size() != assigneeIds.size()) {
            throw new QRNGException('Weights must match number of assignees');
        }

        // Build CDF
        Double totalWeight = 0;
        for (Double w : weights) {
            totalWeight += w;
        }

        List<Double> cdf = new List<Double>();
        Double cumulative = 0;
        for (Double w : weights) {
            cumulative += w / totalWeight;
            cdf.add(cumulative);
        }

        // Use 10 bits for resolution (1024 values)
        Integer bitsPerSelection = 10;
        List<QRNG_Assignment__c> assignments = new List<QRNG_Assignment__c>();
        Integer bitOffset = 0;

        for (Integer i = 0; i < recordIds.size(); i++) {
            String bits = QRNGResultParser.consumeBits(randomBits, bitOffset, bitsPerSelection);
            Integer value = QRNGResultParser.bitsToInteger(bits);
            Double normalizedValue = (Double) value / 1024.0;

            // Find assignee via CDF
            Integer assigneeIndex = 0;
            for (Integer j = 0; j < cdf.size(); j++) {
                if (normalizedValue <= cdf[j]) {
                    assigneeIndex = j;
                    break;
                }
            }

            assignments.add(
                new QRNG_Assignment__c(
                    Quantum_Job__c = jobId,
                    Certificate__c = certificateId,
                    Assigned_Record_ID__c = recordIds[i],
                    Assigned_To_ID__c = assigneeIds[assigneeIndex],
                    Assignment_Index__c = i,
                    Random_Value__c = bits
                )
            );

            bitOffset += bitsPerSelection;
        }

        return assignments;
    }

    /**
     * Subset selection: Fisher-Yates shuffle using quantum bits, take first K.
     * Used for unbiased audit sampling.
     */
    public static List<QRNG_Assignment__c> selectSubset(
        List<String> recordIds,
        Integer sampleSize,
        String randomBits,
        Id jobId,
        Id certificateId
    ) {
        if (sampleSize > recordIds.size()) {
            throw new QRNGException(
                'Sample size (' + sampleSize + ') exceeds population (' + recordIds.size() + ')'
            );
        }

        // Fisher-Yates shuffle
        List<String> shuffled = new List<String>(recordIds);
        Integer bitsNeeded = ceilLog2(recordIds.size());
        Integer bitOffset = 0;

        for (Integer i = shuffled.size() - 1; i > 0; i--) {
            String bits = QRNGResultParser.consumeBits(randomBits, bitOffset, bitsNeeded);
            Integer j = Math.mod(QRNGResultParser.bitsToInteger(bits), i + 1);

            // Swap
            String temp = shuffled[i];
            shuffled[i] = shuffled[j];
            shuffled[j] = temp;

            bitOffset += bitsNeeded;
        }

        // Take first K
        List<QRNG_Assignment__c> assignments = new List<QRNG_Assignment__c>();
        for (Integer i = 0; i < sampleSize; i++) {
            assignments.add(
                new QRNG_Assignment__c(
                    Quantum_Job__c = jobId,
                    Certificate__c = certificateId,
                    Assigned_Record_ID__c = shuffled[i],
                    Assignment_Index__c = i,
                    Random_Value__c = 'selected'
                )
            );
        }

        return assignments;
    }

    /**
     * Ceiling of log base 2. Minimum 1.
     */
    public static Integer ceilLog2(Integer n) {
        if (n <= 1) {
            return 1;
        }
        Integer bits = 0;
        Integer val = n - 1;
        while (val > 0) {
            bits++;
            val = val >> 1;
        }
        return bits;
    }
}
