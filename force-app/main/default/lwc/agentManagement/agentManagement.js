/**
 * @description Agent payout board. Shows every subagent that has commission lines, what is still
 * owed to them, and lets the owner record a payout for an explicit list of payment periods.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';
import getBoard from '@salesforce/apex/AgentPayoutController.getBoard';
import getAccess from '@salesforce/apex/AgentPayoutController.getAccess';
import getMethodOptions from '@salesforce/apex/AgentPayoutController.getMethodOptions';
import getPreflightJson from '@salesforce/apex/AgentPayoutController.getPreflightJson';
import createPayoutJson from '@salesforce/apex/AgentPayoutController.createPayoutJson';
import voidPayout from '@salesforce/apex/AgentPayoutController.voidPayout';
import getLines from '@salesforce/apex/AgentPayoutController.getLines';

import LBL_TITLE from '@salesforce/label/c.AgentManagement_Title';
import LBL_LOAD_ERROR from '@salesforce/label/c.AgentManagement_LoadError';
import LBL_SAVE_ERROR from '@salesforce/label/c.AgentManagement_SaveError';
import LBL_AGENT_REQUIRED from '@salesforce/label/c.AgentManagement_AgentRequired';
import LBL_PERIOD_REQUIRED from '@salesforce/label/c.AgentManagement_PeriodRequired';
import LBL_PERIOD_INVALID from '@salesforce/label/c.AgentManagement_PeriodInvalid';
import LBL_NOTHING_TO_PAY from '@salesforce/label/c.AgentManagement_NothingToPay';
import LBL_VOID_REASON_REQUIRED from '@salesforce/label/c.AgentManagement_VoidReasonRequired';
import LBL_ALREADY_VOIDED from '@salesforce/label/c.AgentManagement_AlreadyVoided';
import LBL_PRESET_PAY from '@salesforce/label/c.AgentManagement_PresetPay';
import LBL_PRESET_PERIOD from '@salesforce/label/c.AgentManagement_PresetPeriod';
import LBL_PRESET_HALF from '@salesforce/label/c.AgentManagement_PresetHalf';
import LBL_COL_AGENT from '@salesforce/label/c.AgentManagement_ColAgent';
import LBL_COL_OUTSTANDING from '@salesforce/label/c.AgentManagement_ColOutstanding';
import LBL_COL_OLDEST_UNPAID from '@salesforce/label/c.AgentManagement_ColOldestUnpaid';
import LBL_COL_LATE from '@salesforce/label/c.AgentManagement_ColLate';
import LBL_COL_LAST_PAID from '@salesforce/label/c.AgentManagement_ColLastPaid';
import LBL_COL_DELTA from '@salesforce/label/c.AgentManagement_ColDelta';
import LBL_COL_CARRIER_NET from '@salesforce/label/c.AgentManagement_ColCarrierNet';
import LBL_COL_PAYABLE from '@salesforce/label/c.AgentManagement_ColPayable';
import LBL_BADGE_LATE from '@salesforce/label/c.AgentManagement_BadgeLate';
import LBL_RATE_MISSING from '@salesforce/label/c.AgentManagement_RateMissing';
import LBL_RATE_MISSING_HELP from '@salesforce/label/c.AgentManagement_RateMissingHelp';
import LBL_CHARGEBACKS from '@salesforce/label/c.AgentManagement_Chargebacks';
import LBL_ALREADY_STAMPED from '@salesforce/label/c.AgentManagement_AlreadyStamped';
import LBL_NO_LINES from '@salesforce/label/c.AgentManagement_NoLines';
import LBL_NO_AGENTS from '@salesforce/label/c.AgentManagement_NoAgents';
import LBL_PERIOD_FROM from '@salesforce/label/c.AgentManagement_PeriodFrom';
import LBL_PERIOD_TO from '@salesforce/label/c.AgentManagement_PeriodTo';
import LBL_IN_PROGRESS_HALF from '@salesforce/label/c.AgentManagement_InProgressHalf';
import LBL_DELTA_INSUFFICIENT from '@salesforce/label/c.AgentManagement_DeltaInsufficient';
import LBL_REVIEW from '@salesforce/label/c.AgentManagement_Review';
import LBL_VOID from '@salesforce/label/c.AgentManagement_Void';
import LBL_VOID_REASON from '@salesforce/label/c.AgentManagement_VoidReason';
import LBL_CANCEL from '@salesforce/label/c.AgentManagement_Cancel';
import LBL_RECORD_PAYOUT from '@salesforce/label/c.AgentManagement_RecordPayout';
import LBL_PAYOUT_HISTORY from '@salesforce/label/c.AgentManagement_PayoutHistory';
import LBL_PAID_DATE from '@salesforce/label/c.AgentManagement_PaidDate';
import LBL_AMOUNT_PAID from '@salesforce/label/c.AgentManagement_AmountPaid';
import LBL_NO_ACCESS from '@salesforce/label/c.AgentManagement_NoAccess';
import LBL_NO_AGENTS_HELP from '@salesforce/label/c.AgentManagement_NoAgentsHelp';
import LBL_LOADING from '@salesforce/label/c.AgentManagement_Loading';
import LBL_SAVING from '@salesforce/label/c.AgentManagement_Saving';
import LBL_METHOD_LOAD_ERROR from '@salesforce/label/c.AgentManagement_MethodLoadError';
import LBL_NEGATIVE_AMOUNT from '@salesforce/label/c.AgentManagement_NegativeAmount';
import LBL_SELECT_AGENT_HINT from '@salesforce/label/c.AgentManagement_SelectAgentHint';
import LBL_SELECTED_AGENT from '@salesforce/label/c.AgentManagement_SelectedAgent';
import LBL_LEGEND_TITLE from '@salesforce/label/c.AgentManagement_LegendTitle';

/** @description The only shape a payment period may take, mirroring the Period_*_Format rules. */
const PERIOD_PATTERN = /^20\d\d-(0[1-9]|1[0-2])$/;

