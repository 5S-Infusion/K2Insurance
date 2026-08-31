/**
 * @description Tests for AgentPayoutController — delegation to the service, the JSON write path,
 * and the two tiers of controlled UI errors.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private with sharing class AgentPayoutControllerTest {

    /**
     * @description Grants the running user the feature's permission set in its own transaction, so
     * every test method starts with field-level security on the newly deployed fields.
     */
    @testSetup
    static void grantFeatureAccess() {
        AgentPayoutTestData.grantAccess();
    }

    /**
     * @description getBoard returns the board the service builds.
     */
    @isTest
    static void getBoardReturnsTheBoard() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);

        Test.startTest();
        AgentPayoutService.BoardDto board = AgentPayoutController.getBoard();
        Test.stopTest();

        Assert.areEqual(1, board.agents.size(), 'The controller returns the agent row');
        Assert.areEqual(scenario.agent.Id, board.agents[0].agentId, 'The row is the test agent');
        Assert.areEqual(board.meta.periods.size(), board.agents[0].cells.size(),
            'The row carries one cell per period on the axis the meta declares');
    }

    /**
     * @description getAccess and getMethodOptions return the service's answers.
     */
    @isTest
    static void getAccessAndMethodOptionsReturnData() {
        AgentPayoutTestData.grantAccess();

        Test.startTest();
        AgentPayoutService.AccessDto access = AgentPayoutController.getAccess();
        List<Map<String, String>> options = AgentPayoutController.getMethodOptions();
        Test.stopTest();

        Assert.isNotNull(access, 'The controller returns an access answer');
        Assert.isTrue(access.canRead, 'A granted user may read the board');
        Assert.isFalse(options.isEmpty(), 'The controller returns the payment-method options');
    }

    /**
     * @description getLines returns the drill-down rows for the agent and periods asked for.
     */
    @isTest
    static void getLinesReturnsTheDrillDownRows() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 100.00, 50);

        Test.startTest();
        List<AgentPayoutService.LineDto> lines = AgentPayoutController.getLines(
            scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE }
        );
        Test.stopTest();

        Assert.areEqual(4, lines.size(), 'The controller returns every line in the period');
        Assert.areEqual(50.00, lines[0].payableAmount, 'Each line is valued at the policy rate');
    }

    /**
     * @description getPreflightJson deserializes the selection and hands back the server's
     * valuation as JSON, which parses into the shape the client is written against.
     */
    @isTest
    static void getPreflightJsonValuesTheSelection() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 100.00, 50);

        Test.startTest();
        String raw = AgentPayoutController.getPreflightJson(selectionJson(scenario.agent.Id));
        Test.stopTest();

        Assert.isNotNull(raw, 'The valuation comes back as a JSON string');
        AgentPayoutService.PreflightDto preflight = parsePreflight(raw);
        Assert.areEqual(scenario.agent.Id, preflight.agentId, 'The valuation names the agent');
        Assert.areEqual(4, preflight.lineCount, 'All four lines are payable');
        Assert.areEqual(400.00, preflight.linesNetAmount, 'The carrier net is computed server-side');
        Assert.areEqual(200.00, preflight.computedPayable, 'The payable is computed server-side');
        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, preflight.periodLabel,
            'A single-month selection is labelled with that month');
    }

    /**
     * @description createPayoutJson deserializes the payload, records the payout and stamps every
     * line it settles.
     */
    @isTest
    static void createPayoutJsonRecordsThePayout() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 22, 40.00, 50);
        AgentPayoutService.PreflightDto preflight =
            parsePreflight(AgentPayoutController.getPreflightJson(selectionJson(scenario.agent.Id)));
        Map<String, Object> payload = payoutPayload(scenario.agent.Id, preflight);
        payload.put('paidDate', String.valueOf(Date.today()));
        payload.put('paymentMethod', 'Zelle');
        payload.put('referenceNumber', 'ZL-9001');
        payload.put('notes', 'Recorded from the controller test');

        Test.startTest();
        Id payoutId = AgentPayoutController.createPayoutJson(JSON.serialize(payload));
        Test.stopTest();

        Assert.isNotNull(payoutId, 'The new payout id is returned');
        Assert.areEqual(22, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'Every line in the selection is stamped');
        Assert.areEqual(440.00, [
            SELECT Amount_Paid__c FROM Agent_Payout__c WHERE Id = :payoutId
        ].Amount_Paid__c, 'The amount paid is seeded from the computed payable');
    }

    /**
     * @description createPayoutJson carries the lines the user unticked through to the service, so
     * an exclusion survives the JSON hop the client has to make and the excluded lines stay unpaid.
     */
    @isTest
    static void createPayoutJsonHonoursExcludedLineIds() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 22, 40.00, 50);
        AgentPayoutService.PreflightDto preflight =
            parsePreflight(AgentPayoutController.getPreflightJson(selectionJson(scenario.agent.Id)));
        List<String> excluded = new List<String>{
            String.valueOf(preflight.payableLines[0].lineId),
            String.valueOf(preflight.payableLines[1].lineId)
        };
        Map<String, Object> payload = payoutPayload(scenario.agent.Id, preflight);
        payload.put('excludedLineIds', excluded);
        payload.put('expectedLineCount', 20);
        payload.put('expectedLinesNetAmount', 800.00);
        payload.put('expectedPayableAmount', 400.00);

        Test.startTest();
        Id payoutId = AgentPayoutController.createPayoutJson(JSON.serialize(payload));
        Test.stopTest();

        Assert.areEqual(22, preflight.payableLines.size(),
            'The valuation offered every open line before any was unticked');
        Assert.areEqual(20, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'Only the twenty included lines are stamped');
        Assert.areEqual(0, [
            SELECT COUNT() FROM Commission_Line__c WHERE Id IN :excluded AND Payout__c != null
        ], 'The two unticked lines are left unpaid');
        Agent_Payout__c payout = [
            SELECT Line_Count__c, Lines_Net_Amount__c, Amount_Paid__c
            FROM Agent_Payout__c WHERE Id = :payoutId
        ];
        Assert.areEqual(20, payout.Line_Count__c.intValue(),
            'The header counts only the lines it settled');
        Assert.areEqual(800.00, payout.Lines_Net_Amount__c,
            'The carrier net is the twenty included lines of 40.00');
        Assert.areEqual(400.00, payout.Amount_Paid__c,
            'The amount paid is seeded from the included payable');
    }

    /**
     * @description An empty or blank request object is refused outright. This is the server-side
     * defence against reactive component state arriving at Apex as an empty object, which would
     * otherwise record a payout against nobody and report success.
     */
    @isTest
    static void createPayoutJsonRejectsAnEmptyRequestObject() {
        Test.startTest();
        try {
            AgentPayoutController.createPayoutJson('{}');
            Assert.fail('An empty request object must be refused');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_AgentRequired, ex.getMessage(),
                'The agent-required refusal reaches the UI');
        }
        try {
            AgentPayoutController.createPayoutJson(null);
            Assert.fail('A null payload must be refused');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_AgentRequired, ex.getMessage(),
                'The agent-required refusal reaches the UI');
        }
        try {
            AgentPayoutController.createPayoutJson('   ');
            Assert.fail('A blank payload must be refused');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_AgentRequired, ex.getMessage(),
                'The agent-required refusal reaches the UI');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A refused request creates no payout');
    }

    /**
     * @description A payload whose echoed totals no longer match what the server recomputes is
     * refused through the controller, and nothing is written.
     */
    @isTest
    static void createPayoutJsonRefusesStaleTotals() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 100.00, 50);
        AgentPayoutService.PreflightDto preflight =
            parsePreflight(AgentPayoutController.getPreflightJson(selectionJson(scenario.agent.Id)));
        Map<String, Object> payload = payoutPayload(scenario.agent.Id, preflight);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, scenario.policy.Id, 2, 28.91
        );

        Test.startTest();
        try {
            AgentPayoutController.createPayoutJson(JSON.serialize(payload));
            Assert.fail('A save built on totals that have since moved must be refused');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The named refusal reaches the UI rather than a generic save error');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A refused save creates no payout');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c != null],
            'A refused save stamps no line');
    }

    /**
     * @description voidPayout delegates to the service and releases the lines.
     */
    @isTest
    static void voidPayoutReleasesTheLines() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService.PreflightDto preflight =
            parsePreflight(AgentPayoutController.getPreflightJson(selectionJson(scenario.agent.Id)));
        Id payoutId = AgentPayoutController.createPayoutJson(
            JSON.serialize(payoutPayload(scenario.agent.Id, preflight))
        );

        Test.startTest();
        AgentPayoutController.voidPayout(payoutId, 'Recorded against the wrong agent');
        Test.stopTest();

        Assert.areEqual('Voided', [
            SELECT Status__c FROM Agent_Payout__c WHERE Id = :payoutId
        ].Status__c, 'The payout is voided through the controller');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'The lines are released');
    }

    /**
     * @description A refusal the service can name reaches the user with that message rather than
     * being flattened into a generic failure.
     */
    @isTest
    static void controllerSurfacesTypedServiceRefusals() {
        AgentPayoutController.service = (AgentPayoutService) Test.createStub(
            AgentPayoutService.class, new TypedRefusalMock()
        );
        Id fakeAgentId = sentinelAgentId();
        String payload = selectionJson(fakeAgentId);

        Test.startTest();
        try {
            AgentPayoutController.createPayoutJson(payload);
            Assert.fail('createPayoutJson should surface the typed refusal');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The service\'s own refusal message reaches the UI, not a generic error');
        }
        try {
            AgentPayoutController.getPreflightJson(payload);
            Assert.fail('getPreflightJson should surface the typed refusal');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The service\'s own refusal message reaches the UI, not a generic error');
        }
        try {
            AgentPayoutController.voidPayout(fakeAgentId, 'reason');
            Assert.fail('voidPayout should surface the typed refusal');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The service\'s own refusal message reaches the UI, not a generic error');
        }
        try {
            AgentPayoutController.getLines(fakeAgentId, new List<String>{ AgentPayoutTestData.PERIOD_ONE });
            Assert.fail('getLines should surface the typed refusal');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The service\'s own refusal message reaches the UI, not a generic error');
        }
        Test.stopTest();
    }

    /**
     * @description An unexpected service failure is logged and surfaced as a controlled message, on
     * every entry point.
     */
    @isTest
    static void controllerLogsAndSurfacesUnexpectedFailures() {
        AgentPayoutController.service = (AgentPayoutService) Test.createStub(
            AgentPayoutService.class, new ThrowingServiceMock()
        );
        Id fakeAgentId = sentinelAgentId();
        String payload = selectionJson(fakeAgentId);

        Test.startTest();
        try {
            AgentPayoutController.getBoard();
            Assert.fail('getBoard should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_LoadError, ex.getMessage(),
                'A read failure surfaces as the generic load error');
        }
        try {
            AgentPayoutController.getAccess();
            Assert.fail('getAccess should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_LoadError, ex.getMessage(),
                'A read failure surfaces as the generic load error');
        }
        try {
            AgentPayoutController.getMethodOptions();
            Assert.fail('getMethodOptions should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_LoadError, ex.getMessage(),
                'A read failure surfaces as the generic load error');
        }
        try {
            AgentPayoutController.getLines(fakeAgentId, new List<String>{ AgentPayoutTestData.PERIOD_ONE });
            Assert.fail('getLines should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_LoadError, ex.getMessage(),
                'A read failure surfaces as the generic load error');
        }
        try {
            AgentPayoutController.getPreflightJson(payload);
            Assert.fail('getPreflightJson should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_LoadError, ex.getMessage(),
                'A read failure surfaces as the generic load error');
        }
        try {
            AgentPayoutController.createPayoutJson(payload);
            Assert.fail('createPayoutJson should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_SaveError, ex.getMessage(),
                'A write failure surfaces as the generic save error, not the load one');
        }
        try {
            AgentPayoutController.voidPayout(fakeAgentId, 'reason');
            Assert.fail('voidPayout should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.areEqual(Label.AgentManagement_SaveError, ex.getMessage(),
                'A write failure surfaces as the generic save error, not the load one');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A failed save leaves no payout behind');
    }

    /**
     * @description Builds the selection payload a client sends for a preflight.
     * @param agentId The agent to be paid.
     * @return The JSON payload.
     */
    private static String selectionJson(Id agentId) {
        return JSON.serialize(new Map<String, Object>{
            'agentId' => agentId,
            'periodStart' => AgentPayoutTestData.PERIOD_ONE,
            'periodEnd' => AgentPayoutTestData.PERIOD_ONE,
            'periods' => new List<String>{ AgentPayoutTestData.PERIOD_ONE }
        });
    }

    /**
     * @description Builds the write payload a client sends to record a payout, echoing back the
     * three totals the preflight reported.
     * @param agentId The agent to be paid.
     * @param preflight The valuation the payload is built on.
     * @return The payload, ready to be serialized.
     */
    private static Map<String, Object> payoutPayload(
        Id agentId, AgentPayoutService.PreflightDto preflight
    ) {
        return new Map<String, Object>{
            'agentId' => agentId,
            'periodStart' => preflight.periodStart,
            'periodEnd' => preflight.periodEnd,
            'periods' => preflight.periods,
            'expectedLineCount' => preflight.lineCount,
            'expectedLinesNetAmount' => preflight.linesNetAmount,
            'expectedPayableAmount' => preflight.computedPayable
        };
    }

    /**
     * @description Parses the JSON valuation the controller returns.
     * @param raw The JSON the controller returned.
     * @return The valuation.
     */
    private static AgentPayoutService.PreflightDto parsePreflight(String raw) {
        return (AgentPayoutService.PreflightDto) JSON.deserialize(
            raw, AgentPayoutService.PreflightDto.class
        );
    }

    /**
     * @description Builds an account id that names no record, for the tests that stub the service
     * out entirely and never reach the database. The key prefix is read from the describe rather
     * than written down, so nothing here depends on a literal id.
     * @return An account id that resolves to nothing.
     */
    private static Id sentinelAgentId() {
        return Id.valueOf(Account.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA');
    }

    /**
     * @description Stub whose every call fails the way the service refuses a request it understands.
     */
    private class TypedRefusalMock implements System.StubProvider {
        /**
         * @description Fails every stubbed call the way the service refuses a request it understands.
         * @param stubbedObject The stubbed service instance.
         * @param methodName The method that was called.
         * @param returnType The method's return type.
         * @param paramTypes The method's parameter types.
         * @param paramNames The method's parameter names.
         * @param args The arguments the call was made with.
         * @return Never returns; the call always refuses.
         */
        public Object handleMethodCall(
            Object stubbedObject, String methodName, Type returnType,
            List<Type> paramTypes, List<String> paramNames, List<Object> args
        ) {
            throw new AgentPayoutService.AgentPayoutException(Label.AgentManagement_StaleTotals);
        }
    }

    /**
     * @description Stub whose every call fails unexpectedly, to exercise the logged error tier.
     */
    private class ThrowingServiceMock implements System.StubProvider {
        /**
         * @description Fails every stubbed call the way an unforeseen system error would.
         * @param stubbedObject The stubbed service instance.
         * @param methodName The method that was called.
         * @param returnType The method's return type.
         * @param paramTypes The method's parameter types.
         * @param paramNames The method's parameter names.
         * @param args The arguments the call was made with.
         * @return Never returns; the call always fails.
         */
        public Object handleMethodCall(
            Object stubbedObject, String methodName, Type returnType,
            List<Type> paramTypes, List<String> paramNames, List<Object> args
        ) {
            throw new MockServiceException('Simulated service failure');
        }
    }

    /**
     * @description Generic failure used by the failing service stub.
     */
    private class MockServiceException extends Exception {}
}
