/**
 * Converts quantum random bits into fair assignments.
 * Supports uniform, weighted, and subset selection modes.
 *
 * ── Determinism & audit replay ──────────────────────────────────────
 * Every assignment is deterministically derived from the certified
 * debiased quantum bit pool. Bit consumption is STRICTLY SEQUENTIAL:
 * each draw consumes fixed-width blocks starting at offset 0 of the
 * pool, in processing order — input record order for Uniform and
 * Weighted; descending Fisher-Yates positions (n-1 down to 1) for
 * Subset. An auditor holding the certified pool can replay every
 * selection by applying the rules below in the same order.
 *
 * ── Rejection rule (unbiased sampling) ──────────────────────────────
 * To draw an unbiased index in [0, m):
 *   1. Read the next ceil(log2(m)) bits as an unsigned integer v.
 *   2. If v >= m, DISCARD v and read the next block. Discarded blocks
 *      still count as consumed — they advance the pool offset and are
 *      recorded in the audit trail.
 *   3. Repeat until v < m; v is the result.
 * The pool is never wrapped or reused. If the pool is exhausted before
 * a draw completes, the engine throws a QuantumException — it NEVER
 * falls back to a biased selection (no modulo, no default index).
 *
 * Weighted mode uses exact integer arithmetic: each weight is scaled by
 * 10^6 and rounded to a Long; a value v is drawn in [0, scaledTotal)
 * with the rejection rule, then assignees are walked in input order and
 * the first whose cumulative scaled weight exceeds v (strict '<') wins.
 *
 * Random_Value__c stores the exact bits consumed for the deciding draw,
 * including rejected blocks in consumption order, so third parties can
 * verify each individual selection. Special cases: Uniform with a
 * single assignee consumes no bits (Random_Value__c is empty); in
 * Subset mode Random_Value__c holds the bits of the last draw that
 * moved the record into its final position (empty if the record was
 * never displaced during the shuffle).
 */