/** @description Months shown by the "기간별" preset, ending at the newest period on the axis. */
const MONTH_WINDOW = 13;

/** @description Half-years shown by the "반기" preset, ending at the half holding that period. */
const HALF_WINDOW = 4;

/** @description The three column presets. Switching between them never re-hits the server. */
const PRESET = { PAY: 'pay', PERIOD: 'period', HALF: 'half' };

/**
 * @description Per-state display language. The glyph is the first signal and the weight the second,
 * so every state stays readable in greyscale; colour only reinforces what the glyph already says.
 * Paid is deliberately the quietest state and unpaid the heaviest — the board answers "who am I
 * still holding money for", so the usual green-for-done convention is inverted.
 */
const STATE_META = {
    NO_DATA: { glyph: '—', cssClass: 'cell cell_nodata', labelKey: 'stateNoData' },
    UNPAID: { glyph: '○', cssClass: 'cell cell_unpaid', labelKey: 'stateUnpaid' },
    CREDIT_DUE: { glyph: '▼', cssClass: 'cell cell_credit', labelKey: 'stateCredit' },
    LATE_LINES: { glyph: '▲', cssClass: 'cell cell_late', labelKey: 'stateLate' },
    ORPHAN_PAID: { glyph: '✻', cssClass: 'cell cell_orphan', labelKey: 'stateOrphan' },
    PAID: { glyph: '✓', cssClass: 'cell cell_paid', labelKey: 'statePaid' },
    COVERED_EMPTY: { glyph: '·', cssClass: 'cell cell_covered', labelKey: 'stateCovered' }
};

/** @description Selectors for everything inside a dialog that can hold focus, in DOM order. */
const FOCUSABLE =
    'button:not([disabled]), lightning-button, lightning-textarea, lightning-input, lightning-combobox';

/** @description Legend order — heaviest (still owed) first, quietest (settled, empty) last. */
const LEGEND_ORDER = [
    'UNPAID',
    'CREDIT_DUE',
    'LATE_LINES',
    'ORPHAN_PAID',
    'PAID',
    'COVERED_EMPTY',
    'NO_DATA'
];

/**
 * @description An all-zero cell, so a period an agent has nothing in still folds and renders. It
 * carries every member of CellDto except `period`, which the caller already knows.
 */
const EMPTY_CELL = {
    state: 'NO_DATA',
    totalLineCount: 0,
    totalNet: 0,
    openLineCount: 0,
    openNet: 0,
    openPayable: 0,
    openUnratedLineCount: 0,
    openUnratedNet: 0,
    paidLineCount: 0,
    covered: false
};

/**
 * @description Resolves a FOLDED bucket to exactly one state.
 *
 * KEEP THIS. The server stamps `state` on every monthly cell and the "지급" and "기간별" presets use
 * that value verbatim — this function is never called for them. The "반기" preset folds six monthly
 * cells into one column, and a folded column's state exists nowhere on the server, so it has to be
 * re-derived here from the folded counts. Deleting this leaves the half-year board stateless.
 *
 * First match wins and the chain is total. Every paid/unpaid decision is a COUNT test: a statement
 * can hold four unsettled lines that sum to exactly $0.00, so a sum-based test would call it settled
 * before a dollar moved. The net appears only in the credit rule, and only as a sign test.
 * @param {Object} bucket The folded bucket for one agent and one half-year column.
 * @return {String} The state key, always one of STATE_META's keys.
 */
function resolveState(bucket) {
    const open = bucket.openLineCount || 0;
    const paid = bucket.paidLineCount || 0;
    const covered = !!bucket.covered;
    if (open === 0 && paid === 0 && !covered) {
        return 'NO_DATA';
    }
    if (open > 0 && covered) {
        return 'LATE_LINES';
    }
    if (open === 0 && paid > 0) {
        return 'PAID';
    }
    if (open === 0 && covered) {
        return 'COVERED_EMPTY';
    }
    if (paid > 0) {
        return 'ORPHAN_PAID';
    }
    if (bucket.openNet !== null && bucket.openNet !== undefined && bucket.openNet < 0) {
        return 'CREDIT_DUE';
    }
    return 'UNPAID';
}

/**
 * @description Adds one monthly cell into an accumulator, so the client can fold monthly cells into
 * halves without asking the server for a second shape.
 * @param {Object} target The accumulator to add into.
 * @param {Object} cell The monthly cell to add.
 * @return {Object} The accumulator.
 */
function addCell(target, cell) {
    target.totalLineCount += cell.totalLineCount || 0;
    target.totalNet += cell.totalNet || 0;
    target.openLineCount += cell.openLineCount || 0;
    target.openNet += cell.openNet || 0;
    target.openPayable += cell.openPayable || 0;
    target.openUnratedLineCount += cell.openUnratedLineCount || 0;
    target.openUnratedNet += cell.openUnratedNet || 0;
    target.paidLineCount += cell.paidLineCount || 0;
    target.covered = target.covered || !!cell.covered;
    return target;
}

