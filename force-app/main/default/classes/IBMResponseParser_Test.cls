@IsTest
private class IBMResponseParser_Test {
    // ── extractStatus ───────────────────────────────────────────────

    @IsTest
    static void testExtractStatusNestedState() {
        Map<String, Object> response = new Map<String, Object>{
            'state' => new Map<String, Object>{ 'status' => 'Completed' }
        };
        System.assertEquals(
            'Completed',
            IBMResponseParser.extractStatus(response)
        );
    }

    @IsTest
    static void testExtractStatusTopLevel() {
        Map<String, Object> response = new Map<String, Object>{
            'status' => 'Running'
        };
        System.assertEquals(
            'Running',
            IBMResponseParser.extractStatus(response)
        );
    }

    @IsTest
    static void testExtractStatusNestedTakesPrecedence() {
        // When both state.status and top-level status exist, nested wins
        Map<String, Object> response = new Map<String, Object>{
            'state' => new Map<String, Object>{ 'status' => 'Queued' },
            'status' => 'Running'
        };
        System.assertEquals(
            'Queued',
            IBMResponseParser.extractStatus(response)
        );
    }

    @IsTest
    static void testExtractStatusNull() {
        System.assertEquals('Unknown', IBMResponseParser.extractStatus(null));
    }

    @IsTest
    static void testExtractStatusEmptyMap() {
        System.assertEquals(
            'Unknown',
            IBMResponseParser.extractStatus(new Map<String, Object>())
        );
    }

    @IsTest
    static void testExtractStatusStateNotMap() {
        // state key exists but is not a Map
        Map<String, Object> response = new Map<String, Object>{
            'state' => 'some-string'
        };
        System.assertEquals(
            'Unknown',
            IBMResponseParser.extractStatus(response)
        );
    }

    @IsTest
    static void testExtractStatusStateMapNoStatusKey() {
        Map<String, Object> response = new Map<String, Object>{
            'state' => new Map<String, Object>{ 'reason' => 'no status here' }
        };
        // Falls through to top-level, which is absent → Unknown
        System.assertEquals(
            'Unknown',
            IBMResponseParser.extractStatus(response)
        );
    }

    // ── normalizeStatus ─────────────────────────────────────────────

    @IsTest
    static void testNormalizeStatusCompleted() {
        System.assertEquals(
            'Completed',
            IBMResponseParser.normalizeStatus('Completed')
        );
        System.assertEquals(
            'Completed',
            IBMResponseParser.normalizeStatus('COMPLETED')
        );
        System.assertEquals(
            'Completed',
            IBMResponseParser.normalizeStatus('completed')
        );
        System.assertEquals(
            'Completed',
            IBMResponseParser.normalizeStatus('result_ready')
        );
    }

    @IsTest
    static void testNormalizeStatusRunning() {
        System.assertEquals(
            'Running',
            IBMResponseParser.normalizeStatus('Running')
        );
        System.assertEquals(
            'Running',
            IBMResponseParser.normalizeStatus('RUNNING')
        );
    }

    @IsTest
    static void testNormalizeStatusQueued() {
        System.assertEquals(
            'Queued',
            IBMResponseParser.normalizeStatus('Queued')
        );
        System.assertEquals(
            'Queued',
            IBMResponseParser.normalizeStatus('pending_in_queue')
        );
    }

    @IsTest
    static void testNormalizeStatusFailed() {
        System.assertEquals(
            'Failed',
            IBMResponseParser.normalizeStatus('Failed')
        );
        System.assertEquals(
            'Failed',
            IBMResponseParser.normalizeStatus('Cancelled')
        );
        System.assertEquals(
            'Failed',
            IBMResponseParser.normalizeStatus('canceled')
        );
    }

    @IsTest
    static void testNormalizeStatusNull() {
        System.assertEquals(
            'Submitted',
            IBMResponseParser.normalizeStatus(null)
        );
    }

    @IsTest
    static void testNormalizeStatusUnknown() {
        System.assertEquals(
            'Submitted',
            IBMResponseParser.normalizeStatus('some_unknown_status')
        );
    }

    // ── isTerminal / isCompleted / isFailed ─────────────────────────

    @IsTest
    static void testIsTerminal() {
        System.assertEquals(true, IBMResponseParser.isTerminal('Completed'));
        System.assertEquals(true, IBMResponseParser.isTerminal('Failed'));
        System.assertEquals(false, IBMResponseParser.isTerminal('Running'));
        System.assertEquals(false, IBMResponseParser.isTerminal('Queued'));
        System.assertEquals(false, IBMResponseParser.isTerminal('Submitted'));
    }

    @IsTest
    static void testIsCompleted() {
        System.assertEquals(true, IBMResponseParser.isCompleted('Completed'));
        System.assertEquals(
            true,
            IBMResponseParser.isCompleted('result_ready')
        );
        System.assertEquals(false, IBMResponseParser.isCompleted('Failed'));
    }