public with sharing class QuantumAssignmentEngine {
    private static final Long WEIGHT_SCALE = 1000000L;

    /**
     * Tracks the sequential read position within the random bit pool.
     */
    private class BitCursor {
        private String pool;
        private Integer offset = 0;

        private BitCursor(String pool) {
            this.pool = pool == null ? '' : pool;
        }
    }

    /**
     * Result of one unbiased draw: the value and every bit consumed to
     * obtain it (rejected blocks included, in consumption order).
     */
    private class Draw {
        private Long value;
        private String consumedBits;
    }

    /**
     * Rejection-sample an unbiased value in [0, m) from the pool.
     * Throws QuantumException when the pool is exhausted.
     */
    private static Draw drawUnbiased(BitCursor cursor, Long m) {
        Integer width = ceilLog2Long(m);
        String consumed = '';
        while (true) {
            if (cursor.offset + width > cursor.pool.length()) {
                throw new QuantumException(
                    'Insufficient random bits to complete the assignment ' +
                        'without bias: needed ' +
                        width +
                        ' more bits at offset ' +
                        cursor.offset +
                        ' but the pool holds only ' +
                        cursor.pool.length() +
                        ' bits. Increase shots or qubits and rerun.'
                );
            }
            String block = cursor.pool.substring(
                cursor.offset,
                cursor.offset + width
            );
            cursor.offset += width;
            consumed += block;
            Long v = bitsToLong(block);
            if (v < m) {
                Draw d = new Draw();
                d.value = v;
                d.consumedBits = consumed;
                return d;
            }
            // v >= m: rejected — block stays consumed, draw again
        }
        // Not reachable: the loop always returns or throws, but the Apex
        // compiler cannot prove it and requires a terminal statement.
        throw new QuantumException('drawUnbiased: unreachable');
    }

    /**
     * Uniform assignment: distribute records evenly across assignees.
     * Per record, rejection-sample an index in [0, assigneeCount) using
     * ceil(log2(assigneeCount))-bit blocks. With a single assignee no
     * bits are consumed.
     */
    public static List<Quantum_Assignment__c> assignUniform(
        List<String> recordIds,
        List<String> assigneeIds,
        String randomBits,
        Id jobId,
        Id certificateId
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new QuantumException('No records to assign');
        }
        if (assigneeIds == null || assigneeIds.isEmpty()) {
            throw new QuantumException('No assignees provided');
        }

        Integer n = assigneeIds.size();
        BitCursor cursor = new BitCursor(randomBits);
        List<Quantum_Assignment__c> assignments = new List<Quantum_Assignment__c>();

        for (Integer i = 0; i < recordIds.size(); i++) {
            Integer assigneeIndex;
            String consumed;
            if (n == 1) {
                // Only one possible outcome — consume nothing
                assigneeIndex = 0;
                consumed = '';
            } else {
                Draw d = drawUnbiased(cursor, n);
                assigneeIndex = (Integer) d.value;
                consumed = d.consumedBits;
            }

            assignments.add(
                new Quantum_Assignment__c(
                    Quantum_Job__c = jobId,
                    Certificate__c = certificateId,
                    Assigned_Record_ID__c = recordIds[i],
                    Assigned_To_ID__c = assigneeIds[assigneeIndex],
                    Assignment_Index__c = i,
                    Random_Value__c = consumed
                )
            );
        }

        return assignments;
    }

    /**
     * Weighted assignment: distribute records according to weight
     * proportions using exact integer arithmetic (weights scaled by 10^6
     * and rounded). Per record, rejection-sample v in [0, scaledTotal),
     * then walk cumulative scaled weights with strict '<'.
     */
    public static List<Quantum_Assignment__c> assignWeighted(
        List<String> recordIds,
        List<String> assigneeIds,
        List<Double> weights,
        String randomBits,
        Id jobId,
        Id certificateId
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new QuantumException('No records to assign');
        }
        if (assigneeIds == null || assigneeIds.isEmpty()) {
            throw new QuantumException('No assignees provided');
        }
        if (weights == null || weights.size() != assigneeIds.size()) {
            throw new QuantumException(
                'Weights must match number of assignees'
            );
        }

        // Scale weights to exact integers
        List<Long> scaled = new List<Long>();
        Long scaledTotal = 0;
        for (Double w : weights) {
            if (w == null || w <= 0) {
                throw new QuantumException(
                    'All weights must be positive, got: ' + w
                );
            }
            Long s = Math.roundToLong(w * WEIGHT_SCALE);
            if (s <= 0) {
                throw new QuantumException(
                    'Weight too small to represent at 10^-6 resolution: ' + w
                );
            }
            scaled.add(s);
            scaledTotal += s;
        }

        BitCursor cursor = new BitCursor(randomBits);
        List<Quantum_Assignment__c> assignments = new List<Quantum_Assignment__c>();

        for (Integer i = 0; i < recordIds.size(); i++) {
            Draw d = drawUnbiased(cursor, scaledTotal);

            // Walk cumulative scaled weights; strict '<' means a value of
            // exactly the cumulative boundary belongs to the NEXT assignee
            Integer assigneeIndex = scaled.size() - 1;
            Long cumulative = 0;
            for (Integer j = 0; j < scaled.size(); j++) {
                cumulative += scaled[j];
                if (d.value < cumulative) {
                    assigneeIndex = j;
                    break;
                }
            }

            assignments.add(
                new Quantum_Assignment__c(
                    Quantum_Job__c = jobId,
                    Certificate__c = certificateId,
                    Assigned_Record_ID__c = recordIds[i],
                    Assigned_To_ID__c = assigneeIds[assigneeIndex],
                    Assignment_Index__c = i,
                    Random_Value__c = d.consumedBits
                )
            );
        }

        return assignments;
    }

    /**
     * Subset selection: Fisher-Yates shuffle using quantum bits, take
     * first K. Per swap at position i (descending from n-1 to 1), an
     * unbiased j in [0, i] is rejection-sampled with ceil(log2(i+1))-bit
     * blocks. Used for unbiased audit sampling.
     */
    public static List<Quantum_Assignment__c> selectSubset(
        List<String> recordIds,
        Integer sampleSize,
        String randomBits,
        Id jobId,
        Id certificateId
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new QuantumException('No records to select from');
        }
        if (sampleSize == null || sampleSize <= 0) {
            throw new QuantumException('Sample size must be positive');
        }
        if (sampleSize > recordIds.size()) {
            throw new QuantumException(
                'Sample size (' +
                    sampleSize +
                    ') exceeds population (' +
                    recordIds.size() +
                    ')'
            );
        }

        List<String> shuffled = new List<String>(recordIds);
        // Bits consumed by the most recent draw that moved the element
        // now at each position (empty = never displaced)
        List<String> lastDrawBits = new List<String>();
        for (Integer i = 0; i < shuffled.size(); i++) {
            lastDrawBits.add('');
        }

        BitCursor cursor = new BitCursor(randomBits);

        for (Integer i = shuffled.size() - 1; i > 0; i--) {
            Draw d = drawUnbiased(cursor, i + 1);
            Integer j = (Integer) d.value;

            String temp = shuffled[i];
            shuffled[i] = shuffled[j];
            shuffled[j] = temp;

            lastDrawBits[i] = d.consumedBits;
            lastDrawBits[j] = d.consumedBits;
        }

        // Take first K
        List<Quantum_Assignment__c> assignments = new List<Quantum_Assignment__c>();
        for (Integer i = 0; i < sampleSize; i++) {
            assignments.add(
                new Quantum_Assignment__c(
                    Quantum_Job__c = jobId,
                    Certificate__c = certificateId,
                    Assigned_Record_ID__c = shuffled[i],
                    Assignment_Index__c = i,
                    Random_Value__c = lastDrawBits[i]
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

    /**
     * Ceiling of log base 2 for Long values. Minimum 1.
     */
    @TestVisible
    private static Integer ceilLog2Long(Long n) {
        if (n <= 1) {
            return 1;
        }
        Integer bits = 0;
        Long val = n - 1;
        while (val > 0) {
            bits++;
            val = val >> 1;
        }
        return bits;
    }

    /**
     * Convert a binary string to a Long value (supports blocks wider
     * than 31 bits, which Integer arithmetic cannot represent).
     */
    @TestVisible
    private static Long bitsToLong(String bits) {
        Long result = 0;
        for (Integer i = 0; i < bits.length(); i++) {
            result = result * 2;
            if (bits.substring(i, i + 1) == '1') {
                result += 1;
            }
        }
        return result;
    }
}
