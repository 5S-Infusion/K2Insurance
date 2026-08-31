/**
 * @description Pure derivation for agent payouts: the per-period cell state machine, payment-period
 * arithmetic on "YYYY-MM" strings, half-year bucketing, and the policy-rate payable calculation.
 * Every method is a total function with no database access.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class AgentPayoutCalculator {

    private static final String PERIOD_PATTERN = '20\\d\\d-(0[1-9]|1[0-2])';
    private static final String STATUS_PAID = 'Paid';
    private static final Integer MAX_PERIODS = 240;
    private static final Integer MONTHS_IN_HALF = 6;
    private static final Integer AGENT_PREFIX_LENGTH = 6;
    private static final String AGENT_PREFIX = 'Agent ';

    /**
     * @description The settlement state of one (agent, period) cell on the agent board.
     */
    public enum CellState {
        NO_DATA,
        LATE_LINES,
        PAID,
        COVERED_EMPTY,
        ORPHAN_PAID,
        CREDIT_DUE,
        UNPAID
    }

    /**
     * @description Resolves the state of one (agent, period) cell. First match wins, and every
     * paid/unpaid decision is a count test — a period whose amounts happen to net to zero while
     * lines remain unsettled must still read as unpaid. Null inputs are treated as zero counts,
     * an unknown net, and not covered.
     * @param openLineCount Lines for the agent in the period that carry no payout stamp.
     * @param paidLineCount Lines stamped by a payout belonging to the agent in the period.
     * @param openNet The carrier net of the open lines; null when unknown.
     * @param isCovered Whether a Paid payout for the agent declares a range containing the period.
     * @return The cell state.
     */
    public static CellState evaluate(
        Integer openLineCount, Integer paidLineCount, Decimal openNet, Boolean isCovered
    ) {
        Integer open = openLineCount == null || openLineCount < 0 ? 0 : openLineCount;
        Integer paid = paidLineCount == null || paidLineCount < 0 ? 0 : paidLineCount;
        Boolean covered = isCovered == true;

        if (open == 0 && paid == 0 && !covered) {
            return CellState.NO_DATA;
        }
        if (open > 0 && covered) {
            return CellState.LATE_LINES;
        }
        if (open == 0 && paid > 0) {
            return CellState.PAID;
        }
        if (open == 0 && covered) {
            return CellState.COVERED_EMPTY;
        }
        if (paid > 0) {
            return CellState.ORPHAN_PAID;
        }
        if (openNet != null && openNet < 0) {
            return CellState.CREDIT_DUE;
        }
        return CellState.UNPAID;
    }

    /**
     * @description Reports whether one of the agent's Paid payouts declares a period range that
     * contains the given period. The range is compared lexically on the "YYYY-MM" strings, which is
     * chronological for that format, so a range is never enumerated month by month.
     * @param paidPayouts The payouts to test.
     * @param agentId The agent whose coverage is being tested.
     * @param period The payment period in "YYYY-MM" form.
     * @return True when a Paid payout for that agent covers the period.
     */
    public static Boolean isCovered(List<Agent_Payout__c> paidPayouts, Id agentId, String period) {
        if (paidPayouts == null || agentId == null || !isValidPeriod(period)) {
            return false;
        }
        for (Agent_Payout__c payout : paidPayouts) {
            if (payout == null || payout.Agent__c != agentId) {
                continue;
            }
            if (payout.Status__c != STATUS_PAID) {
                continue;
            }
            String periodStart = payout.Period_Start__c;
            String periodEnd = payout.Period_End__c;
            if (String.isBlank(periodStart) || String.isBlank(periodEnd)) {
                continue;
            }
            if (periodStart.compareTo(period) <= 0 && periodEnd.compareTo(period) >= 0) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Reports whether a value is a well-formed payment period of the form "YYYY-MM"
     * with a 2000s year and a month between 01 and 12.
     * @param period The value to test.
     * @return True when the value is a valid payment period.
     */
    public static Boolean isValidPeriod(String period) {
        return String.isNotBlank(period) && Pattern.matches(PERIOD_PATTERN, period);
    }

    /**
     * @description Shifts a payment period by a number of months, forwards or backwards.
     * @param period The starting payment period.
     * @param months The number of months to add; may be negative.
     * @return The shifted period, or null when the input is invalid or the result leaves the
     * supported century.
     */
    public static String addMonths(String period, Integer months) {
        if (!isValidPeriod(period) || months == null) {
            return null;
        }
        Integer year = Integer.valueOf(period.substring(0, 4));
        Integer month = Integer.valueOf(period.substring(5, 7));
        Integer absolute = year * 12 + (month - 1) + months;
        if (absolute < 0) {
            return null;
        }
        Integer shiftedYear = absolute / 12;
        Integer shiftedMonth = Math.mod(absolute, 12) + 1;
        if (shiftedYear < 2000 || shiftedYear > 2099) {
            return null;
        }
        return String.valueOf(shiftedYear) + '-' + (shiftedMonth < 10 ? '0' : '') + String.valueOf(shiftedMonth);
    }

    /**
     * @description Lists every payment period from start to end inclusive, ascending. The result is
     * capped so a mistyped range can never produce an unbounded list.
     * @param startPeriod The first period.
     * @param endPeriod The last period.
     * @return The periods in ascending order; empty when either bound is invalid or start is after end.
     */
    public static List<String> periodsBetween(String startPeriod, String endPeriod) {
        List<String> periods = new List<String>();
        if (!isValidPeriod(startPeriod) || !isValidPeriod(endPeriod)) {
            return periods;
        }
        if (startPeriod.compareTo(endPeriod) > 0) {
            return periods;
        }
        String cursor = startPeriod;
        while (cursor != null && cursor.compareTo(endPeriod) <= 0 && periods.size() < MAX_PERIODS) {
            periods.add(cursor);
            cursor = addMonths(cursor, 1);
        }
        return periods;
    }

    /**
     * @description Compares two payment periods chronologically. A null is ordered before any period.
     * @param left The first period.
     * @param right The second period.
     * @return -1 when left precedes right, 1 when it follows, 0 when they are equal.
     */
    public static Integer compareTo(String left, String right) {
        if (left == null && right == null) {
            return 0;
        }
        if (left == null) {
            return -1;
        }
        if (right == null) {
            return 1;
        }
        Integer result = left.compareTo(right);
        if (result < 0) {
            return -1;
        }
        return result > 0 ? 1 : 0;
    }

    /**
     * @description Returns which half of the year a period falls in.
     * @param period The payment period.
     * @return 1 for January–June, 2 for July–December, null when the period is invalid.
     */
    public static Integer halfOf(String period) {
        if (!isValidPeriod(period)) {
            return null;
        }
        return Integer.valueOf(period.substring(5, 7)) <= MONTHS_IN_HALF ? 1 : 2;
    }

    /**
     * @description Builds the half-year bucket key a period belongs to, for example "2026-H1".
     * @param period The payment period.
     * @return The half-year key, or null when the period is invalid.
     */
    public static String buildHalfKey(String period) {
        Integer half = halfOf(period);
        return half == null ? null : period.substring(0, 4) + '-H' + String.valueOf(half);
    }

    /**
     * @description Lists the six payment periods that make up a half-year bucket, ascending.
     * @param halfYearKey The half-year key, for example "2026-H2".
     * @return The six periods; empty when the key is malformed.
     */
    public static List<String> listHalfPeriods(String halfYearKey) {
        List<String> periods = new List<String>();
        if (String.isBlank(halfYearKey) || !Pattern.matches('20\\d\\d-H[12]', halfYearKey)) {
            return periods;
        }
        String year = halfYearKey.substring(0, 4);
        Integer firstMonth = halfYearKey.endsWith('H1') ? 1 : 7;
        for (Integer offset = 0; offset < MONTHS_IN_HALF; offset++) {
            Integer month = firstMonth + offset;
            periods.add(year + '-' + (month < 10 ? '0' : '') + String.valueOf(month));
        }
        return periods;
    }

    /**
     * @description Returns the half-year bucket immediately before the given one.
     * @param halfYearKey The half-year key, for example "2026-H1".
     * @return The preceding half-year key, or null when the key is malformed.
     */
    public static String resolvePreviousHalfKey(String halfYearKey) {
        List<String> periods = listHalfPeriods(halfYearKey);
        if (periods.isEmpty()) {
            return null;
        }
        return buildHalfKey(addMonths(periods[0], -1));
    }

    /**
     * @description Counts how many months of a half-year bucket have elapsed as at the latest
     * period on the board, so a half that is still in progress can be compared on a per-month basis
     * against a complete one.
     * @param halfYearKey The half-year key to measure.
     * @param latestPeriod The most recent period with data.
     * @return 0 when the half has not started, 6 when it is complete, otherwise the months elapsed.
     */
    public static Integer elapsedMonthsInHalf(String halfYearKey, String latestPeriod) {
        List<String> periods = listHalfPeriods(halfYearKey);
        if (periods.isEmpty() || !isValidPeriod(latestPeriod)) {
            return 0;
        }
        if (compareTo(latestPeriod, periods[0]) < 0) {
            return 0;
        }
        if (compareTo(latestPeriod, periods[MONTHS_IN_HALF - 1]) >= 0) {
            return MONTHS_IN_HALF;
        }
        Integer firstMonth = Integer.valueOf(periods[0].substring(5, 7));
        return Integer.valueOf(latestPeriod.substring(5, 7)) - firstMonth + 1;
    }

    /**
     * @description Values one commission line against the rate carried by its policy. A missing rate
     * is not a zero rate and not a hundred percent rate — it is unknown, so the line cannot be
     * valued and null is returned. This derivation is mirrored declaratively by the
     * Commission_Line__c.Payable_Amount__c formula, which the board sums; the two must be changed
     * together or the board column and the review modal will disagree over the same lines.
     * @param amount The carrier commission amount on the line.
     * @param ratePercent The policy commission rate, stored as a percent (50 means 50%).
     * @return The payable amount rounded to two decimals, or null when the rate is unknown.
     */
    public static Decimal computePayable(Decimal amount, Decimal ratePercent) {
        if (ratePercent == null) {
            return null;
        }
        Decimal resolved = amount == null ? 0 : amount;
        return (resolved * ratePercent / 100).setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * @description Builds the sortable display name for an agent: "Last, First", with the
     * bookkeeping prefix "Agent " stripped off the first name so the agents recorded that way do
     * not all collapse under a single letter.
     * @param firstName The agent's first name.
     * @param lastName The agent's last name.
     * @return The sortable name; empty when neither name is present.
     */
    public static String buildSortName(String firstName, String lastName) {
        String first = firstName == null ? '' : firstName.trim();
        if (first.length() > AGENT_PREFIX_LENGTH
            && first.substring(0, AGENT_PREFIX_LENGTH).equalsIgnoreCase(AGENT_PREFIX)) {
            first = first.substring(AGENT_PREFIX_LENGTH).trim();
        }
        String last = lastName == null ? '' : lastName.trim();
        if (String.isBlank(first) && String.isBlank(last)) {
            return '';
        }
        if (String.isBlank(last)) {
            return first;
        }
        if (String.isBlank(first)) {
            return last;
        }
        return last + ', ' + first;
    }
}
