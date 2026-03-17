@IsTest
private class QuantumRandomAssignment_Test {
    private class MockIBMApi implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getEndpoint().contains('iam.cloud.ibm.com')) {
                res.setBody(
                    '{"access_token":"test-token","token_type":"Bearer","expires_in":3600}'
                );
            } else {
                res.setBody('{"id":"job_flow_test","backend":"ibm_kingston"}');
            }
            return res;
        }
    }

    @IsTest
    static void testInvocableAction() {
        Test.setMock(HttpCalloutMock.class, new MockIBMApi());
        IBMQuantumAuth.cachedToken = 'test-token';
        IBMQuantumAuth.tokenExpiry = DateTime.now().addMinutes(30);

        QuantumRandomAssignment.AssignmentRequest req = new QuantumRandomAssignment.AssignmentRequest();
        req.recordIds = new List<String>{
            '001000000000001',
            '001000000000002'
        };
        req.assigneeIds = new List<String>{
            '005000000000001',
            '005000000000002'
        };
        req.assignmentType = 'Uniform';
        req.purpose = 'Test assignment';
        req.numQubits = 4;

        Test.startTest();
        List<QuantumRandomAssignment.AssignmentResult> results = QuantumRandomAssignment.execute(
            new List<QuantumRandomAssignment.AssignmentRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].jobId);
    }
}
