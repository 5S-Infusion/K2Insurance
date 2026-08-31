/**
 * @description Tests for AgentPayoutService — the board, the server-side valuation of a proposed
 * payout, recording and voiding a payout, and the access model.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private with sharing class AgentPayoutServiceTest {

    /**
     * @description Grants the running user the feature's permission set in its own transaction, so
     * every test method starts with field-level security on the newly deployed fields. A field
     * deployed by the Metadata API carries none of its own.
     */
    @testSetup
    static void grantFeatureAccess() {
        AgentPayoutTestData.grantAccess();
    }

    /**
     * @description Lines whose policy names no subagent belong to K2 and are out of scope: they are
     * never counted into a board row and never create one.
     */
    @isTest
    static void getBoardExcludesLinesWithNoSubagent() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        Insurance__c housePolicy = AgentPayoutTestData.createPolicy(
            'AP-HOUSE', scenario.carrier.Id, scenario.holder.Id, null, 50
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, housePolicy.Id, 5, 100.00
        );
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        Assert.areEqual(1, board.agents.size(), 'Only the subagent gets a board row');
        AgentPayoutService.AgentRowDto row = board.agents[0];
        Assert.areEqual(scenario.agent.Id, row.agentId, 'The row belongs to the subagent');
        Assert.areEqual(3, row.outstandingLineCount,
            'Only the three subagent lines are outstanding; the house lines are out of scope');
        Assert.areEqual(300.00, row.outstandingNet,
            'The house lines contribute nothing to the outstanding net');
    }

    /**
     * @description The board lays each agent out across the period axis with one cell per period in
     * axis order, carrying the cell state, the carrier net and the payable at the policy rate.
     */
    @isTest
    static void getBoardComputesCellStatesAndOutstandingTotals() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 25.00, 50);
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        Assert.areEqual(1, board.agents.size(), 'One agent has commission lines');
        Assert.areEqual(
            new List<String>{ AgentPayoutTestData.PERIOD_ONE }, board.meta.periods,
            'The axis covers the one period that has data');
        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, board.meta.latestPeriod,
            'The latest period is the only period');
        Assert.areEqual(1, board.meta.halves.size(),
            'The axis falls inside a single half-year bucket');

        AgentPayoutService.AgentRowDto row = board.agents[0];
        Assert.areEqual(board.meta.periods.size(), row.cells.size(),
            'The cells are dense: exactly one per period on the axis');
        AgentPayoutService.CellDto cell = cellFor(board, row, AgentPayoutTestData.PERIOD_ONE);
        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, cell.period,
            'The cell sits at the same index as its period on the axis');
        Assert.areEqual('UNPAID', cell.state, 'Unstamped lines in an unsettled period are unpaid');
        Assert.areEqual(4, cell.openLineCount, 'All four lines are open');
        Assert.areEqual(0, cell.paidLineCount, 'Nothing has been stamped');
        Assert.areEqual(4, cell.totalLineCount, 'The total is the open lines plus the paid ones');
        Assert.areEqual(100.00, cell.openNet, 'The carrier net is four lines of 25.00');
        Assert.areEqual(100.00, cell.totalNet, 'With nothing paid the total net is the open net');
        Assert.areEqual(50.00, cell.openPayable, 'The payable is that net at the policy rate of 50');
        Assert.areEqual(0, cell.openUnratedLineCount, 'Every line here carries a policy rate');
        Assert.areEqual(0.00, cell.openUnratedNet, 'So no carrier net sits behind a missing rate');
        Assert.isFalse(cell.covered, 'No payout declares this period settled');
        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, row.oldestUnpaidPeriod,
            'The only unpaid period is also the oldest');
        Assert.isFalse(row.hasLateLines, 'Nothing has been settled, so nothing arrived late');
        Assert.areEqual(0, row.lateLineCount, 'No line arrived into a settled period');
        Assert.isTrue(row.payouts.isEmpty(), 'The agent has no payout history yet');
        Assert.isNull(row.deltaPerMonth,
            'A single period is not enough history to compare half-years');
    }

    /**
     * @description Unstamped lines whose policy carries no rate are reported per cell as well as
     * per row, so the column shows what part of a month cannot be valued.
     */
    @isTest
    static void getBoardReportsUnratedLinesPerCell() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 2, 100.00, 50);
        Insurance__c unratedPolicy = AgentPayoutTestData.createPolicy(
            'AP-UNRATED-CELL', scenario.carrier.Id, scenario.holder.Id, scenario.agent.Id, null
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, unratedPolicy.Id, 3, 50.00
        );
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        AgentPayoutService.AgentRowDto row = board.agents[0];
        AgentPayoutService.CellDto cell = cellFor(board, row, AgentPayoutTestData.PERIOD_ONE);
        Assert.areEqual(5, cell.openLineCount, 'All five lines are open');
        Assert.areEqual(350.00, cell.openNet, 'The carrier net covers every open line');
        Assert.areEqual(100.00, cell.openPayable,
            'Only the two rated lines can be valued, at 50 percent of 200.00');
        Assert.areEqual(3, cell.openUnratedLineCount, 'Three of them have no policy rate');
        Assert.areEqual(150.00, cell.openUnratedNet, 'Their carrier net is reported, not guessed');
        Assert.areEqual(3, row.unratedLineCount, 'The row rolls the unrated cells up');
        Assert.areEqual(150.00, row.unratedNet, 'And their carrier net with them');
    }

    /**
     * @description A period whose open lines net to exactly zero is still unpaid on the board. This
     * is the real shape of a statement carrying two payments and two matching chargebacks, so the
     * money nets to nothing while four lines remain unsettled. A sum-based test would call the
     * month paid before a dollar had moved.
     */
    @isTest
    static void getBoardReadsAZeroSumPeriodAsUnpaid() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 2, 28.91, 50);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, scenario.policy.Id, 2, -28.91
        );
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        AgentPayoutService.AgentRowDto row = board.agents[0];
        AgentPayoutService.CellDto cell = cellFor(board, row, AgentPayoutTestData.PERIOD_ONE);
        Assert.areEqual(0.00, cell.openNet, 'The four lines net to exactly zero');
        Assert.areEqual(4, cell.openLineCount, 'Four lines are still unsettled');
        Assert.areEqual('UNPAID', cell.state,
            'Four unsettled lines that net to zero are unpaid, not paid');
        Assert.areEqual(0.00, row.outstandingNet, 'The outstanding money is nothing');
        Assert.areEqual(4, row.outstandingLineCount,
            'But four lines are still outstanding, which is what decides paid or unpaid');
    }

    /**
     * @description A line arriving into a period a payout already settled raises the late-arrival
     * state on the board and is counted in the row's late line count.
     */
    @isTest
    static void getBoardFlagsLateArrivalAfterAPayout() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 40.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        service.createPayout(requestFrom(preflight, null));
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, scenario.policy.Id, 2, 28.91
        );

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        AgentPayoutService.AgentRowDto row = board.agents[0];
        AgentPayoutService.CellDto cell = cellFor(board, row, AgentPayoutTestData.PERIOD_ONE);
        Assert.areEqual('LATE_LINES', cell.state,
            'Lines arriving into an already-settled period are late');
        Assert.isTrue(cell.covered, 'A Paid payout declares this period settled');
        Assert.isTrue(row.hasLateLines, 'The row is flagged as having late arrivals');
        Assert.areEqual(1, row.latePeriodCount, 'Exactly one period holds late arrivals');
        Assert.areEqual(2, row.lateLineCount, 'Two lines arrived after the period was settled');
        Assert.areEqual(3, cell.paidLineCount, 'The three settled lines are still counted as paid');
        Assert.areEqual(2, cell.openLineCount, 'The two late lines are still open');
        Assert.areEqual(5, cell.totalLineCount, 'The cell holds five lines in all');
    }

    /**
     * @description A payout may declare a range wider than the months that actually held lines. When
     * a line later arrives into one of those empty-but-settled months it is a late arrival, which
     * no comparison of amounts or dates could express — only the payout's declared range can.
     */
    @isTest
    static void getBoardFlagsLateLinesWhenTheCoveredPeriodWasEmpty() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        List<String> range = new List<String>{
            AgentPayoutTestData.PERIOD_ONE, AgentPayoutTestData.PERIOD_TWO
        };
        AgentPayoutService.PreflightDto preflight =
            service.getPreflight(selection(scenario.agent.Id, range));
        Assert.areEqual(3, preflight.lineCount,
            'Only the first period holds lines when the payout is recorded');
        service.createPayout(requestFrom(preflight, null));
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_TWO, scenario.policy.Id, 2, 45.00
        );

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        AgentPayoutService.AgentRowDto row = board.agents[0];
        AgentPayoutService.CellDto settled = cellFor(board, row, AgentPayoutTestData.PERIOD_ONE);
        AgentPayoutService.CellDto wasEmpty = cellFor(board, row, AgentPayoutTestData.PERIOD_TWO);
        Assert.areEqual('PAID', settled.state, 'The month that held the lines is settled');
        Assert.isTrue(wasEmpty.covered,
            'The second month is covered by the payout even though it was empty');
        Assert.areEqual(0, wasEmpty.paidLineCount, 'No line was ever stamped in that month');
        Assert.areEqual('LATE_LINES', wasEmpty.state,
            'Lines arriving into a settled but empty month are late arrivals');
        Assert.areEqual(2, row.lateLineCount, 'Both late lines are counted');
        Assert.areEqual(1, row.latePeriodCount, 'They sit in a single period');
    }

    /**
     * @description The row carries the agent's payout history, newest first, and the last payout's
     * date and amount.
     */
    @isTest
    static void getBoardCarriesThePayoutHistory() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_TWO, scenario.policy.Id, 4, 100.00
        );
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto first = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        AgentPayoutService.PayoutRequest earlier = requestFrom(first, null);
        earlier.paidDate = Date.today().addDays(-30);
        service.createPayout(earlier);
        AgentPayoutService.PreflightDto second = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_TWO })
        );
        Id secondPayoutId = service.createPayout(requestFrom(second, null));

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        AgentPayoutService.AgentRowDto row = board.agents[0];
        Assert.areEqual(2, row.payouts.size(), 'Both payouts are listed');
        Assert.areEqual(200.00, row.payouts[0].amountPaid,
            'The newest payout leads the history: four lines of 100.00 at 50 percent');
        Assert.areEqual(4, row.payouts[0].lineCount,
            'The summary keeps the line count the payout settled');
        Assert.areEqual('Paid', row.payouts[0].status, 'A live payout is Paid');
        Assert.areEqual(AgentPayoutTestData.PERIOD_TWO, row.payouts[0].periodLabel,
            'A single-month payout is labelled with that month');
        Assert.areEqual(secondPayoutId, row.lastPayoutId, 'The last payout is the newest one');
        Assert.areEqual(200.00, row.lastPaidAmount, 'The row carries what was last paid');
        Assert.areEqual(Date.today(), row.lastPaidDate, 'And when it was paid');
    }

    /**
     * @description A voided payout is not part of the history the board offers, because it no
     * longer settles anything.
     */
    @isTest
    static void getBoardOmitsVoidedPayoutsFromTheHistory() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Id payoutId = service.createPayout(requestFrom(preflight, null));
        service.voidPayout(payoutId, 'Recorded against the wrong agent');

        Test.startTest();
        AgentPayoutService.BoardDto board = service.getBoard();
        Test.stopTest();

        AgentPayoutService.AgentRowDto row = board.agents[0];
        Assert.isTrue(row.payouts.isEmpty(), 'A voided payout is not offered as history');
        Assert.isNull(row.lastPayoutId, 'And it is not the agent\'s last payout');
        AgentPayoutService.CellDto cell = cellFor(board, row, AgentPayoutTestData.PERIOD_ONE);
        Assert.isFalse(cell.covered, 'A voided payout settles nothing');
        Assert.areEqual('UNPAID', cell.state, 'The released lines are unpaid again');
        Assert.areEqual(3, cell.openLineCount, 'All three lines are open again');
    }

    /**
     * @description The payable is computed from the policy's commission rate, never from the
     * agent account's own default rate, and neither rate is written to.
     */
    @isTest
    static void payableUsesPolicyRateNotAccountRate() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Test.stopTest();

        Assert.areEqual(400.00, preflight.linesNetAmount, 'The carrier net is four lines of 100.00');
        Assert.areEqual(200.00, preflight.computedPayable,
            'The payable is the net at the policy rate of 50, not the account rate of 90');
        Assert.areEqual(90.00, [
            SELECT Commission_Rate__c FROM Account WHERE Id = :scenario.agent.Id
        ].Commission_Rate__c, 'The agent account rate is left untouched');
        Assert.areEqual(50.00, [
            SELECT Commission_Rate__c FROM Insurance__c WHERE Id = :scenario.policy.Id
        ].Commission_Rate__c, 'The policy rate is left untouched');
    }

    /**
     * @description Lines whose policy carries no commission rate cannot be valued: they contribute
     * nothing to the computed payable and are counted, totalled and listed separately instead.
     */
    @isTest
    static void unratedLinesAreCountedSeparatelyAndPayNothing() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 2, 100.00, 50);
        Insurance__c unratedPolicy = AgentPayoutTestData.createPolicy(
            'AP-UNRATED', scenario.carrier.Id, scenario.holder.Id, scenario.agent.Id, null
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, unratedPolicy.Id, 3, 50.00
        );
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Test.stopTest();

        Assert.areEqual(5, preflight.lineCount, 'All five lines are payable candidates');
        Assert.areEqual(350.00, preflight.linesNetAmount, 'The carrier net covers every line');
        Assert.areEqual(100.00, preflight.computedPayable,
            'Only the two rated lines can be valued, at 50 percent of 200.00');
        Assert.areEqual(3, preflight.unratedLineCount, 'Three lines have no policy rate');
        Assert.areEqual(150.00, preflight.unratedNetAmount,
            'Their carrier net is reported so it is visible rather than guessed at');
        Assert.areEqual(3, preflight.rateMissingLines.size(),
            'The three unvalued lines are listed so they can be paid by hand');
        for (AgentPayoutService.LineDto line : preflight.rateMissingLines) {
            Assert.isTrue(line.rateMissing, 'Every listed line is one with no policy rate');
            Assert.isNull(line.payableAmount, 'And none of them can be valued');
        }
    }

    /**
     * @description The valuation names the range it covers, lists the chargebacks inside it, and
     * lists the lines an earlier payout already settled.
     */
    @isTest
    static void getPreflightListsChargebacksAndAlreadyStampedLines() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_TWO, scenario.policy.Id, 4, 100.00
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_TWO, scenario.policy.Id, 2, -25.00
        );
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto first = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        service.createPayout(requestFrom(first, null));

        Test.startTest();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(selection(
            scenario.agent.Id,
            new List<String>{ AgentPayoutTestData.PERIOD_ONE, AgentPayoutTestData.PERIOD_TWO }
        ));
        Test.stopTest();

        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, preflight.periodStart,
            'The range starts at the first period selected');
        Assert.areEqual(AgentPayoutTestData.PERIOD_TWO, preflight.periodEnd,
            'And ends at the last');
        Assert.areEqual(
            AgentPayoutTestData.PERIOD_ONE + ' ~ ' + AgentPayoutTestData.PERIOD_TWO,
            preflight.periodLabel, 'A multi-month range is labelled from start to end');
        Assert.areEqual(6, preflight.lineCount, 'Only the six still-open lines are payable');
        Assert.areEqual(350.00, preflight.linesNetAmount,
            'Four payments of 100.00 less two chargebacks of 25.00');
        Assert.areEqual(-50.00, preflight.chargebackAmount, 'The chargebacks are reported apart');
        Assert.areEqual(2, preflight.chargebackLineCount, 'Two lines are chargebacks');
        Assert.areEqual(2, preflight.chargebackLines.size(), 'And both are listed');
        Assert.areEqual(3, preflight.alreadyStampedLineCount,
            'The three lines the first payout settled are reported');
        Assert.areEqual(3, preflight.alreadyStampedLines.size(), 'And listed');
        for (AgentPayoutService.LineDto line : preflight.alreadyStampedLines) {
            Assert.isTrue(line.paidOut, 'Every listed line already carries a payout');
        }
        Assert.areEqual(1, preflight.coveredPeriods.size(),
            'The first period is already settled by the earlier payout');
        Assert.areEqual(0, preflight.lateLineCount,
            'Nothing new arrived into the settled period, so nothing is late');
    }

    /**
     * @description A preflight with no agent is refused.
     */
    @isTest
    static void getPreflightRejectsAMissingAgent() {
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        try {
            service.getPreflight(
                selection(null, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
            );
            Assert.fail('Expected a typed exception for a preflight with no agent');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_AgentRequired, ex.getMessage(),
                'The agent-required message should reach the user');
        }
        try {
            service.getPreflight(null);
            Assert.fail('Expected a typed exception for a preflight with no request at all');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_AgentRequired, ex.getMessage(),
                'The agent-required message should reach the user');
        }
        Test.stopTest();
    }

    /**
     * @description A preflight with a malformed, empty, or self-contradicting period selection is
     * refused.
     */
    @isTest
    static void getPreflightRejectsAnInvalidPeriodSelection() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 1, 10.00, 50);
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        try {
            service.getPreflight(selection(scenario.agent.Id, new List<String>{ '2026-13' }));
            Assert.fail('Expected a typed exception for a malformed period');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_PeriodInvalid, ex.getMessage(),
                'The invalid-period message should reach the user');
        }
        try {
            service.getPreflight(selection(scenario.agent.Id, new List<String>()));
            Assert.fail('Expected a typed exception for an empty period selection');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_PeriodRequired, ex.getMessage(),
                'The period-required message should reach the user');
        }
        try {
            AgentPayoutService.PayoutRequest narrow = selection(
                scenario.agent.Id,
                new List<String>{ AgentPayoutTestData.PERIOD_ONE, AgentPayoutTestData.PERIOD_TWO }
            );
            narrow.periodEnd = AgentPayoutTestData.PERIOD_ONE;
            service.getPreflight(narrow);
            Assert.fail('Expected a typed exception for a range narrower than its own selection');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_PeriodInvalid, ex.getMessage(),
                'A payout may never claim to settle less than it is stamping');
        }
        Test.stopTest();
    }

    /**
     * @description When no amount is typed, the amount paid is seeded from the payable the server
     * computed, and the header records the whole valuation.
     */
    @isTest
    static void createPayoutSeedsAmountPaidFromComputedPayable() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );

        Test.startTest();
        Id payoutId = service.createPayout(requestFrom(preflight, null));
        Test.stopTest();

        Agent_Payout__c payout = [
            SELECT Agent__c, Period_Start__c, Period_End__c, Line_Count__c, Lines_Net_Amount__c,
                   Chargeback_Amount__c, Payable_Amount__c, Amount_Paid__c, Paid_Date__c,
                   Unrated_Line_Count__c, Unrated_Net_Amount__c, Status__c
            FROM Agent_Payout__c WHERE Id = :payoutId
        ];
        Assert.areEqual(scenario.agent.Id, payout.Agent__c, 'The payout belongs to the agent');
        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, payout.Period_Start__c,
            'The payout declares the period it covers');
        Assert.areEqual(AgentPayoutTestData.PERIOD_ONE, payout.Period_End__c,
            'A single-period payout starts and ends in the same period');
        Assert.areEqual(4, payout.Line_Count__c.intValue(), 'Four lines were settled');
        Assert.areEqual(400.00, payout.Lines_Net_Amount__c, 'The carrier net is recorded');
        Assert.areEqual(200.00, payout.Payable_Amount__c, 'The computed payable is recorded');
        Assert.areEqual(200.00, payout.Amount_Paid__c,
            'The amount paid is seeded from the computed payable');
        Assert.areEqual(Date.today(), payout.Paid_Date__c, 'The paid date defaults to today');
        Assert.areEqual('Paid', payout.Status__c, 'A new payout is Paid');
        Assert.areEqual(0, payout.Unrated_Line_Count__c.intValue(),
            'Every line here carries a policy rate');
    }

    /**
     * @description Every payable line in the selection is stamped with the payout, in bulk.
     */
    @isTest
    static void createPayoutStampsEveryPayableLine() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 25, 40.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );

        Test.startTest();
        Id payoutId = service.createPayout(requestFrom(preflight, null));
        Test.stopTest();

        Assert.areEqual(25, [
            SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId
        ], 'All twenty-five lines carry the payout stamp');
        Assert.areEqual(0, [
            SELECT COUNT() FROM Commission_Line__c
            WHERE Policy_Number__c = :scenario.policy.Id AND Payout__c = null
        ], 'No payable line is left unstamped');
        Assert.areEqual(500.00, [
            SELECT Payable_Amount__c FROM Agent_Payout__c WHERE Id = :payoutId
        ].Payable_Amount__c, 'Twenty-five lines of 40.00 at 50 percent pay 500.00');
    }

    /**
     * @description A line already stamped by an earlier payout is left alone; only the still-open
     * lines in the selection are settled by the new one.
     */
    @isTest
    static void createPayoutSkipsLinesAlreadyStampedByAnotherPayout() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 5, 100.00, 50);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_TWO, scenario.policy.Id, 6, 100.00
        );
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        AgentPayoutService.PreflightDto first = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Id firstPayoutId = service.createPayout(requestFrom(first, null));
        AgentPayoutService.PreflightDto second = service.getPreflight(selection(
            scenario.agent.Id,
            new List<String>{ AgentPayoutTestData.PERIOD_ONE, AgentPayoutTestData.PERIOD_TWO }
        ));
        Id secondPayoutId = service.createPayout(requestFrom(second, null));
        Test.stopTest();

        Assert.areEqual(5, second.alreadyStampedLineCount,
            'The preflight reports the five lines an earlier payout already settled');
        Assert.areEqual(6, second.lineCount, 'Only the six still-open lines are payable');
        Assert.areEqual(5, [
            SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :firstPayoutId
        ], 'The first payout keeps its five lines');
        Assert.areEqual(6, [
            SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :secondPayoutId
        ], 'The second payout settles only the six lines that were still open');
        Assert.areEqual(6, [
            SELECT Line_Count__c FROM Agent_Payout__c WHERE Id = :secondPayoutId
        ].Line_Count__c.intValue(), 'The header records only the lines it actually settled');
    }

    /**
     * @description When the data has moved since the client reviewed it, the totals it echoes back
     * no longer match the server's own recomputation, the save is refused, and nothing at all is
     * written.
     */
    @isTest
    static void createPayoutRejectsWhenTheEchoedTotalsAreStale() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, scenario.policy.Id, 2, 28.91
        );

        Test.startTest();
        try {
            service.createPayout(requestFrom(preflight, null));
            Assert.fail('Expected a typed exception for totals that have since moved');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The stale-totals message should reach the user');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A refused save creates no payout');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c != null],
            'A refused save stamps no line');
    }

    /**
     * @description A request that carries no expected totals at all is refused too. This is what an
     * empty reactive-state object collapses to on its way to Apex, and it must never be saved
     * against numbers nobody has seen.
     */
    @isTest
    static void createPayoutRejectsWhenTheExpectedTotalsAreMissing() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PayoutRequest request =
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE });

        Test.startTest();
        try {
            service.createPayout(request);
            Assert.fail('Expected a typed exception when no totals are echoed back');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The stale-totals message should reach the user');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A refused save creates no payout');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c != null],
            'A refused save stamps no line');
    }

    /**
     * @description If the line stamp fails, the payout header it was written against is rolled back
     * with it — a payout never exists without the lines it settled.
     */
    @isTest
    static void createPayoutRollsBackEverythingWhenTheStampFails() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 22, 40.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        service.stampFailureInjected = true;

        Test.startTest();
        try {
            service.createPayout(requestFrom(preflight, null));
            Assert.fail('Expected the injected stamp failure to abort the save');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.isNotNull(ex.getMessage(), 'The failure is reported, not swallowed');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'The payout header is rolled back with the failed stamp');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c != null],
            'No line is left stamped');
    }

    /**
     * @description A selection that nets negative is a real situation in the data, so recording it
     * must be possible. No carry-forward is created; the lines are simply settled.
     */
    @isTest
    static void createPayoutAllowsNegativeNet() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 4, -50.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );

        Test.startTest();
        Id payoutId = service.createPayout(requestFrom(preflight, null));
        Test.stopTest();

        Agent_Payout__c payout = [
            SELECT Lines_Net_Amount__c, Chargeback_Amount__c, Payable_Amount__c, Amount_Paid__c
            FROM Agent_Payout__c WHERE Id = :payoutId
        ];
        Assert.areEqual(4, preflight.chargebackLineCount, 'Every line here is a chargeback');
        Assert.areEqual(-200.00, payout.Lines_Net_Amount__c, 'The carrier net is negative');
        Assert.areEqual(-200.00, payout.Chargeback_Amount__c,
            'Every line here is a chargeback, so the chargeback total is the whole net');
        Assert.areEqual(-100.00, payout.Payable_Amount__c, 'The payable is negative too');
        Assert.areEqual(-100.00, payout.Amount_Paid__c,
            'A negative payout can be recorded without a validation rule blocking it');
        Assert.areEqual(4, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'The chargeback lines are settled by the payout');
    }

    /**
     * @description Recording a payout over a selection that holds no open line is refused.
     */
    @isTest
    static void createPayoutRefusesWhenThereIsNothingToPay() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        service.createPayout(requestFrom(preflight, null));

        Test.startTest();
        try {
            service.createPayout(requestFrom(preflight, null));
            Assert.fail('Expected a typed exception when nothing is left to pay');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_NothingToPay, ex.getMessage(),
                'The nothing-to-pay message should reach the user');
        }
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Agent_Payout__c],
            'The refused second attempt creates no extra payout');
    }

    /**
     * @description The valuation offers every open line as payable, so the review modal can open
     * with all of them ticked. A line an earlier payout already settled is reported separately and
     * is never offered, because it is not the current payout's to settle.
     */
    @isTest
    static void getPreflightReturnsEveryOpenLineAsPayable() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 8, 100.00, 50);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_TWO, scenario.policy.Id, 12, 100.00
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_THREE, scenario.policy.Id, 6, 100.00
        );
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto settled = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        service.createPayout(requestFrom(settled, null));

        Test.startTest();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(selection(
            scenario.agent.Id,
            new List<String>{
                AgentPayoutTestData.PERIOD_ONE, AgentPayoutTestData.PERIOD_TWO,
                AgentPayoutTestData.PERIOD_THREE
            }
        ));
        Test.stopTest();

        Assert.areEqual(18, preflight.payableLines.size(),
            'Every one of the eighteen still-open lines is offered as payable');
        Assert.areEqual(preflight.lineCount, preflight.payableLines.size(),
            'The payable list and the line count describe the same set of lines');
        Set<Id> stampedIds = new Set<Id>();
        for (AgentPayoutService.LineDto line : preflight.alreadyStampedLines) {
            stampedIds.add(line.lineId);
        }
        Assert.areEqual(8, stampedIds.size(),
            'The eight lines the earlier payout settled are reported separately');
        String previousKey = '';
        for (AgentPayoutService.LineDto line : preflight.payableLines) {
            Assert.isFalse(line.paidOut, 'Every offered line is still open');
            Assert.isNull(line.payoutId, 'And carries no payout stamp');
            Assert.isFalse(stampedIds.contains(line.lineId),
                'A line another payout already settled is never offered as selectable');
            String key = line.period + '|' + line.lineName;
            Assert.isTrue(key.compareTo(previousKey) >= 0,
                'The payable lines are listed by period, then by line name');
            previousKey = key;
        }
    }

    /**
     * @description A line the user unticked is left unpaid: it keeps no stamp, it is not counted,
     * and every other line in the selection is settled exactly as it would have been.
     */
    @isTest
    static void createPayoutSkipsExcludedLines() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 25, 40.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Set<Id> excluded = firstLineIds(preflight.payableLines, 5);

        Test.startTest();
        Id payoutId = service.createPayout(requestExcluding(preflight, excluded));
        Test.stopTest();

        Assert.areEqual(25, preflight.payableLines.size(),
            'All twenty-five lines were offered before any was unticked');
        Assert.areEqual(20, [
            SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId
        ], 'Exactly the twenty included lines carry the payout stamp');
        Assert.areEqual(0, [
            SELECT COUNT() FROM Commission_Line__c
            WHERE Id IN :excluded AND Payout__c != null
        ], 'None of the five unticked lines was stamped');
        Assert.areEqual(5, [
            SELECT COUNT() FROM Commission_Line__c WHERE Id IN :excluded AND Payout__c = null
        ], 'All five unticked lines are still unpaid and will come back next period');
        Assert.areEqual(20, [
            SELECT Line_Count__c FROM Agent_Payout__c WHERE Id = :payoutId
        ].Line_Count__c.intValue(), 'The header counts only what it settled');
    }

    /**
     * @description The header snapshots the money of the included lines only. A payout that
     * recorded the pre-exclusion figures would overstate what was paid and leave the excluded lines
     * looking settled in every later reconciliation.
     */
    @isTest
    static void createPayoutSnapshotsOnlyTheIncludedLines() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 20, 100.00, 50);
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, scenario.policy.Id, 4, -25.00
        );
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Set<Id> excluded = new Set<Id>();
        excluded.addAll(firstLineIds(chargebacksOf(preflight.payableLines, true), 2));
        excluded.addAll(firstLineIds(chargebacksOf(preflight.payableLines, false), 2));

        Test.startTest();
        Id payoutId = service.createPayout(requestExcluding(preflight, excluded));
        Test.stopTest();

        Agent_Payout__c payout = [
            SELECT Line_Count__c, Lines_Net_Amount__c, Chargeback_Amount__c, Payable_Amount__c,
                   Amount_Paid__c, Unrated_Line_Count__c, Unrated_Net_Amount__c
            FROM Agent_Payout__c WHERE Id = :payoutId
        ];
        Assert.areEqual(1900.00, preflight.linesNetAmount,
            'The valuation opens on every line, which is the everything-included default');
        Assert.areEqual(4, excluded.size(), 'Two payments and two chargebacks were unticked');
        Assert.areEqual(20, payout.Line_Count__c.intValue(),
            'Twenty of the twenty-four lines were settled');
        Assert.areEqual(1750.00, payout.Lines_Net_Amount__c,
            'The carrier net is eighteen payments of 100.00 less two chargebacks of 25.00');
        Assert.areEqual(-50.00, payout.Chargeback_Amount__c,
            'Only the two included chargebacks are recorded, not all four');
        Assert.areEqual(875.00, payout.Payable_Amount__c,
            'The payable is the included net at the policy rate of 50');
        Assert.areEqual(875.00, payout.Amount_Paid__c,
            'The amount paid is seeded from the included payable, not the full selection');
        Assert.areEqual(0, payout.Unrated_Line_Count__c.intValue(),
            'Every included line carries a policy rate');
        Assert.areEqual(0.00, payout.Unrated_Net_Amount__c,
            'So no included carrier net sits behind a missing rate');
    }

    /**
     * @description Unticking every line leaves nothing to settle, so the payout is refused outright
     * rather than being recorded as an empty payment.
     */
    @isTest
    static void createPayoutWithEveryLineExcludedRefuses() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 21, 60.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Set<Id> excluded = firstLineIds(preflight.payableLines, preflight.payableLines.size());

        Test.startTest();
        try {
            service.createPayout(requestExcluding(preflight, excluded));
            Assert.fail('Expected a typed exception when every line has been unticked');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_NothingToPay, ex.getMessage(),
                'The nothing-to-pay message should reach the user');
        }
        Test.stopTest();

        Assert.areEqual(21, excluded.size(), 'Every one of the twenty-one lines was unticked');
        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A payout with nothing included is never created');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c != null],
            'And no line is stamped');
    }

    /**
     * @description An exclusion naming a line that is not in the selection — a stale id from an
     * earlier view, or a blank one — is ignored rather than refused, so every real line is still
     * settled.
     */
    @isTest
    static void createPayoutIgnoresUnknownExcludedIds() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 22, 40.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        AgentPayoutService.PayoutRequest request = requestFrom(preflight, null);
        request.excludedLineIds = new List<Id>{ scenario.agent.Id, null };

        Test.startTest();
        Id payoutId = service.createPayout(request);
        Test.stopTest();

        Assert.isNotNull(payoutId, 'An exclusion naming nothing real does not refuse the payout');
        Assert.areEqual(22, [
            SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId
        ], 'Every real line in the selection is still stamped');
        Assert.areEqual(22, [
            SELECT Line_Count__c FROM Agent_Payout__c WHERE Id = :payoutId
        ].Line_Count__c.intValue(), 'And the header counts all of them');
        Assert.areEqual(440.00, [
            SELECT Payable_Amount__c FROM Agent_Payout__c WHERE Id = :payoutId
        ].Payable_Amount__c, 'Twenty-two lines of 40.00 at 50 percent pay 440.00');
    }

    /**
     * @description A request that carries exclusions but echoes back the totals of the whole
     * selection is refused. This is the shape an exclusion the server never received would take,
     * and refusing it is what stops a silent overpayment.
     */
    @isTest
    static void createPayoutRejectsWhenExpectedTotalsIgnoreTheExclusion() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 20, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        AgentPayoutService.PayoutRequest request = requestFrom(preflight, null);
        request.excludedLineIds = new List<Id>(firstLineIds(preflight.payableLines, 3));

        Test.startTest();
        try {
            service.createPayout(request);
            Assert.fail('Expected a typed exception for totals computed over the full selection');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_StaleTotals, ex.getMessage(),
                'The stale-totals message should reach the user');
        }
        Test.stopTest();

        Assert.areEqual(2000.00, request.expectedLinesNetAmount,
            'The request echoed the pre-exclusion carrier net');
        Assert.areEqual(0, [SELECT COUNT() FROM Agent_Payout__c],
            'A refused save creates no payout');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c != null],
            'And stamps no line, so nothing was overpaid');
    }

    /**
     * @description Voiding a payout releases every line it stamped so they become payable again,
     * and keeps the header as the record of the reversal.
     */
    @isTest
    static void voidPayoutNullsPayoutOnEveryLineAndKeepsTheHeader() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 22, 40.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Id payoutId = service.createPayout(requestFrom(preflight, null));

        Test.startTest();
        service.voidPayout(payoutId, 'Paid by mistake, cheque cancelled');
        Test.stopTest();

        Agent_Payout__c payout = [
            SELECT Status__c, Notes__c, Line_Count__c, Amount_Paid__c
            FROM Agent_Payout__c WHERE Id = :payoutId
        ];
        Assert.areEqual('Voided', payout.Status__c, 'The payout is marked Voided');
        Assert.isTrue(payout.Notes__c.contains('[VOIDED'),
            'The note carries a machine-readable void marker');
        Assert.isTrue(payout.Notes__c.contains('Paid by mistake'),
            'The note carries the reason that was given');
        Assert.areEqual(22, payout.Line_Count__c.intValue(),
            'The header keeps the snapshot of what it settled');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'Every line is released from the voided payout');
        Assert.areEqual(22, [
            SELECT COUNT() FROM Commission_Line__c
            WHERE Policy_Number__c = :scenario.policy.Id AND Payout__c = null
        ], 'All twenty-two lines are payable again');
    }

    /**
     * @description Voiding without a reason is refused and changes nothing.
     */
    @isTest
    static void voidPayoutRequiresAReason() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Id payoutId = service.createPayout(requestFrom(preflight, null));

        Test.startTest();
        try {
            service.voidPayout(payoutId, '   ');
            Assert.fail('Expected a typed exception for a void with no reason');
        } catch (AgentPayoutService.AgentPayoutException ex) {
            Assert.areEqual(Label.AgentManagement_VoidReasonRequired, ex.getMessage(),
                'The reason-required message should reach the user');
        }
        Test.stopTest();

        Assert.areEqual('Paid', [SELECT Status__c FROM Agent_Payout__c WHERE Id = :payoutId].Status__c,
            'The payout is untouched');
        Assert.areEqual(3, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'The lines stay stamped');
    }

    /**
     * @description Voiding twice is harmless: the second call neither re-stamps the note nor
     * changes the outcome.
     */
    @isTest
    static void voidPayoutIsIdempotent() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Id payoutId = service.createPayout(requestFrom(preflight, null));

        Test.startTest();
        service.voidPayout(payoutId, 'Cheque cancelled');
        service.voidPayout(payoutId, 'Cheque cancelled again');
        Test.stopTest();

        Agent_Payout__c payout = [SELECT Status__c, Notes__c FROM Agent_Payout__c WHERE Id = :payoutId];
        Assert.areEqual('Voided', payout.Status__c, 'The payout stays Voided');
        Assert.isFalse(payout.Notes__c.contains('again'),
            'A second void does not re-stamp the note');
        Assert.areEqual(0, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'No line is stamped by the voided payout');
    }

    /**
     * @description Reassigning a policy's subagent after its lines were paid must not brick those
     * lines. The stamp rule only fires when the stamp itself is being set, so the live subagent
     * sync can keep rewriting the policy without every future save on the line failing.
     */
    @isTest
    static void changingSubagentAfterPayoutDoesNotBrickTheLine() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.PreflightDto preflight = service.getPreflight(
            selection(scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE })
        );
        Id payoutId = service.createPayout(requestFrom(preflight, null));
        Account replacement = AgentPayoutTestData.createAgent('Agent Replacement', 'Successor', 70);

        Test.startTest();
        update new Insurance__c(Id = scenario.policy.Id, Subagent__c = replacement.Id);
        List<Commission_Line__c> stamped = [
            SELECT Id, Payout__c FROM Commission_Line__c WHERE Payout__c = :payoutId
        ];
        for (Commission_Line__c line : stamped) {
            line.Commission_Date__c = Date.today().addDays(-1);
        }
        update stamped;
        Test.stopTest();

        Assert.areEqual(3, stamped.size(), 'The three settled lines are still stamped');
        Assert.areEqual(3, [SELECT COUNT() FROM Commission_Line__c WHERE Payout__c = :payoutId],
            'Reassigning the policy leaves the payout stamp in place');
        Assert.areEqual(replacement.Id, [
            SELECT Subagent__c FROM Insurance__c WHERE Id = :scenario.policy.Id
        ].Subagent__c, 'The policy now names the replacement subagent');
    }

    /**
     * @description The drill-down never returns the object's hyperlink formula fields, which carry
     * raw anchor markup, and it values each line at its own policy rate.
     */
    @isTest
    static void getLinesNeverReturnsHtmlFormulaFields() {
        AgentPayoutTestData.Scenario scenario =
            AgentPayoutTestData.build(AgentPayoutTestData.PERIOD_ONE, 3, 100.00, 50);
        Insurance__c unratedPolicy = AgentPayoutTestData.createPolicy(
            'AP-UNRATED-LINES', scenario.carrier.Id, scenario.holder.Id, scenario.agent.Id, null
        );
        AgentPayoutTestData.addLines(
            scenario, AgentPayoutTestData.PERIOD_ONE, unratedPolicy.Id, 2, 60.00
        );
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        List<AgentPayoutService.LineDto> lines = service.getLines(
            scenario.agent.Id, new List<String>{ AgentPayoutTestData.PERIOD_ONE }
        );
        Test.stopTest();

        Assert.areEqual(5, lines.size(), 'Every line in the period is listed');
        Integer rated = 0;
        Integer unrated = 0;
        for (AgentPayoutService.LineDto line : lines) {
            String rendered = String.valueOf(line.lineName) + String.valueOf(line.policyName)
                + String.valueOf(line.clientName) + String.valueOf(line.clientCompany)
                + String.valueOf(line.carrierName) + String.valueOf(line.payoutName)
                + String.valueOf(line.period);
            Assert.isFalse(rendered.contains('<a '),
                'No returned value may carry anchor markup from a hyperlink formula field');
            Assert.isFalse(rendered.containsIgnoreCase('href'),
                'No returned value may carry a hyperlink attribute');
            if (line.rateMissing) {
                unrated++;
                Assert.isNull(line.payableAmount, 'A line with no policy rate cannot be valued');
            } else {
                rated++;
                Assert.areEqual(50.00, line.payableAmount, '100.00 at 50 percent pays 50.00');
            }
        }
        Assert.areEqual(3, rated, 'Three lines sit on the rated policy');
        Assert.areEqual(2, unrated, 'Two lines sit on the policy with no rate');
        Assert.areEqual(scenario.carrier.Name, lines[0].carrierName,
            'The carrier comes from the statement that issued the line');
        Assert.areEqual(scenario.holder.LastName, lines[0].clientName,
            'The client comes from the policy holder, not from a hyperlink formula');
    }

    /**
     * @description A user who has not been granted the feature is offered nothing, so the UI can
     * degrade rather than start a save it cannot finish.
     */
    @isTest
    static void getAccessOffersNothingToAnUngrantedUser() {
        AgentPayoutTestData.grantAccess();
        User restricted = AgentPayoutTestData.createRestrictedUser('apagt');
        AgentPayoutService service = new AgentPayoutService();
        AgentPayoutService.AccessDto granted = service.getAccess();
        AgentPayoutService.AccessDto ungranted;

        Test.startTest();
        System.runAs(restricted) {
            ungranted = service.getAccess();
        }
        Test.stopTest();

        Assert.isTrue(granted.canRead, 'A granted user can read the board');
        Assert.isTrue(granted.canRecord,
            'A granted user may both create a payout and stamp the lines it settles');
        Assert.isTrue(granted.canVoid,
            'A granted user may both update a payout and unstamp the lines it held');
        Assert.isFalse(ungranted.canRead, 'An ungranted user cannot read the board');
        Assert.isFalse(ungranted.canRecord, 'An ungranted user is offered no payout action');
        Assert.isFalse(ungranted.canVoid, 'An ungranted user is offered no void action');
    }

    /**
     * @description The payment-method options come from the picklist, so the form and the field
     * cannot drift apart.
     */
    @isTest
    static void getMethodOptionsReturnsTheActivePicklistValues() {
        AgentPayoutService service = new AgentPayoutService();

        Test.startTest();
        List<Map<String, String>> options = service.getMethodOptions();
        Test.stopTest();

        Assert.isFalse(options.isEmpty(), 'The payment-method picklist has options');
        Set<String> values = new Set<String>();
        for (Map<String, String> option : options) {
            values.add(option.get('value'));
        }
        Assert.isTrue(values.contains('Check'), 'Cheque is one of the payment methods');
        Assert.isTrue(values.contains('Other'), 'Other is one of the payment methods');
    }

    /**
     * @description Finds the cell a row holds for one period, proving the cells are dense and in
     * axis order rather than looking the period up by key.
     * @param board The board the row came from.
     * @param row The agent row.
     * @param period The payment period.
     * @return The cell at that period's index on the axis.
     */
    private static AgentPayoutService.CellDto cellFor(
        AgentPayoutService.BoardDto board, AgentPayoutService.AgentRowDto row, String period
    ) {
        Integer index = board.meta.periods.indexOf(period);
        Assert.isTrue(index >= 0, 'The period ' + period + ' must be on the board axis');
        Assert.areEqual(board.meta.periods.size(), row.cells.size(),
            'The cells must be dense: one per period on the axis');
        AgentPayoutService.CellDto cell = row.cells[index];
        Assert.areEqual(period, cell.period, 'The cell must sit at its own period\'s index');
        return cell;
    }

    /**
     * @description Builds the selection a client sends for a preflight.
     * @param agentId The agent to be paid.
     * @param periods The payment periods selected.
     * @return The request.
     */
    private static AgentPayoutService.PayoutRequest selection(Id agentId, List<String> periods) {
        AgentPayoutService.PayoutRequest request = new AgentPayoutService.PayoutRequest();
        request.agentId = agentId;
        request.periods = periods;
        return request;
    }

    /**
     * @description Builds a payout request from a preflight, echoing back the three totals the
     * server computed so the save can be checked against them.
     * @param preflight The valuation the request is based on.
     * @param amountPaid The amount actually paid, or null to let the server seed it.
     * @return The request.
     */
    private static AgentPayoutService.PayoutRequest requestFrom(
        AgentPayoutService.PreflightDto preflight, Decimal amountPaid
    ) {
        AgentPayoutService.PayoutRequest request = new AgentPayoutService.PayoutRequest();
        request.agentId = preflight.agentId;
        request.periodStart = preflight.periodStart;
        request.periodEnd = preflight.periodEnd;
        request.periods = preflight.periods;
        request.expectedLineCount = preflight.lineCount;
        request.expectedLinesNetAmount = preflight.linesNetAmount;
        request.expectedPayableAmount = preflight.computedPayable;
        request.amountPaid = amountPaid;
        request.paidDate = Date.today();
        request.paymentMethod = 'Check';
        request.referenceNumber = '1001';
        request.notes = 'Recorded by the payout tests';
        return request;
    }

    /**
     * @description Builds a payout request that holds some lines back, echoing back the totals of
     * the included lines only — which is what the review modal computes as boxes are unticked.
     * @param preflight The valuation the request is based on.
     * @param excludedLineIds The lines the user unticked.
     * @return The request.
     */
    private static AgentPayoutService.PayoutRequest requestExcluding(
        AgentPayoutService.PreflightDto preflight, Set<Id> excludedLineIds
    ) {
        AgentPayoutService.PayoutRequest request = requestFrom(preflight, null);
        request.excludedLineIds = new List<Id>(excludedLineIds);
        Integer lineCount = 0;
        Decimal net = 0;
        Decimal payable = 0;
        for (AgentPayoutService.LineDto line : preflight.payableLines) {
            if (excludedLineIds.contains(line.lineId)) {
                continue;
            }
            lineCount++;
            net += line.commissionAmount == null ? 0 : line.commissionAmount;
            payable += line.payableAmount == null ? 0 : line.payableAmount;
        }
        request.expectedLineCount = lineCount;
        request.expectedLinesNetAmount = net.setScale(2, System.RoundingMode.HALF_UP);
        request.expectedPayableAmount = payable.setScale(2, System.RoundingMode.HALF_UP);
        return request;
    }

    /**
     * @description Takes the ids of the first few lines of a list, standing in for the boxes a user
     * unticks in the review modal.
     * @param lines The lines offered as payable.
     * @param howMany How many of them to untick.
     * @return The line ids to exclude.
     */
    private static Set<Id> firstLineIds(List<AgentPayoutService.LineDto> lines, Integer howMany) {
        Set<Id> excluded = new Set<Id>();
        for (AgentPayoutService.LineDto line : lines) {
            if (excluded.size() >= howMany) {
                break;
            }
            excluded.add(line.lineId);
        }
        return excluded;
    }

    /**
     * @description Splits payable lines into the chargebacks and the payments, so a test can untick
     * some of each and prove the money on the header follows the included set.
     * @param lines The lines offered as payable.
     * @param wantChargebacks True for the negative lines, false for the positive ones.
     * @return The matching lines, in the order they were offered.
     */
    private static List<AgentPayoutService.LineDto> chargebacksOf(
        List<AgentPayoutService.LineDto> lines, Boolean wantChargebacks
    ) {
        List<AgentPayoutService.LineDto> matched = new List<AgentPayoutService.LineDto>();
        for (AgentPayoutService.LineDto line : lines) {
            Boolean isChargeback = line.commissionAmount != null && line.commissionAmount < 0;
            if (isChargeback == wantChargebacks) {
                matched.add(line);
            }
        }
        return matched;
    }
}
