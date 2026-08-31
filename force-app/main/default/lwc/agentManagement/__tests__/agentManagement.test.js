import { createElement } from 'lwc';
import AgentManagement from 'c/agentManagement';
import getBoard from '@salesforce/apex/AgentPayoutController.getBoard';
import getAccess from '@salesforce/apex/AgentPayoutController.getAccess';
import getMethodOptions from '@salesforce/apex/AgentPayoutController.getMethodOptions';
import getPreflightJson from '@salesforce/apex/AgentPayoutController.getPreflightJson';
import createPayoutJson from '@salesforce/apex/AgentPayoutController.createPayoutJson';
import voidPayout from '@salesforce/apex/AgentPayoutController.voidPayout';
import getLines from '@salesforce/apex/AgentPayoutController.getLines';

// Imperative Apex is mocked; the cacheable reads consumed through @wire (getBoard, getAccess,
// getMethodOptions) are auto-mocked as test wire adapters by sfdx-lwc-jest. getLines is cacheable
// but called imperatively for the drill-down, so it is mocked as a function.
jest.mock(
    '@salesforce/apex/AgentPayoutController.getPreflightJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AgentPayoutController.createPayoutJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AgentPayoutController.voidPayout',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/AgentPayoutController.getLines',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const PERIODS = [
    '2025-01', '2025-02', '2025-03', '2025-04', '2025-05', '2025-06',
    '2025-07', '2025-08', '2025-09', '2025-10', '2025-11', '2025-12',
    '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07'
];

const HALVES = [
    {
        key: '2025-H1',
        label: '2025-H1',
        periods: ['2025-01', '2025-02', '2025-03', '2025-04', '2025-05', '2025-06'],
        inProgress: false
    },
    {
        key: '2025-H2',
        label: '2025-H2',
        periods: ['2025-07', '2025-08', '2025-09', '2025-10', '2025-11', '2025-12'],
        inProgress: false
    },
    {
        key: '2026-H1',
        label: '2026-H1',
        periods: ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06'],
        inProgress: false
    },
    { key: '2026-H2', label: '2026-H2', periods: ['2026-07'], inProgress: true }
];

/**
 * CellDto is DENSE and ASCENDING: exactly one entry per meta.periods entry, in the same order, and
 * every one of them carries the state the server decided.
 */
function cells(overrides) {
    return PERIODS.map((period) => ({
        period,
        state: 'NO_DATA',
        totalLineCount: 0,
        totalNet: 0,
        openLineCount: 0,
        openNet: 0,
        openPayable: 0,
        openUnratedLineCount: 0,
        openUnratedNet: 0,
        paidLineCount: 0,
        covered: false,
        ...(overrides[period] || {})
    }));
}

const AGENT_OPEN = {
    agentId: '001AGENT1',
    agentName: 'Peter Kang',
    sortName: 'kang peter',
    outstandingNet: 420.5,
    outstandingPayable: 210.25,
    outstandingLineCount: 4,
    unratedLineCount: 0,
    unratedNet: 0,
    oldestUnpaidPeriod: '2026-05',
    lateLineCount: 0,
    latePeriodCount: 0,
    hasLateLines: false,
    lastPaidDate: '2026-04-30',
    lastPaidAmount: 800,
    lastPayoutId: 'a0X1',
    lastPayoutName: 'AP-202604-0001',
    deltaPerMonth: 12.5,
    cells: cells({
        // The server calls this one ORPHAN_PAID; the folded-cell rules would call it PAID. The
        // monthly board must show what the server said.
        '2026-04': { state: 'ORPHAN_PAID', totalLineCount: 1, totalNet: 100, paidLineCount: 1 },
        '2026-05': {
            state: 'UNPAID',
            totalLineCount: 2,
            totalNet: 200.5,
            openLineCount: 2,
            openNet: 200.5,
            openPayable: 100.25
        },
        '2026-06': {
            state: 'UNPAID',
            totalLineCount: 2,
            totalNet: 220,
            openLineCount: 2,
            openNet: 220,
            openPayable: 110
        }
    }),
    payouts: [
        {
            payoutId: 'a0X1',
            name: 'AP-202604-0001',
            periodLabel: '2026-01 ~ 2026-04',
            paidDate: '2026-04-30',
            amountPaid: 800,
            status: 'Paid',
            lineCount: 9
        }
    ]
};