export default class AgentManagement extends LightningElement {
    label = {
        title: LBL_TITLE,
        loadError: LBL_LOAD_ERROR,
        saveError: LBL_SAVE_ERROR,
        agentRequired: LBL_AGENT_REQUIRED,
        periodRequired: LBL_PERIOD_REQUIRED,
        periodInvalid: LBL_PERIOD_INVALID,
        nothingToPay: LBL_NOTHING_TO_PAY,
        voidReasonRequired: LBL_VOID_REASON_REQUIRED,
        alreadyVoided: LBL_ALREADY_VOIDED,
        presetPay: LBL_PRESET_PAY,
        presetPeriod: LBL_PRESET_PERIOD,
        presetHalf: LBL_PRESET_HALF,
        colAgent: LBL_COL_AGENT,
        colOutstanding: LBL_COL_OUTSTANDING,
        colOldestUnpaid: LBL_COL_OLDEST_UNPAID,
        colLate: LBL_COL_LATE,
        colLastPaid: LBL_COL_LAST_PAID,
        colDelta: LBL_COL_DELTA,
        colCarrierNet: LBL_COL_CARRIER_NET,
        colPayable: LBL_COL_PAYABLE,
        badgeLate: LBL_BADGE_LATE,
        rateMissing: LBL_RATE_MISSING,
        rateMissingHelp: LBL_RATE_MISSING_HELP,
        noLines: LBL_NO_LINES,
        noAgents: LBL_NO_AGENTS,
        periodFrom: LBL_PERIOD_FROM,
        periodTo: LBL_PERIOD_TO,
        inProgressHalf: LBL_IN_PROGRESS_HALF,
        deltaInsufficient: LBL_DELTA_INSUFFICIENT,
        review: LBL_REVIEW,
        void: LBL_VOID,
        voidReason: LBL_VOID_REASON,
        cancel: LBL_CANCEL,
        recordPayout: LBL_RECORD_PAYOUT,
        payoutHistory: LBL_PAYOUT_HISTORY,
        paidDate: LBL_PAID_DATE,
        amountPaid: LBL_AMOUNT_PAID,
        noAccess: LBL_NO_ACCESS,
        noAgentsHelp: LBL_NO_AGENTS_HELP,
        loading: LBL_LOADING,
        saving: LBL_SAVING,
        methodLoadError: LBL_METHOD_LOAD_ERROR,
        negativeAmount: LBL_NEGATIVE_AMOUNT,
        selectAgentHint: LBL_SELECT_AGENT_HINT,
        selectedAgent: LBL_SELECTED_AGENT,
        legendTitle: LBL_LEGEND_TITLE,
        // Reused as the plain-language name of a board state in the legend and cell tooltips.
        stateUnpaid: LBL_COL_OUTSTANDING,
        stateCredit: LBL_CHARGEBACKS,
        stateLate: LBL_BADGE_LATE,
        stateOrphan: LBL_ALREADY_STAMPED,
        statePaid: LBL_PRESET_PAY,
        stateCovered: LBL_NOTHING_TO_PAY,
        stateNoData: LBL_NO_LINES
    };

    board;
    wiredBoard;
    boardResolved = false;
    hasError = false;
    /** @description AccessDto: what this user may do. Never a bare Boolean. */
    access = { canRead: false, canRecord: false, canVoid: false };
    accessResolved = false;
    methodOptions = [];

    preset = PRESET.PAY;
    selectedAgentId;
    periodFrom = '';
    periodTo = '';
    selectionError;

    preflight;
    showReview = false;
    isSaving = false;
    reviewError;

    showVoidModal = false;
    voidTargetId;
    voidTargetName;
    voidReason = '';
    voidError;

    showDrill = false;
    isDrillLoading = false;
    drillCaption = '';
    drillLines = [];
    drillError;

    /** @description Set once the void dialog has taken focus, so re-renders do not steal it back. */
    _voidFocused = false;
    /** @description The payout whose void button focus returns to when the dialog closes. */
    _voidReturnId;
    /** @description Set when the review modal closes, so focus returns to the button that opened it. */
    _reviewReturn = false;

    @wire(getAccess)
    handleAccess({ data, error }) {
        if (data) {
            this.access = {
                canRead: data.canRead === true,
                canRecord: data.canRecord === true,
                canVoid: data.canVoid === true
            };
            this.accessResolved = true;
        } else if (error) {
            // A failed access probe must never look like permission: stay read-only and let the
            // board's own error branch carry the message.
            this.access = { canRead: false, canRecord: false, canVoid: false };
            this.accessResolved = true;
        }
    }

    @wire(getMethodOptions)
    handleMethodOptions({ data, error }) {
        if (data) {
            this.methodOptions = data;
        } else if (error) {
            // The payout still saves without a method, so this is reported rather than fatal — but
            // it is reported: an empty picklist with no explanation is a swallowed failure.
            this.methodOptions = [];
            this.notifyError(error, this.label.methodLoadError);
        }
    }

    @wire(getBoard)
    handleBoard(result) {
        this.wiredBoard = result;
        if (result.data) {
            this.board = result.data;
            this.hasError = false;
            this.boardResolved = true;
        } else if (result.error) {
            this.board = undefined;
            this.hasError = true;
            this.boardResolved = true;
            this.notifyError(result.error, this.label.loadError);
        }
    }

