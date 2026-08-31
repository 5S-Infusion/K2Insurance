/**
 * @description Tests for AgentPayoutCalculator — the cell state machine, payment-period arithmetic,
 * half-year bucketing and the policy-rate payable calculation.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class AgentPayoutCalculatorTest {

    // The state machine never touches the database, so the agents it is told about need only be
    // well-formed ids. The account key prefix is read from the describe rather than written down.
    private static final Id AGENT_ID =
        Id.valueOf(Account.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
    private static final Id OTHER_AGENT_ID =
        Id.valueOf(Account.SObjectType.getDescribe().getKeyPrefix() + '000000000002AAA');

    /**
     * @description Every combination of the state machine's four inputs resolves to exactly one
     * state, in the documented order of precedence, with no gap and no throw.
     */
    @isTest
    static void evaluateIsTotalAcrossEveryInputCombination() {
        List<Integer> openCounts = new List<Integer>{ 0, 1, 5 };
        List<Integer> paidCounts = new List<Integer>{ 0, 1, 5 };
        List<Decimal> nets = new List<Decimal>{ -25.00, 0, 25.00 };
        List<Boolean> coverages = new List<Boolean>{ false, true };
        Integer combinations = 0;

        Test.startTest();
        for (Integer open : openCounts) {
            for (Integer paid : paidCounts) {
                for (Decimal net : nets) {
                    for (Boolean covered : coverages) {
                        combinations++;
                        AgentPayoutCalculator.CellState actual =
                            AgentPayoutCalculator.evaluate(open, paid, net, covered);
                        Assert.isNotNull(actual,
                            'evaluate must return a state for open=' + open + ' paid=' + paid +
                            ' net=' + net + ' covered=' + covered);
                        Assert.areEqual(expectedState(open, paid, net, covered), actual,
                            'Unexpected state for open=' + open + ' paid=' + paid +
                            ' net=' + net + ' covered=' + covered);
                    }
                }
            }
        }
        Test.stopTest();

        Assert.areEqual(54, combinations, 'The sweep must cover all 54 input combinations');
    }

    /**
     * @description The state machine tolerates null counts, a null net and a null coverage flag.
     */
    @isTest
    static void evaluateHandlesNullInputs() {
        Test.startTest();
        AgentPayoutCalculator.CellState empty =
            AgentPayoutCalculator.evaluate(null, null, null, null);
        AgentPayoutCalculator.CellState openOnly =
            AgentPayoutCalculator.evaluate(3, null, null, null);
        Test.stopTest();

        Assert.areEqual(AgentPayoutCalculator.CellState.NO_DATA, empty,
            'All-null inputs describe a cell with nothing in it');
        Assert.areEqual(AgentPayoutCalculator.CellState.UNPAID, openOnly,
            'Open lines with an unknown net are still unpaid');
    }

    /**
     * @description A period whose open lines net to exactly zero is still unpaid. This is the real
     * statement shape of two payments and two matching chargebacks: the money nets to nothing while
     * four lines remain unsettled, so a sum-based test would call it paid before a dollar moved.
     */
    @isTest
    static void cellStateIsUnpaidWhenOpenNetIsExactlyZero() {
        Decimal net = 28.91 + 28.91 - 28.91 - 28.91;

        Test.startTest();
        AgentPayoutCalculator.CellState state = AgentPayoutCalculator.evaluate(4, 0, net, false);
        Test.stopTest();

        Assert.isTrue(net == 0, 'The four lines must net to exactly zero');
        Assert.areEqual(AgentPayoutCalculator.CellState.UNPAID, state,
            'Four unsettled lines that net to zero are unpaid, not paid');
    }

    /**
     * @description A line arriving into a period a payout already declared settled raises the
     * late-arrival state. Nothing about the amounts, the dates or the counts alone can express this
     * — it needs the payout's declared range.
     */
    @isTest
    static void cellStateLateLinesWhenCoveredPeriodWasEmptyAtPayoutTime() {
        Test.startTest();
        AgentPayoutCalculator.CellState state = AgentPayoutCalculator.evaluate(2, 0, 57.82, true);
        AgentPayoutCalculator.CellState settledAndEmpty =
            AgentPayoutCalculator.evaluate(0, 0, null, true);
        Test.stopTest();

        Assert.areEqual(AgentPayoutCalculator.CellState.LATE_LINES, state,
            'Open lines inside a settled range are late arrivals');
        Assert.areEqual(AgentPayoutCalculator.CellState.COVERED_EMPTY, settledAndEmpty,
            'A settled range with no lines at all is covered but empty');
    }

    /**
     * @description Lines stamped by a payout whose range no longer covers their period read as
     * orphaned rather than paid.
     */
    @isTest
    static void cellStateOrphanPaidWhenStampedButNotCovered() {
        Test.startTest();
        AgentPayoutCalculator.CellState state = AgentPayoutCalculator.evaluate(2, 3, 40.00, false);
        Test.stopTest();

        Assert.areEqual(AgentPayoutCalculator.CellState.ORPHAN_PAID, state,
            'Stamped lines outside any covered range are orphaned');
    }

    /**
     * @description A period whose only open lines are chargebacks is a credit owed back, not a
     * payment due.
     */
    @isTest
    static void cellStateCreditDueWhenOpenNetIsNegative() {
        Test.startTest();
        AgentPayoutCalculator.CellState state = AgentPayoutCalculator.evaluate(3, 0, -117.65, false);
        Test.stopTest();

        Assert.areEqual(AgentPayoutCalculator.CellState.CREDIT_DUE, state,
            'Open lines with a negative net are a credit due back');
    }

    /**
     * @description Coverage is decided by comparing the period against the payout's declared range,
     * for the right agent and only while the payout is still Paid.
     */
    @isTest
    static void isCoveredComparesTheDeclaredRangeLexically() {
        List<Agent_Payout__c> payouts = new List<Agent_Payout__c>{
            new Agent_Payout__c(
                Agent__c = AGENT_ID, Status__c = 'Paid',
                Period_Start__c = '2026-01', Period_End__c = '2026-06'
            ),
            new Agent_Payout__c(
                Agent__c = AGENT_ID, Status__c = 'Voided',
                Period_Start__c = '2025-01', Period_End__c = '2025-12'
            ),
            new Agent_Payout__c(
                Agent__c = OTHER_AGENT_ID, Status__c = 'Paid',
                Period_Start__c = '2026-07', Period_End__c = '2026-12'
            )
        };

        Test.startTest();
        Boolean insideRange = AgentPayoutCalculator.isCovered(payouts, AGENT_ID, '2026-04');
        Boolean onLowerBound = AgentPayoutCalculator.isCovered(payouts, AGENT_ID, '2026-01');
        Boolean onUpperBound = AgentPayoutCalculator.isCovered(payouts, AGENT_ID, '2026-06');
        Boolean pastRange = AgentPayoutCalculator.isCovered(payouts, AGENT_ID, '2026-07');
        Boolean voidedRange = AgentPayoutCalculator.isCovered(payouts, AGENT_ID, '2025-05');
        Boolean otherAgentRange = AgentPayoutCalculator.isCovered(payouts, AGENT_ID, '2026-09');
        Boolean noPayouts = AgentPayoutCalculator.isCovered(null, AGENT_ID, '2026-04');
        Test.stopTest();

        Assert.isTrue(insideRange, 'A period inside the range is covered');
        Assert.isTrue(onLowerBound, 'The first period of the range is covered');
        Assert.isTrue(onUpperBound, 'The last period of the range is covered');
        Assert.isFalse(pastRange, 'A period after the range is not covered');
        Assert.isFalse(voidedRange, 'A voided payout covers nothing');
        Assert.isFalse(otherAgentRange, 'Another agent\'s payout covers nothing here');
        Assert.isFalse(noPayouts, 'With no payouts nothing is covered');
    }

    /**
     * @description Period validation accepts only a 2000s year with a real month.
     */
    @isTest
    static void isValidPeriodAcceptsOnlyWellFormedPeriods() {
        Test.startTest();
        Boolean good = AgentPayoutCalculator.isValidPeriod('2026-07');
        Boolean monthZero = AgentPayoutCalculator.isValidPeriod('2026-00');
        Boolean monthThirteen = AgentPayoutCalculator.isValidPeriod('2026-13');
        Boolean wrongShape = AgentPayoutCalculator.isValidPeriod('2026/07');
        Boolean blank = AgentPayoutCalculator.isValidPeriod('   ');
        Boolean nullPeriod = AgentPayoutCalculator.isValidPeriod(null);
        Test.stopTest();

        Assert.isTrue(good, '2026-07 is a valid period');
        Assert.isFalse(monthZero, 'Month 00 is not a valid period');
        Assert.isFalse(monthThirteen, 'Month 13 is not a valid period');
        Assert.isFalse(wrongShape, 'A slash separator is not a valid period');
        Assert.isFalse(blank, 'Blank is not a valid period');
        Assert.isFalse(nullPeriod, 'Null is not a valid period');
    }

    /**
     * @description Period arithmetic rolls across year boundaries in both directions.
     */
    @isTest
    static void addMonthsRollsAcrossYearBoundaries() {
        Test.startTest();
        String forward = AgentPayoutCalculator.addMonths('2025-11', 3);
        String backward = AgentPayoutCalculator.addMonths('2026-01', -1);
        String unchanged = AgentPayoutCalculator.addMonths('2026-05', 0);
        String invalid = AgentPayoutCalculator.addMonths('nonsense', 1);
        Test.stopTest();

        Assert.areEqual('2026-02', forward, 'Three months past 2025-11 is 2026-02');
        Assert.areEqual('2025-12', backward, 'One month before 2026-01 is 2025-12');
        Assert.areEqual('2026-05', unchanged, 'Adding no months returns the same period');
        Assert.isNull(invalid, 'An invalid period cannot be shifted');
    }

    /**
     * @description The period range is ascending, inclusive of both bounds, and capped.
     */
    @isTest
    static void periodsBetweenIsAscendingInclusiveAndCapped() {
        Test.startTest();
        List<String> range = AgentPayoutCalculator.periodsBetween('2025-11', '2026-02');
        List<String> single = AgentPayoutCalculator.periodsBetween('2026-02', '2026-02');
        List<String> reversed = AgentPayoutCalculator.periodsBetween('2026-06', '2026-01');
        List<String> capped = AgentPayoutCalculator.periodsBetween('2000-01', '2099-12');
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ '2025-11', '2025-12', '2026-01', '2026-02' }, range,
            'The range runs ascending from start to end inclusive');
        Assert.areEqual(1, single.size(), 'A single-period range holds one period');
        Assert.isTrue(reversed.isEmpty(), 'A reversed range yields nothing');
        Assert.areEqual(240, capped.size(), 'A very wide range is capped');
    }

    /**
     * @description Period comparison orders chronologically and puts null first.
     */
    @isTest
    static void compareToOrdersPeriodsChronologically() {
        Test.startTest();
        Integer before = AgentPayoutCalculator.compareTo('2025-12', '2026-01');
        Integer after = AgentPayoutCalculator.compareTo('2026-01', '2025-12');
        Integer same = AgentPayoutCalculator.compareTo('2026-01', '2026-01');
        Integer nullLeft = AgentPayoutCalculator.compareTo(null, '2026-01');
        Integer bothNull = AgentPayoutCalculator.compareTo(null, null);
        Test.stopTest();

        Assert.areEqual(-1, before, '2025-12 precedes 2026-01');
        Assert.areEqual(1, after, '2026-01 follows 2025-12');
        Assert.areEqual(0, same, 'Equal periods compare equal');
        Assert.areEqual(-1, nullLeft, 'Null sorts before any period');
        Assert.areEqual(0, bothNull, 'Two nulls compare equal');
    }

    /**
     * @description Half-year bucketing splits the year at June and names the buckets consistently.
     */
    @isTest
    static void halfYearHelpersBucketTheCalendar() {
        Test.startTest();
        Integer firstHalf = AgentPayoutCalculator.halfOf('2026-06');
        Integer secondHalf = AgentPayoutCalculator.halfOf('2026-07');
        String key = AgentPayoutCalculator.buildHalfKey('2026-08');
        List<String> periods = AgentPayoutCalculator.listHalfPeriods('2026-H2');
        String previous = AgentPayoutCalculator.resolvePreviousHalfKey('2026-H1');
        String invalidKey = AgentPayoutCalculator.buildHalfKey('bad');
        Test.stopTest();

        Assert.areEqual(1, firstHalf, 'June belongs to the first half');
        Assert.areEqual(2, secondHalf, 'July belongs to the second half');
        Assert.areEqual('2026-H2', key, 'August 2026 belongs to 2026-H2');
        Assert.areEqual(
            new List<String>{ '2026-07', '2026-08', '2026-09', '2026-10', '2026-11', '2026-12' },
            periods, 'The second half of 2026 runs July to December');
        Assert.areEqual('2025-H2', previous, 'The half before 2026-H1 is 2025-H2');
        Assert.isNull(invalidKey, 'An invalid period has no half-year key');
    }

    /**
     * @description A half still in progress reports only the months that have elapsed, so it can be
     * compared per month against a complete one.
     */
    @isTest
    static void elapsedMonthsInHalfNormalisesAPartlyElapsedHalf() {
        Test.startTest();
        Integer partial = AgentPayoutCalculator.elapsedMonthsInHalf('2026-H2', '2026-08');
        Integer complete = AgentPayoutCalculator.elapsedMonthsInHalf('2026-H1', '2026-08');
        Integer notStarted = AgentPayoutCalculator.elapsedMonthsInHalf('2027-H1', '2026-08');
        Integer malformed = AgentPayoutCalculator.elapsedMonthsInHalf('2026-H3', '2026-08');
        Test.stopTest();

        Assert.areEqual(2, partial, 'Two months of 2026-H2 have elapsed by August');
        Assert.areEqual(6, complete, '2026-H1 is complete by August');
        Assert.areEqual(0, notStarted, 'A future half has not started');
        Assert.areEqual(0, malformed, 'A malformed half key has no elapsed months');
    }

    /**
     * @description A line whose policy carries no commission rate cannot be valued. A blank rate is
     * never treated as zero percent and never as a hundred percent.
     */
    @isTest
    static void payableIsNullWhenPolicyRateIsMissing() {
        Test.startTest();
        Decimal missingRate = AgentPayoutCalculator.computePayable(120.00, null);
        Decimal zeroRate = AgentPayoutCalculator.computePayable(120.00, 0);
        Test.stopTest();

        Assert.isNull(missingRate, 'A line with no policy rate cannot be valued');
        Assert.areEqual(0.00, zeroRate, 'A rate that is genuinely zero pays zero');
    }

    /**
     * @description The payable is the carrier amount taken at the rate supplied, rounded to cents,
     * and it moves with that rate rather than with any other rate in the org.
     */
    @isTest
    static void payableUsesTheSuppliedRateAndRoundsToCents() {
        Test.startTest();
        Decimal atPolicyRate = AgentPayoutCalculator.computePayable(100.00, 50);
        Decimal atAccountRate = AgentPayoutCalculator.computePayable(100.00, 90);
        Decimal rounded = AgentPayoutCalculator.computePayable(33.33, 50);
        Decimal negative = AgentPayoutCalculator.computePayable(-28.91, 50);
        Decimal nullAmount = AgentPayoutCalculator.computePayable(null, 50);
        Test.stopTest();

        Assert.areEqual(50.00, atPolicyRate, '100 at 50 percent pays 50');
        Assert.areEqual(90.00, atAccountRate, 'A different rate gives a different answer');
        Assert.areNotEqual(atPolicyRate, atAccountRate,
            'The rate that is passed in is the rate that is used');
        Assert.areEqual(16.67, rounded, '33.33 at 50 percent rounds half up to 16.67');
        Assert.areEqual(-14.46, negative, 'A chargeback is valued at the same rate');
        Assert.areEqual(0.00, nullAmount, 'A missing amount values at zero, not null');
    }

    /**
     * @description The sortable name is "Last, First" with the bookkeeping prefix removed, so the
     * agents recorded as "Agent <name>" do not all sort together.
     */
    @isTest
    static void sortNameStripsTheAgentPrefixAndPutsTheSurnameFirst() {
        Test.startTest();
        String prefixed = AgentPayoutCalculator.buildSortName('Agent Kay', 'Kim');
        String plain = AgentPayoutCalculator.buildSortName('Dana', 'Kim');
        String lastOnly = AgentPayoutCalculator.buildSortName(null, 'Kim');
        String firstOnly = AgentPayoutCalculator.buildSortName('Agent Kay', null);
        String neither = AgentPayoutCalculator.buildSortName(null, null);
        String justThePrefix = AgentPayoutCalculator.buildSortName('Agent', 'Kim');
        Test.stopTest();

        Assert.areEqual('Kim, Kay', prefixed, 'The Agent prefix is stripped from the first name');
        Assert.areEqual('Kim, Dana', plain, 'An unprefixed name is simply reordered');
        Assert.areEqual('Kim', lastOnly, 'With no first name only the surname is used');
        Assert.areEqual('Kay', firstOnly, 'With no surname only the first name is used');
        Assert.areEqual('', neither, 'With no name at all the sort name is empty');
        Assert.areEqual('Kim, Agent', justThePrefix,
            'A first name that is exactly "Agent" is a name, not a prefix');
    }

    /**
     * @description Independent restatement of the documented precedence order, used as the oracle
     * for the totality sweep.
     * @param open The open line count.
     * @param paid The stamped line count.
     * @param net The open carrier net.
     * @param covered Whether the period sits inside a settled range.
     * @return The state the rules require.
     */
    private static AgentPayoutCalculator.CellState expectedState(
        Integer open, Integer paid, Decimal net, Boolean covered
    ) {
        if (open == 0 && paid == 0 && !covered) {
            return AgentPayoutCalculator.CellState.NO_DATA;
        }
        if (open > 0 && covered) {
            return AgentPayoutCalculator.CellState.LATE_LINES;
        }
        if (open == 0 && paid > 0) {
            return AgentPayoutCalculator.CellState.PAID;
        }
        if (open == 0 && covered) {
            return AgentPayoutCalculator.CellState.COVERED_EMPTY;
        }
        if (paid > 0) {
            return AgentPayoutCalculator.CellState.ORPHAN_PAID;
        }
        if (net != null && net < 0) {
            return AgentPayoutCalculator.CellState.CREDIT_DUE;
        }
        return AgentPayoutCalculator.CellState.UNPAID;
    }
}