const AGENT_LATE = {
    agentId: '001AGENT2',
    agentName: 'Dana Kim',
    sortName: 'kim dana',
    outstandingNet: 55,
    outstandingPayable: 0,
    outstandingLineCount: 3,
    unratedLineCount: 3,
    unratedNet: 55,
    oldestUnpaidPeriod: '2026-02',
    lateLineCount: 3,
    latePeriodCount: 1,
    hasLateLines: true,
    lastPaidDate: '2026-03-31',
    lastPaidAmount: 120,
    lastPayoutId: 'a0X9',
    lastPayoutName: 'AP-202603-0009',
    deltaPerMonth: null,
    cells: cells({
        '2026-02': {
            state: 'LATE_LINES',
            totalLineCount: 3,
            totalNet: 55,
            openLineCount: 3,
            openNet: 55,
            openUnratedLineCount: 3,
            openUnratedNet: 55,
            covered: true
        }
    }),
    payouts: []
};

const BOARD = {
    meta: { latestPeriod: '2026-07', periods: PERIODS, halves: HALVES },
    agents: [AGENT_OPEN, AGENT_LATE]
};

const ACCESS_FULL = { canRead: true, canRecord: true, canVoid: true };

const PREFLIGHT = {
    agentId: '001AGENT1',
    agentName: 'Peter Kang',
    periodStart: '2026-05',
    periodEnd: '2026-06',
    periods: ['2026-05', '2026-06'],
    periodLabel: '2026-05 ~ 2026-06',
    lineCount: 4,
    linesNetAmount: 420.5,
    chargebackAmount: -20,
    chargebackLineCount: 1,
    computedPayable: 210.25,
    unratedLineCount: 0,
    unratedNetAmount: 0,
    lateLineCount: 0,
    alreadyStampedLineCount: 0,
    coveredPeriods: [],
    payableLines: [],
    lateLines: [],
    chargebackLines: [],
    alreadyStampedLines: [],
    rateMissingLines: []
};

const LINE = {
    lineId: 'a0L1',
    lineName: 'CL-00001',
    period: '2026-05',
    commissionDate: '2026-05-14',
    clientName: 'Jong H Yi',
    clientCompany: '',
    policyId: 'a0P1',
    policyName: 'H-10021',
    carrierName: 'Ambetter',
    commissionAmount: 28.91,
    rate: 50,
    payableAmount: 14.46,
    rateMissing: false,
    paidOut: false,
    payoutId: null,
    payoutName: null
};

function flushPromises() {
    return Promise.resolve();
}

function createComponent() {
    const element = createElement('c-agent-management', { is: AgentManagement });
    document.body.appendChild(element);
    return element;
}

async function renderBoard(element, board = BOARD, access = ACCESS_FULL) {
    getAccess.emit(access);
    getMethodOptions.emit([{ label: 'Check', value: 'Check' }]);
    getBoard.emit(board);
    await flushPromises();
}

async function selectAgent(element, agentId) {
    const button = element.shadowRoot.querySelector(`button[data-agent="${agentId}"][data-id="agent-row"]`);
    button.click();
    await flushPromises();
}

async function choosePreset(element, index) {
    element.shadowRoot.querySelectorAll('lightning-button[data-id="preset"]')[index].click();
    await flushPromises();
}