    /** @description May this user create a payout and stamp its lines? */
    get canRecord() {
        return this.access.canRecord === true;
    }

    /** @description May this user void a payout and unstamp its lines? */
    get canVoid() {
        return this.access.canVoid === true;
    }

    /** @description True once the access probe answered and said this user may not read at all. */
    get isDenied() {
        return this.accessResolved && this.access.canRead !== true;
    }

    /**
     * @description True while the board has not answered yet. A refused read is not loading — the
     * access probe has already spoken — so the spinner never stands in for a permission problem.
     */
    get isLoading() {
        return !this.boardResolved && !this.isDenied;
    }

    /**
     * @description Splits an amount into its magnitude and its sign, so a negative renders in
     * accounting parentheses with `lightning-formatted-number` still doing the formatting. A bare
     * minus sign is easy to miss on a dense board; a parenthesised figure is not.
     * @param {Number} value The signed amount.
     * @param {String} extraClass An extra class for the wrapper, or undefined.
     * @return {Object} `{ amount, moneyClass, negativeText }`.
     */
    moneyView(value, extraClass) {
        const resolved = Number(value) || 0;
        const base = extraClass ? `money ${extraClass}` : 'money';
        return {
            amount: Math.abs(resolved),
            moneyClass: resolved < 0 ? `${base} money_negative` : base,
            negativeText: resolved < 0 ? this.label.negativeAmount : ''
        };
    }

    /** @description Every subagent the server returned, in the order it returned them. */
    get agents() {
        return this.board && this.board.agents ? this.board.agents : [];
    }

    get hasAgents() {
        return this.agents.length > 0;
    }

    /** @description The newest payment period present anywhere on the board. */
    get latestPeriod() {
        return this.board && this.board.meta ? this.board.meta.latestPeriod : undefined;
    }

    /** @description Every payment period on the axis, oldest first. */
    get periodAxis() {
        return this.board && this.board.meta && this.board.meta.periods
            ? this.board.meta.periods
            : [];
    }

    /** @description Every half-year the server put on the axis, oldest first. */
    get halves() {
        return this.board && this.board.meta && this.board.meta.halves
            ? this.board.meta.halves
            : [];
    }

    get presetButtons() {
        return [
            { key: PRESET.PAY, name: PRESET.PAY, label: this.label.presetPay },
            { key: PRESET.PERIOD, name: PRESET.PERIOD, label: this.label.presetPeriod },
            { key: PRESET.HALF, name: PRESET.HALF, label: this.label.presetHalf }
        ].map((preset) => ({
            ...preset,
            variant: this.preset === preset.name ? 'brand' : 'neutral'
        }));
    }

    /**
     * @description The trailing months rendered by the "기간별" preset.
     * @return {String[]} Up to MONTH_WINDOW periods, oldest first.
     */
    get monthWindow() {
        const axis = this.periodAxis;
        if (!axis.length) {
            return [];
        }
        const end = axis.indexOf(this.latestPeriod);
        const last = end < 0 ? axis.length : end + 1;
        return axis.slice(Math.max(0, last - MONTH_WINDOW), last);
    }

    /**
     * @description The trailing half-years rendered by the "반기" preset. The server marks the half
     * that is still filling, so nobody reads it as a finished half.
     * @return {Object[]} Up to HALF_WINDOW HalfDto entries, oldest first.
     */
    get halfWindow() {
        const halves = this.halves;
        return halves.slice(Math.max(0, halves.length - HALF_WINDOW));
    }

    /**
     * @description The column descriptors for the active preset. The agent column is rendered
     * separately as a pinned lead cell and is not part of this list. `periods` is the list of
     * monthly periods a column stands for, and `isFolded` says whether more than one of them was
     * folded into it — which is what decides where the column's state comes from.
     * @return {Object[]} One descriptor per column, left to right.
     */
    get columns() {
        // Outstanding is the board's answer to "who do I still owe", so it is the one figure that
        // carries weight; everything beside it is deliberately quieter.
        const money = [
            {
                key: 'outstanding',
                label: this.label.colOutstanding,
                headerClass: 'col-money col-money_primary',
                isInProgress: false
            },
            {
                key: 'payable',
                label: this.label.colPayable,
                headerClass: 'col-money',
                isInProgress: false
            }
        ];
        if (this.preset === PRESET.PERIOD) {
            return this.monthWindow
                .map((period) => ({
                    key: period,
                    label: period,
                    headerClass: 'col-state',
                    isInProgress: false,
                    isFolded: false,
                    periods: [period]
                }))
                .concat(money);
        }
        if (this.preset === PRESET.HALF) {
            return this.halfWindow
                .map((half) => ({
                    key: half.key,
                    label: half.label,
                    headerClass: 'col-state',
                    isInProgress: half.inProgress === true,
                    isFolded: true,
                    periods: half.periods || []
                }))
                .concat([
                    {
                        key: 'delta',
                        label: this.label.colDelta,
                        headerClass: 'col-money',
                        isInProgress: false
                    }
                ])
                .concat(money);
        }
        return money.concat([
            {
                key: 'oldest',
                label: this.label.colOldestUnpaid,
                headerClass: 'col-text',
                isInProgress: false
            },
            {
                key: 'late',
                label: this.label.colLate,
                headerClass: 'col-count',
                isInProgress: false
            },
            {
                key: 'lastPaid',
                label: this.label.colLastPaid,
                headerClass: 'col-money',
                isInProgress: false
            }
        ]);
    }