    @IsTest
    static void testIsFailed() {
        System.assertEquals(true, IBMResponseParser.isFailed('Failed'));
        System.assertEquals(true, IBMResponseParser.isFailed('Cancelled'));
        System.assertEquals(false, IBMResponseParser.isFailed('Completed'));
    }

    // ── buildErrorMessage ───────────────────────────────────────────

    @IsTest
    static void testBuildErrorMessageNullResponse() {
        String msg = IBMResponseParser.buildErrorMessage('Failed', null);
        System.assertEquals('IBM job status: Failed', msg);
    }

    @IsTest
    static void testBuildErrorMessageEmptyResponse() {
        String msg = IBMResponseParser.buildErrorMessage(
            'Failed',
            new Map<String, Object>{ 'status' => 'Failed' }
        );
        System.assertEquals('IBM job status: Failed', msg);
    }

    @IsTest
    static void testBuildErrorMessageWithFullError() {
        Map<String, Object> response = new Map<String, Object>{
            'error' => new Map<String, Object>{
                'code' => 1234,
                'message' => 'Hardware fault',
                'solution' => 'Retry later',
                'more_info' => 'https://ibm.com/help'
            },
            'state' => new Map<String, Object>{
                'status' => 'Failed',
                'reason' => 'Calibration expired',
                'reason_code' => 8020
            }
        };
        String msg = IBMResponseParser.buildErrorMessage('Failed', response);

        System.assert(msg.contains('Error code: 1234'), 'Should have code');
        System.assert(msg.contains('Hardware fault'), 'Should have message');
        System.assert(msg.contains('Retry later'), 'Should have solution');
        System.assert(
            msg.contains('https://ibm.com/help'),
            'Should have more_info'
        );
        System.assert(
            msg.contains('Calibration expired'),
            'Should have reason'
        );
        System.assert(msg.contains('8020'), 'Should have reason_code');
    }

    @IsTest
    static void testBuildErrorMessageWithStringError() {
        Map<String, Object> response = new Map<String, Object>{
            'error' => 'Simple error string'
        };
        String msg = IBMResponseParser.buildErrorMessage('Cancelled', response);
        System.assert(
            msg.contains('Simple error string'),
            'Should contain string error'
        );
    }

    @IsTest
    static void testBuildErrorMessagePartialError() {
        // Error object with only message (no code, solution, etc.)
        Map<String, Object> response = new Map<String, Object>{
            'error' => new Map<String, Object>{
                'message' => 'Something went wrong'
            }
        };
        String msg = IBMResponseParser.buildErrorMessage('Failed', response);
        System.assert(msg.contains('Something went wrong'));
        System.assert(!msg.contains('Error code:'));
        System.assert(!msg.contains('Solution:'));
    }

    // ── extractQueueTimeMs ──────────────────────────────────────────

    @IsTest
    static void testExtractQueueTimeMsValid() {
        Map<String, Object> response = new Map<String, Object>{
            'timestamps' => new Map<String, Object>{
                'created' => '2026-03-17T10:00:00Z',
                'running' => '2026-03-17T10:00:12Z'
            }
        };
        Decimal queueMs = IBMResponseParser.extractQueueTimeMs(response);
        System.assertEquals(12000, queueMs, 'Queue time should be 12000ms');
    }

    @IsTest
    static void testExtractQueueTimeMsNull() {
        System.assertEquals(null, IBMResponseParser.extractQueueTimeMs(null));
    }

    @IsTest
    static void testExtractQueueTimeMsNoTimestamps() {
        Map<String, Object> response = new Map<String, Object>{
            'status' => 'Completed'
        };
        System.assertEquals(
            null,
            IBMResponseParser.extractQueueTimeMs(response)
        );
    }

    @IsTest
    static void testExtractQueueTimeMsTimestampsNotMap() {
        Map<String, Object> response = new Map<String, Object>{
            'timestamps' => 'not-a-map'
        };
        System.assertEquals(
            null,
            IBMResponseParser.extractQueueTimeMs(response)
        );
    }

    @IsTest
    static void testExtractQueueTimeMsMissingRunning() {
        Map<String, Object> response = new Map<String, Object>{
            'timestamps' => new Map<String, Object>{
                'created' => '2026-03-17T10:00:00Z'
            }
        };
        System.assertEquals(
            null,
            IBMResponseParser.extractQueueTimeMs(response)
        );
    }

    @IsTest
    static void testExtractQueueTimeMsBadFormat() {
        Map<String, Object> response = new Map<String, Object>{
            'timestamps' => new Map<String, Object>{
                'created' => 'not-a-date',
                'running' => 'also-not-a-date'
            }
        };
        System.assertEquals(
            null,
            IBMResponseParser.extractQueueTimeMs(response)
        );
    }

    @IsTest
    static void testExtractQueueTimeMsBlankValues() {
        Map<String, Object> response = new Map<String, Object>{
            'timestamps' => new Map<String, Object>{
                'created' => '',
                'running' => ''
            }
        };
        System.assertEquals(
            null,
            IBMResponseParser.extractQueueTimeMs(response)
        );
    }
}
