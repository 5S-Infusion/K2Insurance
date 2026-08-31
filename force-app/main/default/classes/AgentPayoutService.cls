/**
 * @description Business logic for agent payouts: builds the agent board, prices a proposed payout
 * from the policy commission rate, records the payout and stamps the commission lines it settles,
 * and voids a payout by releasing its lines. The server is the sole authority on every amount.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class AgentPayoutService {

    private static final String STATUS_PAID = 'Paid';
    private static final String STATUS_VOIDED = 'Voided';
    private static final Integer MAX_LINES = 5000;
    private static final Integer NOTES_LENGTH = 255;
    private static final Integer REFERENCE_LENGTH = 50;
    private static final Integer MONTHS_IN_HALF = 6;
    private static final String RANGE_SEPARATOR = ' ~ ';
    private static final String NOTE_SEPARATOR = ' | ';
    private static final Decimal ZERO = 0;

    // Only a test may set this, through @TestVisible; production code has no path to it. It exists
    // so the all-or-nothing rollback of a failed line stamp can be proven.
    @TestVisible
    private Boolean stampFailureInjected = false;

    /**
     * @description Raised when a payout request is incomplete, stale, or cannot be settled as asked.
     */
    public class AgentPayoutException extends Exception {}

    /**
     * @description One (agent, period) cell of the agent board. It carries the raw buckets as well
     * as the state the server derived from them, so the client can re-derive the state for itself
     * when it folds several months into one column without ever inventing its own numbers.
     */
    public class CellDto {
        @AuraEnabled public String period;
        @AuraEnabled public String state;
        @AuraEnabled public Integer totalLineCount;
        @AuraEnabled public Decimal totalNet;
        @AuraEnabled public Integer openLineCount;
        @AuraEnabled public Decimal openNet;
        @AuraEnabled public Decimal openPayable;
        @AuraEnabled public Integer openUnratedLineCount;
        @AuraEnabled public Decimal openUnratedNet;
        @AuraEnabled public Integer paidLineCount;
        @AuraEnabled public Boolean covered;
    }

    /**
     * @description One of an agent's payouts as listed in the payout history.
     */
    public class PayoutSummaryDto {
        @AuraEnabled public Id payoutId;
        @AuraEnabled public String name;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public Date paidDate;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public String status;
        @AuraEnabled public Integer lineCount;
    }

    /**
     * @description One agent row of the agent board, carrying the roll-up totals, the payout
     * history, and one cell per period on the board's axis in the same order as that axis.
     */
    public class AgentRowDto implements Comparable {
        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public String sortName;
        @AuraEnabled public Decimal outstandingNet;
        @AuraEnabled public Decimal outstandingPayable;
        @AuraEnabled public Integer outstandingLineCount;
        @AuraEnabled public Integer unratedLineCount;
        @AuraEnabled public Decimal unratedNet;
        @AuraEnabled public String oldestUnpaidPeriod;
        @AuraEnabled public Integer lateLineCount;
        @AuraEnabled public Integer latePeriodCount;
        @AuraEnabled public Boolean hasLateLines;
        @AuraEnabled public Date lastPaidDate;
        @AuraEnabled public Decimal lastPaidAmount;
        @AuraEnabled public Id lastPayoutId;
        @AuraEnabled public String lastPayoutName;
        @AuraEnabled public Decimal deltaPerMonth;
        @AuraEnabled public List<CellDto> cells;
        @AuraEnabled public List<PayoutSummaryDto> payouts;

        /**
         * @description Orders rows by their sortable "Last, First" name.
         * @param other The row to compare against.
         * @return -1, 0 or 1 in the usual Comparable sense.
         */
        public Integer compareTo(Object other) {
            AgentRowDto row = (AgentRowDto) other;
            String mine = this.sortName == null ? '' : this.sortName;
            String theirs = row == null || row.sortName == null ? '' : row.sortName;
            Integer result = mine.compareTo(theirs);
            if (result < 0) {
                return -1;
            }
            return result > 0 ? 1 : 0;
        }
    }

    /**
     * @description One half-year bucket of the board's period axis.
     */
    public class HalfDto {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public List<String> periods;
        @AuraEnabled public Boolean inProgress;
    }

    /**
     * @description The board's period axis and the way it is bucketed, shared by every row.
     */
    public class MetaDto {
        @AuraEnabled public List<String> periods;
        @AuraEnabled public String latestPeriod;
        @AuraEnabled public List<HalfDto> halves;
    }

    /**
     * @description The whole agent board: the axis every row is laid out on, and the rows.
     */
    public class BoardDto {
        @AuraEnabled public MetaDto meta;
        @AuraEnabled public List<AgentRowDto> agents;
    }

    /**
     * @description The server's valuation of a proposed payout, including the lines that need a
     * human decision — the ones arriving into an already-settled period, the chargebacks, the ones
     * an earlier payout already settled, and the ones whose policy carries no rate. Every total it
     * carries is computed over every open line, which is the default the client starts from before
     * the user excludes anything.
     */
    public class PreflightDto {
        @AuraEnabled public Id agentId;
        @AuraEnabled public String agentName;
        @AuraEnabled public String periodLabel;
        @AuraEnabled public String periodStart;
        @AuraEnabled public String periodEnd;
        @AuraEnabled public List<String> periods;
        @AuraEnabled public Integer lineCount;
        @AuraEnabled public Decimal linesNetAmount;
        @AuraEnabled public Decimal chargebackAmount;
        @AuraEnabled public Integer chargebackLineCount;
        @AuraEnabled public Decimal computedPayable;
        @AuraEnabled public Integer unratedLineCount;
        @AuraEnabled public Decimal unratedNetAmount;
        @AuraEnabled public Integer lateLineCount;
        @AuraEnabled public Integer alreadyStampedLineCount;
        @AuraEnabled public List<String> coveredPeriods;
        @AuraEnabled public List<LineDto> payableLines;
        @AuraEnabled public List<LineDto> lateLines;
        @AuraEnabled public List<LineDto> chargebackLines;
        @AuraEnabled public List<LineDto> alreadyStampedLines;
        @AuraEnabled public List<LineDto> rateMissingLines;
    }

    /**
     * @description An inbound request to price or record one payout for one agent over one period
     * range. The three expected totals are the client's echo of the valuation it showed the user;
     * they are what makes a save built on numbers that have since moved refusable. The excluded
     * line ids are the lines the user unticked; leaving them out settles everything, which is the
     * default the review modal opens on.
     */
    public class PayoutRequest {
        @AuraEnabled public Id agentId;
        @AuraEnabled public String periodStart;
        @AuraEnabled public String periodEnd;
        @AuraEnabled public List<String> periods;
        @AuraEnabled public List<Id> excludedLineIds;
        @AuraEnabled public Integer expectedLineCount;
        @AuraEnabled public Decimal expectedLinesNetAmount;
        @AuraEnabled public Decimal expectedPayableAmount;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Date paidDate;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String referenceNumber;
        @AuraEnabled public String notes;
    }

    /**
     * @description One commission line as shown in the drill-down and review tables.
     */
    public class LineDto {
        @AuraEnabled public Id lineId;
        @AuraEnabled public String lineName;
        @AuraEnabled public String period;
        @AuraEnabled public Date commissionDate;
        @AuraEnabled public String clientName;
        @AuraEnabled public String clientCompany;
        @AuraEnabled public Id policyId;
        @AuraEnabled public String policyName;
        @AuraEnabled public String carrierName;
        @AuraEnabled public Decimal commissionAmount;
        @AuraEnabled public Decimal rate;
        @AuraEnabled public Decimal payableAmount;
        @AuraEnabled public Boolean rateMissing;
        @AuraEnabled public Boolean paidOut;
        @AuraEnabled public Id payoutId;
        @AuraEnabled public String payoutName;
    }

    /**
     * @description What the running user is allowed to see and do, so the UI can degrade cleanly
     * instead of offering an action that would fail half way through.
     */
    public class AccessDto {
        @AuraEnabled public Boolean canRead;
        @AuraEnabled public Boolean canRecord;
        @AuraEnabled public Boolean canVoid;
    }

    /**
     * @description Mutable roll-up of one aggregate bucket while the board is assembled.
     */
    private class Bucket {
        private Integer lineCount = 0;
        private Decimal net = 0;
        private Decimal payable = 0;
    }

    /**
     * @description Everything the board's queries produced, keyed for row assembly.
     */
    private class BoardData {
        private Map<String, Bucket> openCells = new Map<String, Bucket>();
        private Map<String, Bucket> unratedCells = new Map<String, Bucket>();
        private Map<String, Bucket> paidCells = new Map<String, Bucket>();
        private Map<Id, List<Agent_Payout__c>> paidPayoutsByAgent =
            new Map<Id, List<Agent_Payout__c>>();
        private Map<Id, List<PayoutSummaryDto>> summariesByAgent =
            new Map<Id, List<PayoutSummaryDto>>();
        private Map<Id, Agent_Payout__c> latestPayoutByAgent = new Map<Id, Agent_Payout__c>();
    }

    /**
     * @description Server-computed totals for a set of commission lines.
     */
    private class Totals {
        private Integer lineCount = 0;
        private Decimal chargeback = 0;
        private Integer chargebackCount = 0;
        private Decimal net = 0;
        private Decimal payable = 0;
        private Integer unratedCount = 0;
        private Decimal unratedNet = 0;
    }

    /**
     * @description A validated payout range: the periods actually selected, and the wider range the
     * payout declares it settles.
     */
    private class PeriodRange {
        private List<String> periods;
        private String periodStart;
        private String periodEnd;
    }

    /**
     * @description One payable line together with the key it is listed under, so the review modal
     * always receives the same selection in the same order: oldest period first, then by line name.
     */
    private class PayableLine implements Comparable {
        private String sortKey;
        private LineDto line;

        /**
         * @description Orders payable lines by payment period, then by line name.
         * @param other The payable line to compare against.
         * @return -1, 0 or 1 in the usual Comparable sense.
         */
        public Integer compareTo(Object other) {
            PayableLine that = (PayableLine) other;
            String mine = this.sortKey == null ? '' : this.sortKey;
            String theirs = that == null || that.sortKey == null ? '' : that.sortKey;
            Integer result = mine.compareTo(theirs);
            if (result < 0) {
                return -1;
            }
            return result > 0 ? 1 : 0;
        }
    }

    /**
     * @description Builds the whole agent board in five queries: one live aggregate over unstamped
     * subagent lines, one over the unstamped lines whose policy carries no rate, one snapshot
     * aggregate over stamped lines, the agents' payouts, and the agents themselves. Lines with no
     * subagent on the policy are out of scope and are never counted.
     * @return The board's period axis and the agent rows laid out on it.
     */
    public BoardDto getBoard() {
        BoardData data = new BoardData();
        Set<Id> agentIds = new Set<Id>();
        Set<String> observedPeriods = new Set<String>();

        for (AggregateResult row : [
            SELECT Policy_Number__r.Subagent__c agentKey,
                   Commission_Statement__r.Payment_Period__c periodKey,
                   COUNT(Id) lineCount,
                   SUM(Commission_Amount__c) netAmount,
                   SUM(Payable_Amount__c) payableAmount
            FROM Commission_Line__c
            WHERE Policy_Number__r.Subagent__c != null AND Payout__c = null
            WITH USER_MODE
            GROUP BY Policy_Number__r.Subagent__c, Commission_Statement__r.Payment_Period__c
        ]) {
            Id agentId = (Id) row.get('agentKey');
            String period = (String) row.get('periodKey');
            if (agentId == null || !AgentPayoutCalculator.isValidPeriod(period)) {
                continue;
            }
            agentIds.add(agentId);
            observedPeriods.add(period);
            accumulate(
                data.openCells, buildCellKey(agentId, period),
                toInteger(row.get('lineCount')),
                toDecimal(row.get('netAmount')),
                toDecimal(row.get('payableAmount'))
            );
        }

        for (AggregateResult row : [
            SELECT Policy_Number__r.Subagent__c agentKey,
                   Commission_Statement__r.Payment_Period__c periodKey,
                   COUNT(Id) lineCount,
                   SUM(Commission_Amount__c) netAmount
            FROM Commission_Line__c
            WHERE Policy_Number__r.Subagent__c != null
              AND Payout__c = null
              AND Policy_Number__r.Commission_Rate__c = null
            WITH USER_MODE
            GROUP BY Policy_Number__r.Subagent__c, Commission_Statement__r.Payment_Period__c
        ]) {
            Id agentId = (Id) row.get('agentKey');
            String period = (String) row.get('periodKey');
            if (agentId == null || !AgentPayoutCalculator.isValidPeriod(period)) {
                continue;
            }
            accumulate(
                data.unratedCells, buildCellKey(agentId, period),
                toInteger(row.get('lineCount')),
                toDecimal(row.get('netAmount')),
                ZERO
            );
        }

        for (AggregateResult row : [
            SELECT Payout__r.Agent__c agentKey,
                   Commission_Statement__r.Payment_Period__c periodKey,
                   COUNT(Id) lineCount,
                   SUM(Commission_Amount__c) netAmount
            FROM Commission_Line__c
            WHERE Payout__c != null
            WITH USER_MODE
            GROUP BY Payout__r.Agent__c, Commission_Statement__r.Payment_Period__c
        ]) {
            Id agentId = (Id) row.get('agentKey');
            String period = (String) row.get('periodKey');
            if (agentId == null || !AgentPayoutCalculator.isValidPeriod(period)) {
                continue;
            }
            agentIds.add(agentId);
            observedPeriods.add(period);
            accumulate(
                data.paidCells, buildCellKey(agentId, period),
                toInteger(row.get('lineCount')),
                toDecimal(row.get('netAmount')),
                ZERO
            );
        }

        BoardDto board = new BoardDto();
        board.meta = new MetaDto();
        board.meta.periods = new List<String>();
        board.meta.halves = new List<HalfDto>();
        board.agents = new List<AgentRowDto>();
        if (agentIds.isEmpty()) {
            return board;
        }

        for (Agent_Payout__c payout : [
            SELECT Id, Name, Agent__c, Period_Start__c, Period_End__c, Period_Label__c, Status__c,
                   Paid_Date__c, Amount_Paid__c, Line_Count__c, CreatedDate
            FROM Agent_Payout__c
            WHERE Agent__c IN :agentIds AND Status__c != :STATUS_VOIDED
            WITH USER_MODE
            ORDER BY Paid_Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            addSummary(data, payout);
            if (payout.Status__c != STATUS_PAID) {
                continue;
            }
            addPaidPayout(data, payout);
            if (AgentPayoutCalculator.isValidPeriod(payout.Period_Start__c)) {
                observedPeriods.add(payout.Period_Start__c);
            }
            if (AgentPayoutCalculator.isValidPeriod(payout.Period_End__c)) {
                observedPeriods.add(payout.Period_End__c);
            }
        }

        board.meta.periods = buildAxis(observedPeriods);
        board.meta.latestPeriod = board.meta.periods.isEmpty()
            ? null : board.meta.periods[board.meta.periods.size() - 1];
        board.meta.halves = buildHalves(board.meta.periods, board.meta.latestPeriod);

        for (Account agent : [
            SELECT Id, Name, FirstName, LastName
            FROM Account
            WHERE Id IN :agentIds
            WITH USER_MODE
        ]) {
            board.agents.add(buildRow(agent, board.meta, data));
        }
        board.agents.sort();
        return board;
    }

    /**
     * @description Assembles one agent's board row: one cell per period on the axis in axis order,
     * the outstanding roll-ups, the late-arrival counts, the payout history and the monthly trend.
     * @param agent The agent account.
     * @param meta The board's period axis.
     * @param data The buckets and payouts the board's queries produced.
     * @return The assembled row.
     */
    private AgentRowDto buildRow(Account agent, MetaDto meta, BoardData data) {
        AgentRowDto row = new AgentRowDto();
        row.agentId = agent.Id;
        row.agentName = agent.Name;
        row.sortName = AgentPayoutCalculator.buildSortName(agent.FirstName, agent.LastName);
        row.outstandingNet = 0;
        row.outstandingPayable = 0;
        row.outstandingLineCount = 0;
        row.unratedLineCount = 0;
        row.unratedNet = 0;
        row.lateLineCount = 0;
        row.latePeriodCount = 0;
        row.cells = new List<CellDto>();
        row.payouts = data.summariesByAgent.containsKey(agent.Id)
            ? data.summariesByAgent.get(agent.Id)
            : new List<PayoutSummaryDto>();

        List<Agent_Payout__c> paidPayouts = data.paidPayoutsByAgent.get(agent.Id);
        Map<String, Decimal> netByPeriod = new Map<String, Decimal>();
        String lateState = AgentPayoutCalculator.CellState.LATE_LINES.name();

        for (String period : meta.periods) {
            String key = buildCellKey(agent.Id, period);
            Bucket open = data.openCells.get(key);
            Bucket unrated = data.unratedCells.get(key);
            Bucket paid = data.paidCells.get(key);

            Bucket openBucket = open == null ? new Bucket() : open;
            Bucket unratedBucket = unrated == null ? new Bucket() : unrated;
            Bucket paidBucket = paid == null ? new Bucket() : paid;

            CellDto cell = new CellDto();
            cell.period = period;
            cell.openLineCount = openBucket.lineCount;
            cell.openNet = roundToMoney(openBucket.net);
            cell.openPayable = roundToMoney(openBucket.payable);
            cell.openUnratedLineCount = unratedBucket.lineCount;
            cell.openUnratedNet = roundToMoney(unratedBucket.net);
            cell.paidLineCount = paidBucket.lineCount;
            cell.totalLineCount = cell.openLineCount + cell.paidLineCount;
            cell.totalNet = roundToMoney(cell.openNet + paidBucket.net);
            cell.covered = AgentPayoutCalculator.isCovered(paidPayouts, agent.Id, period);
            cell.state = AgentPayoutCalculator.evaluate(
                cell.openLineCount, cell.paidLineCount, cell.openNet, cell.covered
            ).name();
            row.cells.add(cell);

            row.outstandingLineCount += cell.openLineCount;
            row.outstandingNet += cell.openNet;
            row.outstandingPayable += cell.openPayable;
            row.unratedLineCount += cell.openUnratedLineCount;
            row.unratedNet += cell.openUnratedNet;
            if (cell.openLineCount > 0 && row.oldestUnpaidPeriod == null) {
                row.oldestUnpaidPeriod = period;
            }
            if (cell.state == lateState) {
                row.latePeriodCount++;
                row.lateLineCount += cell.openLineCount;
            }
            netByPeriod.put(period, cell.totalNet);
        }

        row.hasLateLines = row.latePeriodCount > 0;
        row.outstandingNet = roundToMoney(row.outstandingNet);
        row.outstandingPayable = roundToMoney(row.outstandingPayable);
        row.unratedNet = roundToMoney(row.unratedNet);

        Agent_Payout__c latestPayout = data.latestPayoutByAgent.get(agent.Id);
        if (latestPayout != null) {
            row.lastPaidDate = latestPayout.Paid_Date__c;
            row.lastPaidAmount = latestPayout.Amount_Paid__c;
            row.lastPayoutId = latestPayout.Id;
            row.lastPayoutName = latestPayout.Name;
        }
        row.deltaPerMonth = computeDelta(netByPeriod, meta.periods, meta.latestPeriod);
        return row;
    }

    /**
     * @description Records one payout in the agent's history, newest first because the payouts are
     * read in that order.
     * @param data The board data being assembled.
     * @param payout The payout to summarise.
     */
    private void addSummary(BoardData data, Agent_Payout__c payout) {
        List<PayoutSummaryDto> summaries = data.summariesByAgent.get(payout.Agent__c);
        if (summaries == null) {
            summaries = new List<PayoutSummaryDto>();
            data.summariesByAgent.put(payout.Agent__c, summaries);
        }
        PayoutSummaryDto summary = new PayoutSummaryDto();
        summary.payoutId = payout.Id;
        summary.name = payout.Name;
        summary.periodLabel = payout.Period_Label__c;
        summary.paidDate = payout.Paid_Date__c;
        summary.amountPaid = payout.Amount_Paid__c;
        summary.status = payout.Status__c;
        summary.lineCount = payout.Line_Count__c == null ? 0 : payout.Line_Count__c.intValue();
        summaries.add(summary);
    }

    /**
     * @description Files a Paid payout under its agent, keeping the first one seen as the latest
     * because the payouts are read newest first.
     * @param data The board data being assembled.
     * @param payout The Paid payout.
     */
    private void addPaidPayout(BoardData data, Agent_Payout__c payout) {
        List<Agent_Payout__c> agentPayouts = data.paidPayoutsByAgent.get(payout.Agent__c);
        if (agentPayouts == null) {
            agentPayouts = new List<Agent_Payout__c>();
            data.paidPayoutsByAgent.put(payout.Agent__c, agentPayouts);
        }
        agentPayouts.add(payout);
        if (!data.latestPayoutByAgent.containsKey(payout.Agent__c)) {
            data.latestPayoutByAgent.put(payout.Agent__c, payout);
        }
    }

    /**
     * @description Compares the current half-year's average monthly carrier net against the previous
     * half-year's. A half still in progress is divided by the months elapsed, not by six, so a
     * partly-elapsed half is not read as a collapse in volume.
     * @param netByPeriod The agent's carrier net per period, stamped and unstamped alike.
     * @param axis The board's period axis.
     * @param latestPeriod The most recent period on the axis.
     * @return The monthly change, or null when there is not enough history to compare.
     */
    private Decimal computeDelta(Map<String, Decimal> netByPeriod, List<String> axis, String latestPeriod) {
        if (axis == null || axis.isEmpty() || !AgentPayoutCalculator.isValidPeriod(latestPeriod)) {
            return null;
        }
        String currentHalf = AgentPayoutCalculator.buildHalfKey(latestPeriod);
        String previousHalf = AgentPayoutCalculator.resolvePreviousHalfKey(currentHalf);
        Integer elapsed = AgentPayoutCalculator.elapsedMonthsInHalf(currentHalf, latestPeriod);
        List<String> previousPeriods = AgentPayoutCalculator.listHalfPeriods(previousHalf);
        if (elapsed == 0 || previousPeriods.isEmpty()) {
            return null;
        }
        if (AgentPayoutCalculator.compareTo(previousPeriods[0], axis[0]) < 0) {
            return null;
        }

        Decimal currentSum = 0;
        for (String period : AgentPayoutCalculator.listHalfPeriods(currentHalf)) {
            if (AgentPayoutCalculator.compareTo(period, latestPeriod) > 0) {
                continue;
            }
            Decimal net = netByPeriod.get(period);
            if (net != null) {
                currentSum += net;
            }
        }
        Decimal previousSum = 0;
        for (String period : previousPeriods) {
            Decimal net = netByPeriod.get(period);
            if (net != null) {
                previousSum += net;
            }
        }
        Decimal currentAverage = currentSum / elapsed;
        Decimal previousAverage = previousSum / MONTHS_IN_HALF;
        return (currentAverage - previousAverage).setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * @description Prices a proposed payout from the server's own reading of the data, lists every
     * open line so the user can untick the ones to hold back, and lists the lines that need a look
     * before the payout is recorded. The totals are computed over every open line, so the client
     * starts from everything included and subtracts as lines are unticked. A line an earlier payout
     * already settled is reported for information only and is never offered as payable.
     * @param request The agent and period range to value.
     * @return The valuation of the proposed payout.
     */
    public PreflightDto getPreflight(PayoutRequest request) {
        if (request == null || request.agentId == null) {
            throw new AgentPayoutException(Label.AgentManagement_AgentRequired);
        }
        PeriodRange range = resolveRange(request);
        Set<Id> agentIds = new Set<Id>{ request.agentId };

        List<Commission_Line__c> lines = loadLines(agentIds, new Set<String>(range.periods));
        List<Commission_Line__c> openLines = new List<Commission_Line__c>();
        List<LineDto> alreadyStampedLines = new List<LineDto>();
        for (Commission_Line__c line : lines) {
            if (line.Payout__c == null) {
                openLines.add(line);
            } else {
                alreadyStampedLines.add(toLineDto(line));
            }
        }
        Totals totals = summarize(openLines);
        List<Agent_Payout__c> paidPayouts = loadPaidPayouts(agentIds);

        PreflightDto preflight = new PreflightDto();
        preflight.agentId = request.agentId;
        preflight.agentName = agentNameFor(agentIds);
        preflight.periods = range.periods;
        preflight.periodStart = range.periodStart;
        preflight.periodEnd = range.periodEnd;
        preflight.periodLabel = periodLabel(range.periodStart, range.periodEnd);
        preflight.lineCount = totals.lineCount;
        preflight.linesNetAmount = totals.net;
        preflight.chargebackAmount = totals.chargeback;
        preflight.chargebackLineCount = totals.chargebackCount;
        preflight.computedPayable = totals.payable;
        preflight.unratedLineCount = totals.unratedCount;
        preflight.unratedNetAmount = totals.unratedNet;
        preflight.alreadyStampedLineCount = alreadyStampedLines.size();
        preflight.alreadyStampedLines = alreadyStampedLines;
        preflight.payableLines = toPayableLines(openLines);

        preflight.coveredPeriods = new List<String>();
        for (String period : range.periods) {
            if (AgentPayoutCalculator.isCovered(paidPayouts, request.agentId, period)) {
                preflight.coveredPeriods.add(period);
            }
        }
        Set<String> covered = new Set<String>(preflight.coveredPeriods);

        preflight.lateLines = new List<LineDto>();
        preflight.chargebackLines = new List<LineDto>();
        preflight.rateMissingLines = new List<LineDto>();
        for (Commission_Line__c line : openLines) {
            Boolean isLate = line.Commission_Statement__r != null
                && covered.contains(line.Commission_Statement__r.Payment_Period__c);
            Boolean isChargeback = line.Commission_Amount__c != null
                && line.Commission_Amount__c < 0;
            Boolean isRateMissing = line.Policy_Number__r == null
                || line.Policy_Number__r.Commission_Rate__c == null;
            if (!isLate && !isChargeback && !isRateMissing) {
                continue;
            }
            LineDto dto = toLineDto(line);
            if (isLate) {
                preflight.lateLines.add(dto);
            }
            if (isChargeback) {
                preflight.chargebackLines.add(dto);
            }
            if (isRateMissing) {
                preflight.rateMissingLines.add(dto);
            }
        }
        preflight.lateLineCount = preflight.lateLines.size();
        return preflight;
    }

    /**
     * @description Records one payout and stamps the commission lines it settles. The lines are
     * re-read from the agent and periods rather than trusted from the client, the lines the user
     * unticked are dropped before anything is valued, the totals are recomputed over what survives,
     * and the three totals the client echoes back must match that recomputation exactly or nothing
     * is written — so an exclusion that never reached the server is refused as stale rather than
     * overpaid. The lines are then locked before anything is written, so two saves racing over the
     * same lines cannot both settle them: the second waits, finds them stamped, and is refused.
     * The header therefore snapshots what was actually settled, never what was proposed.
     * The header and the stamps are one DML each and are rolled back together on any failure.
     * @param request The payout to record.
     * @return The id of the payout that was created.
     */
    public Id createPayout(PayoutRequest request) {
        if (request == null || request.agentId == null) {
            throw new AgentPayoutException(Label.AgentManagement_AgentRequired);
        }
        PeriodRange range = resolveRange(request);
        Set<Id> agentIds = new Set<Id>{ request.agentId };
        Set<Id> excluded = excludedIds(request.excludedLineIds);

        List<Commission_Line__c> includedLines = new List<Commission_Line__c>();
        for (Commission_Line__c line : loadLines(agentIds, new Set<String>(range.periods))) {
            if (line.Payout__c == null && !excluded.contains(line.Id)) {
                includedLines.add(line);
            }
        }
        if (includedLines.isEmpty()) {
            throw new AgentPayoutException(Label.AgentManagement_NothingToPay);
        }

        Totals totals = summarize(includedLines);
        if (!totalsMatch(request, totals)) {
            throw new AgentPayoutException(Label.AgentManagement_StaleTotals);
        }
        Set<Id> includedIds = new Map<Id, Commission_Line__c>(includedLines).keySet();
        if (lockOpenLines(includedIds) != totals.lineCount) {
            throw new AgentPayoutException(Label.AgentManagement_StaleTotals);
        }

        Agent_Payout__c header = new Agent_Payout__c(
            Agent__c = request.agentId,
            Period_Start__c = range.periodStart,
            Period_End__c = range.periodEnd,
            Line_Count__c = totals.lineCount,
            Lines_Net_Amount__c = totals.net,
            Chargeback_Amount__c = totals.chargeback,
            Payable_Amount__c = totals.payable,
            Unrated_Line_Count__c = totals.unratedCount,
            Unrated_Net_Amount__c = totals.unratedNet,
            Amount_Paid__c = request.amountPaid == null ? totals.payable : request.amountPaid,
            Paid_Date__c = request.paidDate == null ? Date.today() : request.paidDate,
            Status__c = STATUS_PAID,
            Payment_Method__c = request.paymentMethod,
            Reference_Number__c = truncate(request.referenceNumber, REFERENCE_LENGTH),
            Notes__c = truncate(request.notes, NOTES_LENGTH)
        );

        Savepoint restorePoint = Database.setSavepoint();
        try {
            Database.insert(header, AccessLevel.USER_MODE);
            List<Commission_Line__c> stamps = new List<Commission_Line__c>();
            for (Commission_Line__c line : includedLines) {
                stamps.add(new Commission_Line__c(Id = line.Id, Payout__c = header.Id));
            }
            stampLines(stamps);
            return header.Id;
        } catch (Exception ex) {
            Database.rollback(restorePoint);
            throw ex;
        }
    }

    /**
     * @description Voids a payout: releases every line it stamped so they become payable again, and
     * marks the header Voided with the reason recorded in its notes. The header is kept as the
     * record that the payment was made and reversed. Calling it twice is harmless.
     * @param payoutId The payout to void.
     * @param reason Why the payout is being voided.
     */
    public void voidPayout(Id payoutId, String reason) {
        if (payoutId == null) {
            throw new AgentPayoutException(Label.AgentManagement_LoadError);
        }
        if (String.isBlank(reason)) {
            throw new AgentPayoutException(Label.AgentManagement_VoidReasonRequired);
        }
        List<Agent_Payout__c> found = [
            SELECT Id, Status__c, Notes__c
            FROM Agent_Payout__c
            WHERE Id = :payoutId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new AgentPayoutException(Label.AgentManagement_LoadError);
        }
        Agent_Payout__c payout = found[0];
        List<Commission_Line__c> stamped = loadStampedLines(new Set<Id>{ payoutId });

        Savepoint restorePoint = Database.setSavepoint();
        try {
            if (!stamped.isEmpty()) {
                for (Commission_Line__c line : stamped) {
                    line.Payout__c = null;
                }
                Database.update(stamped, AccessLevel.USER_MODE);
            }
            if (payout.Status__c != STATUS_VOIDED) {
                payout.Status__c = STATUS_VOIDED;
                payout.Notes__c = truncate(voidStamp(reason, payout.Notes__c), NOTES_LENGTH);
                Database.update(payout, AccessLevel.USER_MODE);
            }
        } catch (Exception ex) {
            Database.rollback(restorePoint);
            throw ex;
        }
    }

    /**
     * @description Lists the agent's commission lines for the given periods for the drill-down
     * table. Only plain field paths are read: the object's Client, Company, Agent and Subagent
     * formula fields return raw anchor markup and are never returned to the UI.
     * @param agentId The agent whose lines to list.
     * @param periods The payment periods to list.
     * @return The lines, oldest period first.
     */
    public List<LineDto> getLines(Id agentId, List<String> periods) {
        List<LineDto> rows = new List<LineDto>();
        if (agentId == null || periods == null || periods.isEmpty()) {
            return rows;
        }
        Set<String> periodSet = new Set<String>();
        for (String period : periods) {
            if (AgentPayoutCalculator.isValidPeriod(period)) {
                periodSet.add(period);
            }
        }
        if (periodSet.isEmpty()) {
            throw new AgentPayoutException(Label.AgentManagement_PeriodInvalid);
        }
        for (Commission_Line__c line : loadLines(new Set<Id>{ agentId }, periodSet)) {
            rows.add(toLineDto(line));
        }
        return rows;
    }

    /**
     * @description Reports what the running user may see and do, from object and field describes,
     * so the UI can hide an action it could not complete rather than failing part way through it.
     * Recording a payout needs both the header and the line stamp; voiding needs both too.
     * @return The running user's access.
     */
    public AccessDto getAccess() {
        Schema.DescribeSObjectResult payoutType = Agent_Payout__c.SObjectType.getDescribe();
        Schema.DescribeSObjectResult lineType = Commission_Line__c.SObjectType.getDescribe();
        Schema.DescribeSObjectResult policyType = Insurance__c.SObjectType.getDescribe();
        Schema.DescribeFieldResult stampField = Commission_Line__c.Payout__c.getDescribe();
        Boolean canStampLines = lineType.isUpdateable() && stampField.isUpdateable();

        AccessDto access = new AccessDto();
        access.canRead = payoutType.isAccessible() && lineType.isAccessible()
            && policyType.isAccessible();
        access.canRecord = payoutType.isCreateable() && canStampLines;
        access.canVoid = payoutType.isUpdateable() && canStampLines;
        return access;
    }

    /**
     * @description Returns the active payment-method options for the payout form.
     * @return One {label, value} map per active picklist entry.
     */
    public List<Map<String, String>> getMethodOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Schema.PicklistEntry entry : Agent_Payout__c.Payment_Method__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(), 'value' => entry.getValue()
                });
            }
        }
        return options;
    }

    /**
     * @description Reads the agents' commission lines for the given periods, bounded by a hard
     * ceiling so an over-wide selection is refused rather than silently truncated. Every field the
     * drill-down and the review lists need is read here, so a line is never queried twice.
     * @param agentIds The subagents whose lines to read.
     * @param periods The payment periods to read.
     * @return The lines, oldest period first.
     */
    private List<Commission_Line__c> loadLines(Set<Id> agentIds, Set<String> periods) {
        Integer cap = MAX_LINES + 1;
        List<Commission_Line__c> lines = [
            SELECT Id, Name, Commission_Amount__c, Commission_Date__c, Payout__c, Payout__r.Name,
                   Commission_Statement__r.Payment_Period__c,
                   Commission_Statement__r.Insurance_Provider__r.Name,
                   Policy_Number__c, Policy_Number__r.Name,
                   Policy_Number__r.Commission_Rate__c,
                   Policy_Number__r.Policy_Holder__r.Name,
                   Policy_Number__r.Company__r.Name
            FROM Commission_Line__c
            WHERE Policy_Number__r.Subagent__c IN :agentIds
              AND Commission_Statement__r.Payment_Period__c IN :periods
            WITH USER_MODE
            ORDER BY Commission_Statement__r.Payment_Period__c, Id
            LIMIT :cap
        ];
        if (lines.size() > MAX_LINES) {
            throw new AgentPayoutException(Label.AgentManagement_TooManyLines);
        }
        return lines;
    }

    /**
     * @description Locks the lines a save is about to stamp and reports how many of them are still
     * unstamped. The lock is what makes the server the sole authority when two saves overlap: the
     * second one waits here until the first commits, then sees those lines already stamped and
     * counts fewer than it means to settle, so the caller refuses it instead of paying twice.
     * @param lineIds The lines about to be stamped.
     * @return How many of those lines are still unstamped.
     */
    private Integer lockOpenLines(Set<Id> lineIds) {
        List<Commission_Line__c> locked = [
            SELECT Id
            FROM Commission_Line__c
            WHERE Id IN :lineIds AND Payout__c = null
            WITH USER_MODE
            FOR UPDATE
        ];
        return locked.size();
    }

    /**
     * @description Reads the lines currently stamped by the given payouts.
     * @param payoutIds The payouts whose lines to read.
     * @return The stamped lines.
     */
    private List<Commission_Line__c> loadStampedLines(Set<Id> payoutIds) {
        Integer cap = MAX_LINES + 1;
        List<Commission_Line__c> lines = [
            SELECT Id, Payout__c
            FROM Commission_Line__c
            WHERE Payout__c IN :payoutIds
            WITH USER_MODE
            ORDER BY Id
            LIMIT :cap
        ];
        if (lines.size() > MAX_LINES) {
            throw new AgentPayoutException(Label.AgentManagement_TooManyLines);
        }
        return lines;
    }

    /**
     * @description Reads the agents' Paid payouts, which is what declares a period settled.
     * @param agentIds The agents whose payouts to read.
     * @return The Paid payouts.
     */
    private List<Agent_Payout__c> loadPaidPayouts(Set<Id> agentIds) {
        return [
            SELECT Id, Name, Agent__c, Period_Start__c, Period_End__c, Status__c, Paid_Date__c
            FROM Agent_Payout__c
            WHERE Agent__c IN :agentIds AND Status__c = :STATUS_PAID
            WITH USER_MODE
            ORDER BY Period_Start__c
        ];
    }

    /**
     * @description Reads one agent's display name.
     * @param agentIds The agent to name.
     * @return The account name, or null when it cannot be read.
     */
    private String agentNameFor(Set<Id> agentIds) {
        for (Account agent : [SELECT Id, Name FROM Account WHERE Id IN :agentIds WITH USER_MODE]) {
            return agent.Name;
        }
        return null;
    }

    /**
     * @description Applies the payout stamp to the given lines in one DML.
     * @param stamps The line stamps to apply.
     */
    private void stampLines(List<Commission_Line__c> stamps) {
        if (stampFailureInjected) {
            throw new AgentPayoutException(Label.AgentManagement_SaveError);
        }
        Database.update(stamps, AccessLevel.USER_MODE);
    }

    /**
     * @description Turns one commission line into the row the UI shows. Only plain paths are read;
     * the object's hyperlink formula fields carry raw anchor markup and never leave the server.
     * @param line The commission line.
     * @return The row.
     */
    private LineDto toLineDto(Commission_Line__c line) {
        Insurance__c policy = line.Policy_Number__r;
        Commission_Statement__c statement = line.Commission_Statement__r;
        Decimal rate = policy == null ? null : policy.Commission_Rate__c;

        LineDto row = new LineDto();
        row.lineId = line.Id;
        row.lineName = line.Name;
        row.period = statement == null ? null : statement.Payment_Period__c;
        row.commissionDate = line.Commission_Date__c;
        row.clientName = policy == null || policy.Policy_Holder__r == null
            ? null : policy.Policy_Holder__r.Name;
        row.clientCompany = policy == null || policy.Company__r == null
            ? null : policy.Company__r.Name;
        row.policyId = line.Policy_Number__c;
        row.policyName = policy == null ? null : policy.Name;
        row.carrierName = statement == null || statement.Insurance_Provider__r == null
            ? null : statement.Insurance_Provider__r.Name;
        row.commissionAmount = line.Commission_Amount__c;
        row.rate = rate;
        row.payableAmount = AgentPayoutCalculator.computePayable(line.Commission_Amount__c, rate);
        row.rateMissing = rate == null;
        row.paidOut = line.Payout__c != null;
        row.payoutId = line.Payout__c;
        row.payoutName = line.Payout__r == null ? null : line.Payout__r.Name;
        return row;
    }

    /**
     * @description Lists the open lines the review modal offers as payable, oldest period first and
     * then by line name, so the same selection always renders in the same order and a checkbox keeps
     * its row between one valuation and the next.
     * @param openLines The unstamped lines in the selection.
     * @return The rows to offer, in listing order.
     */
    private List<LineDto> toPayableLines(List<Commission_Line__c> openLines) {
        List<PayableLine> sortable = new List<PayableLine>();
        for (Commission_Line__c line : openLines) {
            LineDto dto = toLineDto(line);
            PayableLine entry = new PayableLine();
            entry.line = dto;
            entry.sortKey = (dto.period == null ? '' : dto.period)
                + '|' + (dto.lineName == null ? '' : dto.lineName);
            sortable.add(entry);
        }
        sortable.sort();
        List<LineDto> rows = new List<LineDto>();
        for (PayableLine entry : sortable) {
            rows.add(entry.line);
        }
        return rows;
    }

    /**
     * @description Reads the line ids the user unticked into a set the load can test against. A
     * missing or empty list means nothing was held back, and an id that names no line in the
     * selection simply never matches, so a stale exclusion is ignored rather than being an error.
     * @param excludedLineIds The line ids the client asked to leave unpaid.
     * @return The ids to drop, which is empty when everything is included.
     */
    private Set<Id> excludedIds(List<Id> excludedLineIds) {
        Set<Id> excluded = new Set<Id>();
        if (excludedLineIds == null) {
            return excluded;
        }
        for (Id lineId : excludedLineIds) {
            if (lineId != null) {
                excluded.add(lineId);
            }
        }
        return excluded;
    }

    /**
     * @description Totals a set of commission lines the way a payout must be valued: the carrier net
     * as paid to K2, the chargebacks within it, and the payable computed strictly from each policy's
     * own commission rate. A line whose policy carries no rate cannot be valued, so it contributes
     * nothing to the payable and is counted separately instead.
     * @param lines The lines to total.
     * @return The totals.
     */
    private Totals summarize(List<Commission_Line__c> lines) {
        Totals totals = new Totals();
        for (Commission_Line__c line : lines) {
            Decimal amount = line.Commission_Amount__c == null ? 0 : line.Commission_Amount__c;
            Decimal rate = line.Policy_Number__r == null
                ? null : line.Policy_Number__r.Commission_Rate__c;
            totals.lineCount++;
            totals.net += amount;
            if (amount < 0) {
                totals.chargeback += amount;
                totals.chargebackCount++;
            }
            Decimal payable = AgentPayoutCalculator.computePayable(amount, rate);
            if (payable == null) {
                totals.unratedCount++;
                totals.unratedNet += amount;
            } else {
                totals.payable += payable;
            }
        }
        totals.net = roundToMoney(totals.net);
        totals.chargeback = roundToMoney(totals.chargeback);
        totals.payable = roundToMoney(totals.payable);
        totals.unratedNet = roundToMoney(totals.unratedNet);
        return totals;
    }

    /**
     * @description Rounds an amount to cents, so every figure the board and the valuation report
     * carries the same scale and can be compared as money rather than as an arbitrary decimal.
     * @param amount The amount to round.
     * @return The amount at two decimal places.
     */
    private Decimal roundToMoney(Decimal amount) {
        Decimal resolved = amount == null ? 0 : amount;
        return resolved.setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * @description Reports whether the three totals the client echoed back are exactly the totals
     * the server has just recomputed. A missing echo is a mismatch, so a payload that lost its
     * totals on the way in can never be saved against numbers nobody has seen.
     * @param request The inbound request.
     * @param totals The server-computed totals.
     * @return True when all three match exactly.
     */
    private Boolean totalsMatch(PayoutRequest request, Totals totals) {
        if (request.expectedLineCount == null || request.expectedLinesNetAmount == null
            || request.expectedPayableAmount == null) {
            return false;
        }
        return request.expectedLineCount == totals.lineCount
            && request.expectedLinesNetAmount == totals.net
            && request.expectedPayableAmount == totals.payable;
    }

    /**
     * @description Validates a requested selection into an ascending, duplicate-free period list and
     * the range the payout declares it settles. The declared range defaults to the selection's own
     * bounds and must contain every period selected, so a payout can never claim to settle less
     * than it is stamping.
     * @param request The inbound request.
     * @return The validated range.
     */
    private PeriodRange resolveRange(PayoutRequest request) {
        PeriodRange range = new PeriodRange();
        range.periods = validatePeriods(request.periods);
        range.periodStart = String.isBlank(request.periodStart)
            ? range.periods[0] : request.periodStart;
        range.periodEnd = String.isBlank(request.periodEnd)
            ? range.periods[range.periods.size() - 1] : request.periodEnd;
        if (!AgentPayoutCalculator.isValidPeriod(range.periodStart)
            || !AgentPayoutCalculator.isValidPeriod(range.periodEnd)
            || AgentPayoutCalculator.compareTo(range.periodStart, range.periodEnd) > 0
            || AgentPayoutCalculator.compareTo(range.periodStart, range.periods[0]) > 0
            || AgentPayoutCalculator.compareTo(
                   range.periodEnd, range.periods[range.periods.size() - 1]) < 0) {
            throw new AgentPayoutException(Label.AgentManagement_PeriodInvalid);
        }
        return range;
    }

    /**
     * @description Validates and normalises a requested period selection into an ascending,
     * duplicate-free list.
     * @param periods The requested periods.
     * @return The normalised periods, ascending.
     */
    private List<String> validatePeriods(List<String> periods) {
        if (periods == null || periods.isEmpty()) {
            throw new AgentPayoutException(Label.AgentManagement_PeriodRequired);
        }
        Set<String> unique = new Set<String>();
        for (String period : periods) {
            if (!AgentPayoutCalculator.isValidPeriod(period)) {
                throw new AgentPayoutException(Label.AgentManagement_PeriodInvalid);
            }
            unique.add(period);
        }
        List<String> ordered = new List<String>(unique);
        ordered.sort();
        return ordered;
    }

    /**
     * @description Names a period range the way the payout record's own label formula does.
     * @param periodStart The first period covered.
     * @param periodEnd The last period covered.
     * @return The label, or null when either bound is missing.
     */
    private String periodLabel(String periodStart, String periodEnd) {
        if (String.isBlank(periodStart) || String.isBlank(periodEnd)) {
            return null;
        }
        return periodStart == periodEnd ? periodStart : periodStart + RANGE_SEPARATOR + periodEnd;
    }

    /**
     * @description Builds the board's contiguous period axis from every period the data touches, so
     * a month with no activity still gets a column.
     * @param observedPeriods The periods seen in the aggregates and payout ranges.
     * @return The axis, ascending.
     */
    private List<String> buildAxis(Set<String> observedPeriods) {
        List<String> observed = new List<String>(observedPeriods);
        if (observed.isEmpty()) {
            return new List<String>();
        }
        observed.sort();
        return AgentPayoutCalculator.periodsBetween(observed[0], observed[observed.size() - 1]);
    }

    /**
     * @description Groups the axis into half-year buckets, marking the one that has not finished.
     * @param axis The board's period axis.
     * @param latestPeriod The most recent period on the axis.
     * @return The half-year buckets, ascending.
     */
    private List<HalfDto> buildHalves(List<String> axis, String latestPeriod) {
        List<HalfDto> halves = new List<HalfDto>();
        Map<String, HalfDto> byKey = new Map<String, HalfDto>();
        for (String period : axis) {
            String key = AgentPayoutCalculator.buildHalfKey(period);
            HalfDto half = byKey.get(key);
            if (half == null) {
                half = new HalfDto();
                half.key = key;
                half.label = key.substring(0, 4) + ' H' + key.substring(6);
                half.periods = new List<String>();
                half.inProgress = false;
                byKey.put(key, half);
                halves.add(half);
            }
            half.periods.add(period);
        }
        String currentKey = AgentPayoutCalculator.buildHalfKey(latestPeriod);
        HalfDto current = byKey.get(currentKey);
        if (current != null) {
            current.inProgress =
                AgentPayoutCalculator.elapsedMonthsInHalf(currentKey, latestPeriod) < MONTHS_IN_HALF;
        }
        return halves;
    }

    /**
     * @description Accumulates one aggregate row into the bucket for its cell.
     * @param buckets The bucket map to accumulate into.
     * @param key The cell key.
     * @param lineCount The row's line count.
     * @param net The row's carrier net.
     * @param payable The row's payable, which is zero for the aggregates that do not read it.
     */
    private void accumulate(
        Map<String, Bucket> buckets, String key, Integer lineCount, Decimal net, Decimal payable
    ) {
        Bucket bucket = buckets.get(key);
        if (bucket == null) {
            bucket = new Bucket();
            buckets.put(key, bucket);
        }
        bucket.lineCount += lineCount;
        bucket.net += net;
        bucket.payable += payable;
    }

    /**
     * @description Builds the map key identifying one (agent, period) cell.
     * @param agentId The agent.
     * @param period The payment period.
     * @return The composite key.
     */
    private String buildCellKey(Id agentId, String period) {
        return String.valueOf(agentId) + '|' + period;
    }

    /**
     * @description Reads an aggregate value as an integer, treating a missing value as zero.
     * @param value The aggregate value.
     * @return The integer value.
     */
    private Integer toInteger(Object value) {
        return value == null ? 0 : (Integer) value;
    }

    /**
     * @description Reads an aggregate value as a decimal, treating a missing value as zero.
     * @param value The aggregate value.
     * @return The decimal value.
     */
    private Decimal toDecimal(Object value) {
        if (value == null) {
            return 0;
        }
        return (Decimal) value;
    }

    /**
     * @description Builds the note recorded on a voided payout: a machine-readable void marker, the
     * reason, and whatever note the payout already carried. The note the user wrote is never cut to
     * make room, because it is the only copy of it there is; the automated stamp takes what is left
     * of the field instead, and stands aside altogether when there is no room for it.
     * @param reason Why the payout was voided.
     * @param existingNotes The note already on the payout.
     * @return The combined note, within the length the column accepts.
     */
    private String voidStamp(String reason, String existingNotes) {
        String stamp = '[VOIDED ' + System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + 'Z] ' + reason.trim();
        if (String.isBlank(existingNotes)) {
            return truncate(stamp, NOTES_LENGTH);
        }
        Integer budget = NOTES_LENGTH - existingNotes.length() - NOTE_SEPARATOR.length();
        if (budget <= 0) {
            return existingNotes;
        }
        return truncate(stamp, budget) + NOTE_SEPARATOR + existingNotes;
    }

    /**
     * @description Truncates a value to the length its column accepts.
     * @param value The value.
     * @param maxLength The maximum length.
     * @return The value, truncated if it was longer.
     */
    private String truncate(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