    /**
     * @description Every board row with its cells already laid out to match `columns`.
     * @return {Object[]} One descriptor per agent.
     */
    get displayRows() {
        const columns = this.columns;
        const index = this.periodIndex;
        return this.agents.map((agent) => {
            const selected = agent.agentId === this.selectedAgentId;
            return {
                agentId: agent.agentId,
                agentName: agent.agentName,
                // The badge beside the name counts PERIODS in trouble; the count of individual
                // late LINES belongs to the 정산 후 도착 column, the drill-down and the modal.
                latePeriodCount: agent.latePeriodCount || 0,
                hasLate: agent.hasLateLines === true,
                isSelected: selected,
                rowClass: selected ? 'slds-hint-parent board-row row_selected' : 'slds-hint-parent board-row',
                cells: columns.map((column) => this.buildCell(agent, index, column))
            };
        });
    }

    /**
     * @description The position of every period on the axis. `AgentRowDto.cells` is dense and
     * ascending — exactly one entry per `meta.periods` entry, in the same order — so a period's
     * cell is found by position, not by scanning or by a map the server never sends.
     * @return {Object} Period to its index on the axis.
     */
    get periodIndex() {
        const index = {};
        this.periodAxis.forEach((period, position) => {
            index[period] = position;
        });
        return index;
    }

    /**
     * @description The agent's cell for one period, read positionally out of the dense array.
     * @param {Object} agent The board agent.
     * @param {Object} index The axis index from `periodIndex`.
     * @param {String} period The period wanted.
     * @return {Object} The cell, or an all-zero stand-in when the row does not reach that period.
     */
    cellFor(agent, index, period) {
        const position = index[period];
        const cells = agent.cells || [];
        const cell = position === undefined ? undefined : cells[position];
        // Defensive: the contract says the array is aligned to the axis. A row that is not must
        // render as empty rather than borrow another period's numbers.
        return cell && cell.period === period ? cell : EMPTY_CELL;
    }

    /**
     * @description Folds the cells a column covers into one bucket, for the "반기" preset.
     * @param {Object} agent The board agent.
     * @param {Object} index The axis index from `periodIndex`.
     * @param {String[]} periods The periods the column covers.
     * @return {Object} The folded bucket.
     */
    foldPeriods(agent, index, periods) {
        const folded = { ...EMPTY_CELL };
        periods.forEach((period) => {
            addCell(folded, this.cellFor(agent, index, period));
        });
        return folded;
    }

    /**
     * @description Builds one cell for one agent and one column, choosing the render type from the
     * column rather than from the preset, so all three presets share a single table body.
     * @param {Object} agent The board agent.
     * @param {Object} index The axis index from `periodIndex`.
     * @param {Object} column The column descriptor.
     * @return {Object} The cell descriptor.
     */
    buildCell(agent, index, column) {
        // The key is data-derived and never positional: for a state column `column.key` IS the
        // period (or the half key), so a cell keeps its identity when the axis grows a month.
        const cell = { key: `${agent.agentId}-${column.key}`, label: column.label };
        if (column.key === 'outstanding') {
            return {
                ...cell,
                isCurrency: true,
                money: this.moneyView(agent.outstandingNet, 'money_primary')
            };
        }
        if (column.key === 'payable') {
            return { ...cell, isCurrency: true, money: this.moneyView(agent.outstandingPayable) };
        }
        if (column.key === 'oldest') {
            return {
                ...cell,
                isText: true,
                value: agent.oldestUnpaidPeriod || STATE_META.NO_DATA.glyph
            };
        }
        if (column.key === 'late') {
            return {
                ...cell,
                isCount: true,
                value: agent.lateLineCount || 0,
                hasValue: (agent.lateLineCount || 0) > 0
            };
        }
        if (column.key === 'lastPaid') {
            return {
                ...cell,
                isLastPaid: true,
                paidDate: agent.lastPaidDate,
                money: this.moneyView(agent.lastPaidAmount, 'money_quiet'),
                payoutName: agent.lastPayoutName,
                hasPayoutName: !!agent.lastPayoutName,
                hasValue: !!agent.lastPaidDate
            };
        }
        if (column.key === 'delta') {
            // The server computes the month-average swing and sends null when two finished halves
            // are not available; the client never recomputes it.
            const delta = agent.deltaPerMonth;
            const hasDelta = delta !== null && delta !== undefined;
            return {
                ...cell,
                isDelta: true,
                hasDelta,
                money: this.moneyView(delta),
                insufficient: hasDelta ? '' : this.label.deltaInsufficient
            };
        }
        return this.buildStateCell(agent, index, column, cell);
    }

