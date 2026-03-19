/**
 * Utility class for parsing IBM Quantum API responses.
 * Centralizes status extraction, normalization, error message building,
 * and timestamp parsing that were previously duplicated across
 * JobPoller, JobSweeper, and SetupController.
 *
 * All methods are stateless (public static). No DML or SOQL.
 */
public with sharing class IBMResponseParser {
    /**
     * Extract job status from an IBM status response.
     * Handles both nested state.status (newer API) and top-level status.
     */
    public static String extractStatus(Map<String, Object> response) {
        if (response == null) {
            return 'Unknown';
        }
        if (response.containsKey('state')) {
            Object stateObj = response.get('state');
            if (stateObj instanceof Map<String, Object>) {
                Map<String, Object> state = (Map<String, Object>) stateObj;
                if (state.containsKey('status')) {
                    return (String) state.get('status');
                }
            }
        }
        if (response.containsKey('status')) {
            return (String) response.get('status');
        }
        return 'Unknown';
    }

    /**
     * Normalize an IBM status string to the internal Salesforce status values.
     * Maps case-insensitive IBM statuses to: Completed, Running, Queued, Failed, Submitted.
     */
    public static String normalizeStatus(String ibmStatus) {
        if (ibmStatus == null) {
            return 'Submitted';
        }
        String lower = ibmStatus.toLowerCase();
        if (lower == 'completed' || lower == 'result_ready') {
            return 'Completed';
        }
        if (lower == 'running') {
            return 'Running';
        }
        if (lower == 'queued' || lower == 'pending_in_queue') {
            return 'Queued';
        }
        if (lower == 'failed' || lower == 'cancelled' || lower == 'canceled') {
            return 'Failed';
        }
        return 'Submitted';
    }

    /**
     * Check whether a normalized status represents a terminal (completed or failed) state.
     */
    public static Boolean isTerminal(String normalizedStatus) {
        return normalizedStatus == 'Completed' || normalizedStatus == 'Failed';
    }

    /**
     * Check whether a raw IBM status represents a completed state.
     */
    public static Boolean isCompleted(String rawStatus) {
        return normalizeStatus(rawStatus) == 'Completed';
    }

    /**
     * Check whether a raw IBM status represents a failed state.
     */
    public static Boolean isFailed(String rawStatus) {
        return normalizeStatus(rawStatus) == 'Failed';
    }

    /**
     * Build a verbose error message from an IBM status response.
     * Extracts error code, message, solution, more_info, and state reason/reason_code.
     */
    public static String buildErrorMessage(
        String status,
        Map<String, Object> statusResponse
    ) {
        String msg = 'IBM job status: ' + status;

        if (statusResponse == null) {
            return msg;
        }

        // Extract error object
        if (statusResponse.containsKey('error')) {
            Object errObj = statusResponse.get('error');
            if (errObj instanceof Map<String, Object>) {
                Map<String, Object> error = (Map<String, Object>) errObj;

                if (error.containsKey('code')) {
                    msg += '\nError code: ' + error.get('code');
                }
                if (error.containsKey('message')) {
                    msg += '\nError message: ' + (String) error.get('message');
                }
                if (error.containsKey('solution')) {
                    msg += '\nSolution: ' + (String) error.get('solution');
                }
                if (error.containsKey('more_info')) {
                    msg += '\nMore info: ' + (String) error.get('more_info');
                }
            } else {
                msg += '\nError: ' + String.valueOf(errObj);
            }
        }

        // Some IBM responses include state.reason
        if (statusResponse.containsKey('state')) {
            Object stateObj = statusResponse.get('state');
            if (stateObj instanceof Map<String, Object>) {
                Map<String, Object> state = (Map<String, Object>) stateObj;
                if (state.containsKey('reason')) {
                    msg += '\nReason: ' + (String) state.get('reason');
                }
                if (state.containsKey('reason_code')) {
                    msg += '\nReason code: ' + state.get('reason_code');
                }
            }
        }

        return msg;
    }

    /**
     * Extract queue time in milliseconds from IBM status response timestamps.
     * IBM returns timestamps: { created: "...", running: "...", completed: "..." }
     * Queue time = running - created.
     */
    public static Decimal extractQueueTimeMs(
        Map<String, Object> statusResponse
    ) {
        if (
            statusResponse == null || !statusResponse.containsKey('timestamps')
        ) {
            return null;
        }
        Object tsObj = statusResponse.get('timestamps');
        if (!(tsObj instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> timestamps = (Map<String, Object>) tsObj;
        String created = (String) timestamps.get('created');
        String running = (String) timestamps.get('running');
        if (String.isBlank(created) || String.isBlank(running)) {
            return null;
        }
        try {
            DateTime createdDt = DateTime.valueOf(
                created.replace('T', ' ').replace('Z', '')
            );
            DateTime runningDt = DateTime.valueOf(
                running.replace('T', ' ').replace('Z', '')
            );
            return runningDt.getTime() - createdDt.getTime();
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Extract QPU time in seconds from IBM status/results response.
     * IBM returns: { usage: { quantum_seconds: 1.234 } } or
     *              { usage: { seconds: 1.234 } }
     */
    public static Decimal extractQpuTimeSeconds(Map<String, Object> response) {
        if (response == null || !response.containsKey('usage')) {
            return null;
        }
        Object usageObj = response.get('usage');
        if (!(usageObj instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> usage = (Map<String, Object>) usageObj;

        // Try quantum_seconds first (newer API), then seconds (legacy)
        if (usage.containsKey('quantum_seconds')) {
            return toDecimal(usage.get('quantum_seconds'));
        }
        if (usage.containsKey('seconds')) {
            return toDecimal(usage.get('seconds'));
        }
        return null;
    }

    private static Decimal toDecimal(Object val) {
        if (val == null)
            return null;
        if (val instanceof Decimal)
            return (Decimal) val;
        if (val instanceof Double)
            return Decimal.valueOf((Double) val);
        if (val instanceof Integer)
            return Decimal.valueOf((Integer) val);
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return null;
        }
    }
}