describe('c-agent-management', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders one board row per subagent', async () => {
        const element = createComponent();
        await renderBoard(element);

        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(2);
    });

    it('shows a spinner rather than an empty table before the board answers', async () => {
        const element = createComponent();
        getAccess.emit(ACCESS_FULL);
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
        expect(element.shadowRoot.querySelector('table')).toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="board-empty"]')).toBeNull();

        getBoard.emit(BOARD);
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
        expect(element.shadowRoot.querySelector('table')).not.toBeNull();
    });

    it('shows the empty state and what to do next when no subagent has commission lines', async () => {
        const element = createComponent();
        await renderBoard(element, {
            meta: { latestPeriod: null, periods: [], halves: [] },
            agents: []
        });

        expect(element.shadowRoot.querySelector('table')).toBeNull();
        const empty = element.shadowRoot.querySelector('[data-id="board-empty"]');
        expect(empty).not.toBeNull();
        // Not just "no data": the empty state tells the owner what would put an agent here.
        expect(empty.querySelector('.board-empty__help')).not.toBeNull();
    });

    it('surfaces an error toast and an inline error region when the board wire fails', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        getBoard.error();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    });

    it('shows the error region instead of the board when access says the user may not read', async () => {
        const element = createComponent();
        await renderBoard(element, BOARD, { canRead: false, canRecord: false, canVoid: false });

        expect(element.shadowRoot.querySelector('table')).toBeNull();
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    });

    it('tells a refused user it is a permission problem, not a failed load to retry', async () => {
        const element = createComponent();
        await renderBoard(element, BOARD, { canRead: false, canRecord: false, canVoid: false });

        // A successful probe that answered canRead:false is not a load failure, and must not offer
        // the "try again shortly" message that invites the owner to retry forever.
        expect(element.shadowRoot.querySelector('.board-notice_denied')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.board-notice_error')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-spinner')).toBeNull();
    });

    it('separates a failed load from a refusal', async () => {
        const element = createComponent();
        getAccess.emit(ACCESS_FULL);
        getBoard.error();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.board-notice_error')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.board-notice_denied')).toBeNull();
    });

    it('reports a failed payment-method load rather than leaving the picklist silently empty', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        getMethodOptions.error();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
    });

    it('counts PERIODS in the badge beside the agent name and LINES in the late column', async () => {
        const element = createComponent();
        await renderBoard(element);

        const lateRow = element.shadowRoot.querySelector('button[data-agent="001AGENT2"][data-id="agent-row"]');
        const badge = lateRow.querySelector('.board-late lightning-formatted-number');
        expect(badge.value).toBe(1);

        const lateCell = element.shadowRoot
            .querySelectorAll('tbody tr')[1]
            .querySelector('td .cell_late lightning-formatted-number');
        expect(lateCell.value).toBe(3);

        const cleanRow = element.shadowRoot.querySelector('button[data-agent="001AGENT1"][data-id="agent-row"]');
        expect(cleanRow.querySelector('.board-late')).toBeNull();
    });

    it('shows the carrier net and the payable side by side, each labelled', async () => {
        const element = createComponent();
        await renderBoard(element);

        // Asserted structurally, not on the rendered label text: sfdx-lwc-jest resolves
        // `@salesforce/label/c.Foo` to the literal string "c.Foo", so a value assertion here could
        // never pass. The two money columns and their order are the behaviour that matters.
        const headers = [...element.shadowRoot.querySelectorAll('thead th.col-money')];
        expect(headers).toHaveLength(2);
        expect(headers[0].classList.contains('col-money_primary')).toBe(true);

        const money = element.shadowRoot
            .querySelectorAll('tbody tr')[0]
            .querySelectorAll('lightning-formatted-number');
        expect(money[0].value).toBe(420.5);
        expect(money[1].value).toBe(210.25);
    });

    it('lays out one column per preset and folds halves client-side', async () => {
        const element = createComponent();
        await renderBoard(element);

        // Agent, outstanding, payable, oldest unpaid, late, last paid.
        expect(element.shadowRoot.querySelectorAll('thead th')).toHaveLength(6);

        await choosePreset(element, 1);
        // Thirteen rolling months plus the two money columns and the pinned agent column.
        expect(element.shadowRoot.querySelectorAll('thead th')).toHaveLength(16);

        await choosePreset(element, 2);
        // Four halves plus delta, the two money columns and the pinned agent column.
        expect(element.shadowRoot.querySelectorAll('thead th')).toHaveLength(8);
    });

    it('takes the monthly state from the server rather than re-deriving it', async () => {
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 1);

        // 2026-04 has one paid line and no open ones: the folded rules would call it PAID, but the
        // server stamped ORPHAN_PAID and the monthly board must show that.
        expect(element.shadowRoot.querySelector('tbody .cell_orphan')).not.toBeNull();
        // The covered period holding open lines is a late arrival.
        expect(element.shadowRoot.querySelectorAll('tbody .cell_late').length).toBeGreaterThan(0);
    });

    it('re-derives the state of a folded half from the months inside it', async () => {
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 2);

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        // 2026-H1 folds two unpaid months for the first agent...
        expect(rows[0].querySelector('.cell_unpaid')).not.toBeNull();
        // ...and one covered month still holding open lines for the second.
        expect(rows[1].querySelector('.cell_late')).not.toBeNull();
    });

    it('shows the delta the server computed and says so when it has none', async () => {
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 2);

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        const deltaCell = rows[0].querySelectorAll('td')[4];
        expect(deltaCell.querySelector('lightning-formatted-number').value).toBe(12.5);
        expect(rows[1].querySelectorAll('td')[4].querySelector('.cell-quiet')).not.toBeNull();
    });

    it('always renders the legend rather than hiding the glyph key behind a tooltip', async () => {
        const element = createComponent();
        await renderBoard(element);

        expect(element.shadowRoot.querySelectorAll('.board-legend__item')).toHaveLength(7);
    });

    it('reads the lines behind a cell from getLines rather than from a preflight', async () => {
        getLines.mockResolvedValue([LINE]);
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 1);

        element.shadowRoot.querySelector('button[data-id="cell"]').click();
        await flushPromises();
        await flushPromises();

        expect(getPreflightJson).not.toHaveBeenCalled();
        expect(getLines).toHaveBeenCalledTimes(1);
        const call = getLines.mock.calls[0][0];
        expect(call.agentId).toBe('001AGENT1');
        expect(call.periods).toEqual(['2026-04']);

        const table = element.shadowRoot.querySelector('c-agent-line-table[data-id="drill-lines"]');
        expect(table).not.toBeNull();
        expect(table.lines).toHaveLength(1);
    });

    it('does not offer a drill-down on a cell with no lines behind it', async () => {
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 1);

        // Thirteen month columns across two rows, of which four hold lines.
        expect(element.shadowRoot.querySelectorAll('button[data-id="cell"]')).toHaveLength(4);
    });

    it('reports a failed drill-down inline instead of showing an empty list', async () => {
        getLines.mockRejectedValue({ body: { message: 'boom' } });
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 1);

        element.shadowRoot.querySelector('button[data-id="cell"]').click();
        await flushPromises();
        await flushPromises();

        const alert = element.shadowRoot.querySelector('.board-drill [role="alert"]');
        expect(alert.textContent).toContain('boom');
        expect(element.shadowRoot.querySelector('c-agent-line-table[data-id="drill-lines"]')).toBeNull();
    });

    it('closes the drill-down on request', async () => {
        getLines.mockResolvedValue([LINE]);
        const element = createComponent();
        await renderBoard(element);
        await choosePreset(element, 1);

        element.shadowRoot.querySelector('button[data-id="cell"]').click();
        await flushPromises();
        await flushPromises();
        element.shadowRoot.querySelector('lightning-button-icon[data-id="drill-close"]').click();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.board-drill')).toBeNull();
    });

    it('opens the period pickers seeded from the oldest unpaid period when a row is chosen', async () => {
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        const from = element.shadowRoot.querySelector('lightning-combobox[data-id="period-from"]');
        const to = element.shadowRoot.querySelector('lightning-combobox[data-id="period-to"]');
        expect(from.value).toBe('2026-05');
        expect(to.value).toBe('2026-07');
        // The "to" picker never offers a period before the chosen "from".
        expect(to.options.every((option) => option.value >= '2026-05')).toBe(true);
    });

    it('sends an explicit list of periods, never a range, to the preflight', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        element.shadowRoot
            .querySelector('lightning-combobox[data-id="period-to"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '2026-06' } }));
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button[data-id="review"]').click();
        await flushPromises();

        expect(getPreflightJson).toHaveBeenCalledTimes(1);
        const request = JSON.parse(getPreflightJson.mock.calls[0][0].requestJson);
        expect(request.agentId).toBe('001AGENT1');
        expect(request.periodStart).toBe('2026-05');
        expect(request.periodEnd).toBe('2026-06');
        expect(request.periods).toEqual(['2026-05', '2026-06']);
    });

    it('hands the parsed preflight to the review modal', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        element.shadowRoot.querySelector('lightning-button[data-id="review"]').click();
        await flushPromises();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('c-agent-payout-review');
        expect(modal.preflight.lineCount).toBe(4);
        expect(modal.preflight.computedPayable).toBe(210.25);
    });

    it('blocks the review and explains itself when the selection holds no unpaid lines', async () => {
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        element.shadowRoot
            .querySelector('lightning-combobox[data-id="period-from"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '2025-01' } }));
        element.shadowRoot
            .querySelector('lightning-combobox[data-id="period-to"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '2025-02' } }));
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button[data-id="review"]').click();
        await flushPromises();

        expect(getPreflightJson).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.board-selection [role="alert"]')).not.toBeNull();
    });

    /**
     * Drives the board as far as an open review modal, then hands it the payload the modal would
     * have emitted, so the container can be checked on what it forwards.
     */
    async function recordFromModal(element, form) {
        await selectAgent(element, '001AGENT1');
        element.shadowRoot
            .querySelector('lightning-combobox[data-id="period-to"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: '2026-06' } }));
        await flushPromises();
        element.shadowRoot.querySelector('lightning-button[data-id="review"]').click();
        await flushPromises();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('c-agent-payout-review');
        expect(modal).not.toBeNull();
        modal.dispatchEvent(
            new CustomEvent('recordpayout', { detail: { formJson: JSON.stringify(form) } })
        );
        await flushPromises();
        return modal;
    }

    it('echoes the three expected totals back as the stale-totals guard', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        createPayoutJson.mockResolvedValue('a0X2');
        const element = createComponent();
        await renderBoard(element);

        await recordFromModal(element, {
            amountPaid: 210.25,
            paidDate: '2026-08-16',
            paymentMethod: 'Check',
            referenceNumber: '1042',
            notes: '',
            excludedLineIds: [],
            expectedLineCount: 4,
            expectedLinesNetAmount: 420.5,
            expectedPayableAmount: 210.25
        });

        expect(createPayoutJson).toHaveBeenCalledTimes(1);
        const request = JSON.parse(createPayoutJson.mock.calls[0][0].requestJson);
        expect(request.periods).toEqual(['2026-05', '2026-06']);
        expect(request.amountPaid).toBe(210.25);
        expect(request.expectedLineCount).toBe(4);
        expect(request.expectedLinesNetAmount).toBe(420.5);
        expect(request.expectedPayableAmount).toBe(210.25);
        expect(request.excludedLineIds).toEqual([]);
        // The fingerprint is gone: the three totals are the whole guard.
        expect(request.fingerprint).toBeUndefined();
    });

    it('forwards the modal exclusions and its totals without recomputing either', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        createPayoutJson.mockResolvedValue('a0X2');
        const element = createComponent();
        await renderBoard(element);

        await recordFromModal(element, {
            amountPaid: 150.25,
            paidDate: '2026-08-16',
            paymentMethod: 'Check',
            referenceNumber: '',
            notes: '',
            excludedLineIds: ['a0L2'],
            expectedLineCount: 3,
            expectedLinesNetAmount: 300.5,
            expectedPayableAmount: 150.25
        });

        const request = JSON.parse(createPayoutJson.mock.calls[0][0].requestJson);
        expect(request.excludedLineIds).toEqual(['a0L2']);
        // The container must not fall back on the preflight's all-included totals.
        expect(request.expectedLineCount).toBe(3);
        expect(request.expectedLinesNetAmount).toBe(300.5);
        expect(request.expectedPayableAmount).toBe(150.25);
    });

    it('sends an empty exclusion list when the modal names none', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        createPayoutJson.mockResolvedValue('a0X2');
        const element = createComponent();
        await renderBoard(element);

        await recordFromModal(element, {
            amountPaid: 210.25,
            expectedLineCount: 4,
            expectedLinesNetAmount: 420.5,
            expectedPayableAmount: 210.25
        });

        const request = JSON.parse(createPayoutJson.mock.calls[0][0].requestJson);
        expect(request.excludedLineIds).toEqual([]);
    });

    it('reports a rejected save inline and re-reads the selection', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        createPayoutJson.mockRejectedValue({
            body: { message: '화면의 금액이 최신이 아닙니다.' }
        });
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');
        element.shadowRoot.querySelector('lightning-button[data-id="review"]').click();
        await flushPromises();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('c-agent-payout-review');
        modal.dispatchEvent(
            new CustomEvent('recordpayout', { detail: { formJson: JSON.stringify({ amountPaid: 1 }) } })
        );
        await flushPromises();
        await flushPromises();
        await flushPromises();

        expect(createPayoutJson).toHaveBeenCalledTimes(1);
        // The selection is re-read so the modal never keeps showing numbers the save rejected, and
        // the message the server gave is handed straight to it.
        expect(getPreflightJson).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelector('c-agent-payout-review').errorMessage).toContain(
            '최신이 아닙니다'
        );
    });

    it('reports a recordpayout event that carries no usable detail instead of dying silently', async () => {
        getPreflightJson.mockResolvedValue(JSON.stringify(PREFLIGHT));
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');
        element.shadowRoot.querySelector('lightning-button[data-id="review"]').click();
        await flushPromises();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('c-agent-payout-review');
        modal.dispatchEvent(new CustomEvent('recordpayout'));
        await flushPromises();
        await flushPromises();
        await flushPromises();

        // No write is attempted, and the failure reaches the owner rather than rejecting the
        // handler with nothing to catch it.
        expect(createPayoutJson).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('c-agent-payout-review').errorMessage).toBeTruthy();
    });

    it('moves focus into the void dialog and back to the button that opened it', async () => {
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        const trigger = element.shadowRoot.querySelector('lightning-button[data-id="void"]');
        const triggerFocus = jest.spyOn(trigger, 'focus');
        trigger.click();
        await flushPromises();

        const reason = element.shadowRoot.querySelector('lightning-textarea[data-id="void-reason"]');
        expect(reason).not.toBeNull();

        reason.dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, composed: true })
        );
        await flushPromises();

        expect(element.shadowRoot.querySelector('[role="dialog"]')).toBeNull();
        expect(triggerFocus).toHaveBeenCalled();
    });

    it('does not let Escape dismiss the void dialog while the void is being written', async () => {
        let resolveVoid;
        voidPayout.mockImplementation(
            () =>
                new Promise((resolve) => {
                    resolveVoid = resolve;
                })
        );
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        element.shadowRoot.querySelector('lightning-button[data-id="void"]').click();
        await flushPromises();
        const reason = element.shadowRoot.querySelector('lightning-textarea[data-id="void-reason"]');
        reason.value = 'wrong period';
        reason.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="confirm-void"]').click();
        await flushPromises();

        element.shadowRoot
            .querySelector('[role="dialog"]')
            .dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        await flushPromises();

        expect(element.shadowRoot.querySelector('[role="dialog"]')).not.toBeNull();
        resolveVoid();
    });

    it('refuses to void a payout without a reason', async () => {
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        element.shadowRoot.querySelector('lightning-button[data-id="void"]').click();
        await flushPromises();
        element.shadowRoot.querySelector('button[data-id="confirm-void"]').click();
        await flushPromises();

        expect(voidPayout).not.toHaveBeenCalled();
    });

    it('voids a payout once a reason is given', async () => {
        voidPayout.mockResolvedValue();
        const element = createComponent();
        await renderBoard(element);
        await selectAgent(element, '001AGENT1');

        element.shadowRoot.querySelector('lightning-button[data-id="void"]').click();
        await flushPromises();

        const reason = element.shadowRoot.querySelector('lightning-textarea[data-id="void-reason"]');
        reason.value = 'wrong period';
        reason.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('button[data-id="confirm-void"]').click();
        await flushPromises();

        expect(voidPayout).toHaveBeenCalledWith({
            payoutId: 'a0X1',
            reason: 'wrong period'
        });
    });

    it('lists the payouts the server sent and hides the void action without canVoid', async () => {
        const element = createComponent();
        await renderBoard(element, BOARD, { canRead: true, canRecord: true, canVoid: false });
        await selectAgent(element, '001AGENT1');

        expect(element.shadowRoot.querySelectorAll('.board-history__row')).toHaveLength(1);
        expect(element.shadowRoot.querySelector('.board-history__name').textContent).toBe(
            'AP-202604-0001'
        );
        expect(element.shadowRoot.querySelector('lightning-button[data-id="void"]')).toBeNull();
    });

    it('keeps the review action disabled when the user may not record payouts', async () => {
        const element = createComponent();
        await renderBoard(element, BOARD, { canRead: true, canRecord: false, canVoid: false });
        await selectAgent(element, '001AGENT1');

        expect(element.shadowRoot.querySelector('lightning-button[data-id="review"]').disabled).toBe(
            true
        );
    });
});