    /**
     * @description Turns a period or half-year column into its glyph, weight and colour.
     * @param {Object} agent The board agent.
     * @param {Object} index The axis index from `periodIndex`.
     * @param {Object} column The column descriptor.
     * @param {Object} cell The partially built cell descriptor.
     * @return {Object} The finished state cell.
     */
    buildStateCell(agent, index, column, cell) {
        const bucket = column.isFolded
            ? this.foldPeriods(agent, index, column.periods)
            : this.cellFor(agent, index, column.key);
        // Monthly columns take the state the server already decided. Only a folded half-year has
        // no server state to take, so only it is re-derived.
        const state = column.isFolded ? resolveState(bucket) : bucket.state || 'NO_DATA';
        const meta = STATE_META[state] || STATE_META.NO_DATA;
        const isCredit = state === 'CREDIT_DUE';
        const stateLabel = this.label[meta.labelKey];
        return {
            ...cell,
            isState: true,
            state,
            glyph: meta.glyph,
            cssClass: meta.cssClass,
            stateLabel,
            a11yLabel: `${column.label} ${stateLabel}`,
            isCredit,
            // A credit is always shown as a negative, so it reads in the same accounting
            // parentheses as every other figure on the board rather than as a bare number.
            credit: this.moneyView(isCredit ? -Math.abs(bucket.openNet) : 0, 'money_micro'),
            isDrillable: (bucket.totalLineCount || 0) > 0,
            agentId: agent.agentId,
            periodsCsv: (column.periods || []).join(','),
            drillCaption: `${agent.agentName} · ${column.label}`
        };
    }

    /** @description The legend, rendered always rather than hidden behind a tooltip. */
    get legend() {
        return LEGEND_ORDER.map((state) => {
            const meta = STATE_META[state];
            return {
                key: state,
                glyph: meta.glyph,
                cssClass: `${meta.cssClass} legend-swatch`,
                text: this.label[meta.labelKey]
            };
        });
    }

    /** @description The agent whose row is currently selected, if any. */
    get selectedAgent() {
        return this.agents.find((agent) => agent.agentId === this.selectedAgentId);
    }

    get hasSelection() {
        return !!this.selectedAgent;
    }

    /** @description The board is up but no row is chosen, so the way in still needs naming. */
    get showSelectHint() {
        return !this.hasSelection;
    }

    get selectedAgentName() {
        return this.selectedAgent ? this.selectedAgent.agentName : '';
    }

    /** @description Every period on the axis, offered as the "from" end of the range. */
    get fromOptions() {
        return this.periodAxis.map((period) => ({ label: period, value: period }));
    }

    /** @description The "to" end, with everything before the chosen "from" removed. */
    get toOptions() {
        return this.periodAxis
            .filter((period) => !this.periodFrom || period >= this.periodFrom)
            .map((period) => ({ label: period, value: period }));
    }

    /**
     * @description The periods that actually exist on the axis inside the chosen range. The server
     * is handed this explicit list, never the range itself, so a period that is not on the axis can
     * never be swept into a payout.
     * @return {String[]} The selected periods, oldest first.
     */
    get selectedPeriods() {
        if (!this.periodFrom || !this.periodTo) {
            return [];
        }
        return this.periodAxis.filter(
            (period) => period >= this.periodFrom && period <= this.periodTo
        );
    }

    /**
     * @description The client-side preview of what the selected range holds, so the numbers are on
     * screen before the review modal is opened. The server recomputes them authoritatively.
     * @return {Object} The folded open totals for the selection.
     */
    get selectionTotals() {
        const agent = this.selectedAgent;
        if (!agent) {
            return { ...EMPTY_CELL };
        }
        return this.foldPeriods(agent, this.periodIndex, this.selectedPeriods);
    }

    get selectionCarrierNet() {
        return this.moneyView(this.selectionTotals.openNet);
    }

    get selectionPayable() {
        // No emphasis class here: the panel's own `_primary` rule already sizes this figure, and a
        // second font-size on the inner span would quietly shrink it back down.
        return this.moneyView(this.selectionTotals.openPayable);
    }

    get selectionUnratedCount() {
        return this.selectionTotals.openUnratedLineCount;
    }

    get hasSelectionUnrated() {
        return this.selectionTotals.openUnratedLineCount > 0;
    }

    get selectionUnratedNet() {
        return this.moneyView(this.selectionTotals.openUnratedNet);
    }

    get isReviewDisabled() {
        return this.isSaving || !this.canRecord || this.selectedPeriods.length === 0;
    }

    /**
     * @description The selected agent's payouts as the server sent them, newest first, each
     * carrying whether this user may still void it.
     * @return {Object[]} One descriptor per payout.
     */
    get payoutHistory() {
        const agent = this.selectedAgent;
        if (!agent || !agent.payouts) {
            return [];
        }
        return agent.payouts.map((payout) => ({
            ...payout,
            key: payout.payoutId,
            money: this.moneyView(payout.amountPaid),
            isVoided: payout.status === 'Voided',
            isVoidable: payout.status !== 'Voided' && this.canVoid
        }));
    }

    get hasPayoutHistory() {
        return this.payoutHistory.length > 0;
    }

    handlePresetChange(event) {
        this.preset = event.currentTarget.dataset.preset;
        this.closeDrill();
    }

    /**
     * @description Selects an agent and pre-fills the range with everything still outstanding, from
     * their oldest unpaid period through the newest period on the axis.
     * @param {Event} event The click on the agent's lead-cell button.
     */
    handleSelectAgent(event) {
        const agentId = event.currentTarget.dataset.agent;
        this.selectedAgentId = agentId;
        this.selectionError = undefined;
        const agent = this.agents.find((candidate) => candidate.agentId === agentId);
        const axis = this.periodAxis;
        this.periodFrom = (agent && agent.oldestUnpaidPeriod) || axis[0] || '';
        this.periodTo = this.latestPeriod || axis[axis.length - 1] || '';
    }

    /**
     * @description Opens the drill-down for one cell: the lines the server holds for that agent and
     * the periods the column covers. The list is read from `getLines`, never reconstructed from a
     * preflight, so a cell can be inspected without proposing a payout.
     * @param {Event} event The click on a state cell.
     */
    async handleDrill(event) {
        const agentId = event.currentTarget.dataset.agent;
        const periods = (event.currentTarget.dataset.periods || '').split(',').filter(Boolean);
        this.drillCaption = event.currentTarget.dataset.caption;
        this.drillError = undefined;
        this.drillLines = [];
        this.showDrill = true;
        this.isDrillLoading = true;
        try {
            const lines = await getLines({ agentId, periods });
            this.drillLines = lines || [];
        } catch (error) {
            this.drillError = reduceErrors(error).join(', ') || this.label.loadError;
        } finally {
            this.isDrillLoading = false;
        }
    }

    handleCloseDrill() {
        this.closeDrill();
    }

    /** @description Drops the drill-down, which is stale the moment lines are stamped or released. */
    closeDrill() {
        this.showDrill = false;
        this.isDrillLoading = false;
        this.drillLines = [];
        this.drillCaption = '';
        this.drillError = undefined;
    }

    handleFromChange(event) {
        this.periodFrom = event.detail.value;
        this.selectionError = undefined;
        if (this.periodTo && this.periodTo < this.periodFrom) {
            this.periodTo = this.periodFrom;
        }
    }

    handleToChange(event) {
        this.periodTo = event.detail.value;
        this.selectionError = undefined;
    }

    /**
     * @description Checks the selection before any server call is made.
     * @return {Boolean} True when the selection can be sent for preflight.
     */
    validateSelection() {
        if (!this.selectedAgentId) {
            this.selectionError = this.label.agentRequired;
            return false;
        }
        if (!this.periodFrom || !this.periodTo) {
            this.selectionError = this.label.periodRequired;
            return false;
        }
        if (
            !PERIOD_PATTERN.test(this.periodFrom) ||
            !PERIOD_PATTERN.test(this.periodTo) ||
            this.periodFrom > this.periodTo
        ) {
            this.selectionError = this.label.periodInvalid;
            return false;
        }
        if (this.selectedPeriods.length === 0) {
            this.selectionError = this.label.periodRequired;
            return false;
        }
        if (this.selectionTotals.openLineCount === 0) {
            this.selectionError = this.label.nothingToPay;
            return false;
        }
        this.selectionError = undefined;
        return true;
    }

    /**
     * @description Asks the server what the selection actually contains and opens the review modal
     * on the answer.
     */
    async handleReview() {
        if (!this.validateSelection()) {
            return;
        }
        this.isSaving = true;
        try {
            const preflight = await this.runPreflight();
            if (!preflight || !preflight.lineCount) {
                this.selectionError = this.label.nothingToPay;
                return;
            }
            this.reviewError = undefined;
            this.showReview = true;
        } catch (error) {
            this.selectionError = reduceErrors(error).join(', ') || this.label.loadError;
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * @description Runs the preflight for the current selection and stores the answer. The request
     * crosses as one JSON string and the answer comes back as one, so nothing reactive is ever
     * serialized across the Apex boundary.
     * @return {Promise<Object>} The parsed PreflightDto.
     */
    async runPreflight() {
        const request = {
            agentId: this.selectedAgentId,
            periodStart: this.periodFrom,
            periodEnd: this.periodTo,
            periods: this.selectedPeriods.map((period) => period)
        };
        const raw = await getPreflightJson({ requestJson: JSON.stringify(request) });
        this.preflight = raw ? JSON.parse(raw) : undefined;
        return this.preflight;
    }

    handleCloseReview() {
        this.showReview = false;
        this.reviewError = undefined;
        this.preflight = undefined;
        this._reviewReturn = true;
    }

    /**
     * @description Records the payout the review modal collected, stamping the open lines it left
     * ticked. The modal owns the include/exclude decision and the three totals that go with it;
     * this container forwards them untouched, so the numbers the server checks are exactly the
     * numbers the owner confirmed. Recomputing them here would defeat the guard.
     * @param {CustomEvent} event The child's `recordpayout` event, carrying the form as JSON.
     */
    async handleRecordPayout(event) {
        this.isSaving = true;
        this.reviewError = undefined;
        try {
            // Read inside the try: an event that arrives with no detail, or with a payload that is
            // not JSON, has to land in the catch and say so rather than reject this handler with
            // nothing to catch it and leave the owner's click doing nothing. A payload that never
            // arrived is refused here rather than sent on — the three expected totals ARE the
            // guard, and an empty form carries none of them.
            const detail = event.detail || {};
            if (!detail.formJson) {
                throw new Error(this.label.saveError);
            }
            const form = JSON.parse(detail.formJson);
            const request = {
                agentId: this.selectedAgentId,
                periodStart: this.periodFrom,
                periodEnd: this.periodTo,
                periods: this.selectedPeriods.map((period) => period),
                excludedLineIds: Array.isArray(form.excludedLineIds) ? form.excludedLineIds : [],
                expectedLineCount: form.expectedLineCount,
                expectedLinesNetAmount: form.expectedLinesNetAmount,
                expectedPayableAmount: form.expectedPayableAmount,
                amountPaid: form.amountPaid,
                paidDate: form.paidDate,
                paymentMethod: form.paymentMethod,
                referenceNumber: form.referenceNumber,
                notes: form.notes
            };
            await createPayoutJson({ requestJson: JSON.stringify(request) });
            this.dispatchEvent(
                new ShowToastEvent({ title: this.label.recordPayout, variant: 'success' })
            );
            this.showReview = false;
            this.preflight = undefined;
            this._reviewReturn = true;
            this.closeDrill();
            await refreshApex(this.wiredBoard);
        } catch (error) {
            this.reviewError = reduceErrors(error).join(', ') || this.label.saveError;
            // Re-read the selection so the modal shows what the server now believes. Handing the
            // child a different set of numbers re-arms its confirmation gate.
            await this.refreshPreflightQuietly();
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * @description Re-runs the preflight without surfacing a second error, so a failed save leaves
     * the modal showing current numbers rather than stale ones.
     */
    async refreshPreflightQuietly() {
        try {
            await this.runPreflight();
        } catch (error) {
            this.reviewError = reduceErrors(error).join(', ') || this.label.loadError;
        }
    }

    handleVoidClick(event) {
        this.voidTargetId = event.currentTarget.dataset.payout;
        this.voidTargetName = event.currentTarget.dataset.name;
        this.voidReason = '';
        this.voidError = undefined;
        this.showVoidModal = true;
        this._voidFocused = false;
    }

    handleVoidReasonChange(event) {
        this.voidReason = event.currentTarget.value;
        this.voidError = undefined;
    }

    closeVoidModal() {
        // Remembered before the target is cleared, so focus can go back to the button that opened
        // the dialog rather than to the top of the page.
        this._voidReturnId = this.voidTargetId;
        this.showVoidModal = false;
        this._voidFocused = false;
        this.voidTargetId = undefined;
        this.voidTargetName = undefined;
        this.voidReason = '';
        this.voidError = undefined;
    }

    /**
     * @description Keeps the void dialog behaving like a dialog from the keyboard: Escape dismisses
     * it and Tab cycles inside it instead of walking out into the board behind the backdrop.
     * @param {KeyboardEvent} event The key press inside the dialog.
     */
    handleVoidKeyDown(event) {
        if (event.key === 'Escape') {
            if (!this.isSaving) {
                this.closeVoidModal();
            }
            return;
        }
        if (event.key === 'Tab') {
            this.trapTab(event);
        }
    }

    /**
     * @description Wraps Tab and Shift+Tab around the focusable elements of the open dialog.
     * @param {KeyboardEvent} event The Tab key press.
     */
    trapTab(event) {
        const dialog = this.template.querySelector('[role="dialog"]');
        if (!dialog) {
            return;
        }
        const focusable = [...dialog.querySelectorAll(FOCUSABLE)].filter(
            (node) => node.disabled !== true
        );
        if (focusable.length === 0) {
            return;
        }
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const active = this.template.activeElement;
        if (event.shiftKey && active === first) {
            event.preventDefault();
            this.focusNode(last);
        } else if (!event.shiftKey && active === last) {
            event.preventDefault();
            this.focusNode(first);
        }
    }

    /**
     * @description Focuses a node when it can take focus. Guarded because the stubs a unit test
     * renders in place of a base component may not implement `focus`.
     * @param {HTMLElement} node The node to focus.
     */
    focusNode(node) {
        if (node && typeof node.focus === 'function') {
            node.focus();
        }
    }

    /**
     * @description Moves focus into the void dialog when it opens and back to the button that
     * opened it when it closes, and returns focus to Review when the review modal closes. Guarded
     * on both sides so a re-render never steals focus from where the owner has moved it.
     */
    renderedCallback() {
        if (this.showVoidModal && !this._voidFocused) {
            const reason = this.template.querySelector('lightning-textarea[data-id="void-reason"]');
            if (reason) {
                this._voidFocused = true;
                this.focusNode(reason);
            }
        } else if (!this.showVoidModal && this._voidReturnId) {
            const trigger = this.template.querySelector(
                `lightning-button[data-id="void"][data-payout="${this._voidReturnId}"]`
            );
            this._voidReturnId = undefined;
            this.focusNode(trigger);
        }
        if (!this.showReview && this._reviewReturn) {
            this._reviewReturn = false;
            this.focusNode(this.template.querySelector('lightning-button[data-id="review"]'));
        }
    }

    /**
     * @description Voids a payout, releasing its lines back to unpaid. The reason is mandatory —
     * the record carries a validation rule that refuses a voided payout with no note.
     */
    async handleConfirmVoid() {
        if (!this.voidReason || !this.voidReason.trim()) {
            this.voidError = this.label.voidReasonRequired;
            return;
        }
        this.isSaving = true;
        try {
            await voidPayout({ payoutId: this.voidTargetId, reason: this.voidReason });
            this.dispatchEvent(new ShowToastEvent({ title: this.label.void, variant: 'success' }));
            this.closeVoidModal();
            this.closeDrill();
            await refreshApex(this.wiredBoard);
        } catch (error) {
            this.voidError = reduceErrors(error).join(', ') || this.label.saveError;
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * @description Shows a normalized error as a toast.
     * @param {*} error The wire or imperative error.
     * @param {String} fallback The label to show when the error carries no readable message.
     */
    notifyError(error, fallback) {
        const message = reduceErrors(error).join(', ');
        this.dispatchEvent(
            new ShowToastEvent({ title: fallback, message, variant: 'error' })
        );
    }
}
