import { createElement } from 'lwc';
import AgentPayoutReview from 'c/agentPayoutReview';

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

/**
 * Every open line in the selection, as the server sends them: three rated lines and one chargeback.
 * Their figures are exactly the totals BASE_PREFLIGHT carries, so the client can be checked against
 * the server's own arithmetic.
 *   200.50 + 120.00 + 120.00 + (-20.00) = 420.50 carrier net
 *   100.25 +  60.00 +  60.00 + (-10.00) = 210.25 payable
 */
const PAYABLE_LINES = [
    { ...LINE, lineId: 'a0L1', period: '2026-05', commissionAmount: 200.5, payableAmount: 100.25 },
    { ...LINE, lineId: 'a0L2', period: '2026-05', commissionAmount: 120, payableAmount: 60 },
    { ...LINE, lineId: 'a0L3', period: '2026-06', commissionAmount: 120, payableAmount: 60 },
    { ...LINE, lineId: 'a0L4', period: '2026-06', commissionAmount: -20, payableAmount: -10 }
];

// PreflightDto, exactly as getPreflightJson serializes it. Every total is computed over ALL open
// lines — the everything-included default the client subtracts from.
const BASE_PREFLIGHT = {
    agentId: '001AGENT1',
    agentName: 'Peter Kang',
    periodLabel: '2026-05 ~ 2026-06',
    periodStart: '2026-05',
    periodEnd: '2026-06',
    periods: ['2026-05', '2026-06'],
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
    payableLines: PAYABLE_LINES,
    lateLines: [],
    chargebackLines: [],
    alreadyStampedLines: [],
    rateMissingLines: []
};

function flushPromises() {
    return Promise.resolve();
}

function createComponent(preflight = BASE_PREFLIGHT) {
    const element = createElement('c-agent-payout-review', { is: AgentPayoutReview });
    element.methodOptions = [{ label: 'Check', value: 'Check' }];
    element.preflight = preflight;
    document.body.appendChild(element);
    return element;
}

function tickConfirm(element) {
    const box = element.shadowRoot.querySelector('input[data-id="confirm"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    return flushPromises();
}

function payableTable(element) {
    return element.shadowRoot.querySelector('c-agent-line-table[data-id="payable-lines"]');
}

function exclude(element, excludedIds) {
    payableTable(element).dispatchEvent(new CustomEvent('exclusionchange', { detail: { excludedIds } }));
    return flushPromises();
}

function moneyAt(element, selector) {
    return element.shadowRoot.querySelector(selector).querySelector('lightning-formatted-number')
        .value;
}

function recordPayload(element) {
    const handler = jest.fn();
    element.addEventListener('recordpayout', handler);
    return {
        handler,
        async fire() {
            element.shadowRoot.querySelector('button[data-id="record"]').click();
            await flushPromises();
            return JSON.parse(handler.mock.calls[0][0].detail.formJson);
        }
    };
}

describe('c-agent-payout-review', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the money block and seeds the amount from the computed payable', async () => {
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="computed-payable"]')).not.toBeNull();
        const amount = element.shadowRoot.querySelector('lightning-input[data-id="amount-paid"]');
        expect(amount.value).toBe(210.25);
    });

    it('renders no exception section when the selection holds none', async () => {
        const element = createComponent();
        await flushPromises();

        const sections = [...element.shadowRoot.querySelectorAll('c-agent-line-table')];
        expect(sections.map((section) => section.dataset.id)).toEqual(['payable-lines']);
        expect(element.shadowRoot.querySelector('[data-id="unrated-summary"]')).toBeNull();
    });

    it('renders the exception sections in order when the selection holds them', async () => {
        const element = createComponent({
            ...BASE_PREFLIGHT,
            lateLineCount: 1,
            lateLines: [LINE],
            chargebackLineCount: 1,
            chargebackLines: [
                { ...LINE, lineId: 'a0L2', commissionAmount: -28.91, payableAmount: -14.46 }
            ],
            alreadyStampedLineCount: 1,
            alreadyStampedLines: [
                { ...LINE, lineId: 'a0L3', paidOut: true, payoutName: 'AP-202604-0001' }
            ],
            unratedLineCount: 2,
            unratedNetAmount: 55,
            rateMissingLines: [{ ...LINE, lineId: 'a0L4', payableAmount: null, rateMissing: true }]
        });
        await flushPromises();

        const sections = element.shadowRoot.querySelectorAll('c-agent-line-table');
        expect(sections).toHaveLength(5);
        // The modal reads top to bottom as: what is being settled, then the exceptions worth
        // looking at, then what could not be valued at all, then the amount, then the gate.
        expect([...sections].map((section) => section.dataset.id)).toEqual([
            'payable-lines',
            'late-lines',
            'chargeback-lines',
            'stamped-lines',
            'unrated-lines'
        ]);
        // The late section speaks in lines, not in periods.
        expect(sections[1].lines).toHaveLength(1);
        // The four informational sections are never selectable; only the payable list is.
        expect([...sections].map((section) => section.selectable)).toEqual([
            true,
            false,
            false,
            false,
            false
        ]);
    });

    it('always shows how many lines and how much money could not be valued', async () => {
        const element = createComponent({
            ...BASE_PREFLIGHT,
            unratedLineCount: 3,
            unratedNetAmount: 55,
            rateMissingLines: [{ ...LINE, payableAmount: null, rateMissing: true }]
        });
        await flushPromises();

        const summary = element.shadowRoot.querySelector('[data-id="unrated-summary"]');
        expect(summary).not.toBeNull();
        const figures = summary.querySelectorAll('lightning-formatted-number');
        expect(figures[0].value).toBe(3);
        expect(figures[1].value).toBe(55);
    });

    it('warns, but still allows recording, when the selection nets zero or less', async () => {
        const element = createComponent({ ...BASE_PREFLIGHT, linesNetAmount: 0, computedPayable: 0 });
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="zero-net"]')).not.toBeNull();
        await tickConfirm(element);
        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(false);
    });

    it('keeps the record button disabled until the amount is confirmed', async () => {
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
        await tickConfirm(element);
        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(false);
    });

    it('clears the confirmation when the amount is edited', async () => {
        const element = createComponent();
        await flushPromises();
        await tickConfirm(element);

        const amount = element.shadowRoot.querySelector('lightning-input[data-id="amount-paid"]');
        amount.value = '150';
        amount.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
    });

    it('clears the confirmation and says so when the server numbers change underneath it', async () => {
        const element = createComponent();
        await flushPromises();
        await tickConfirm(element);

        element.preflight = { ...BASE_PREFLIGHT, lineCount: 5, computedPayable: 260 };
        await flushPromises();

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
        expect(element.shadowRoot.querySelector('.review-alert_warning')).not.toBeNull();
    });

    it('keeps the confirmation when a fresh preflight returns the same three totals', async () => {
        const element = createComponent();
        await flushPromises();
        await tickConfirm(element);

        element.preflight = { ...BASE_PREFLIGHT, periodLabel: '2026-05 ~ 2026-06 (재조회)' };
        await flushPromises();

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(false);
        expect(element.shadowRoot.querySelector('.review-alert_warning')).toBeNull();
    });

    it('re-arms the confirmation gate when the container reports a rejected save', async () => {
        const element = createComponent();
        await flushPromises();
        await tickConfirm(element);
        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(false);

        element.errorMessage = '화면의 금액이 최신이 아닙니다.';
        await flushPromises();

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
    });

    it('emits the form as one JSON string so no reactive proxy crosses the boundary', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('recordpayout', handler);
        await flushPromises();

        const reference = element.shadowRoot.querySelector('lightning-input[data-field="referenceNumber"]');
        reference.value = '1042';
        reference.dispatchEvent(new CustomEvent('change'));
        element.shadowRoot
            .querySelector('lightning-combobox[data-id="method"]')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'Check' } }));
        await tickConfirm(element);

        element.shadowRoot.querySelector('button[data-id="record"]').click();
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
        const payload = JSON.parse(handler.mock.calls[0][0].detail.formJson);
        expect(payload.amountPaid).toBe(210.25);
        expect(payload.referenceNumber).toBe('1042');
        expect(payload.paymentMethod).toBe('Check');
        expect(typeof payload.paidDate).toBe('string');
    });

    it('offers every open line, ticked, as the default', async () => {
        const element = createComponent();
        await flushPromises();

        const table = payableTable(element);
        expect(table).not.toBeNull();
        expect(table.selectable).toBe(true);
        expect(table.lines).toHaveLength(4);
        // Nothing excluded: the routine path settles the whole selection in one click.
        expect(table.excludedIds).toEqual([]);
        expect(element.shadowRoot.querySelector('[data-id="excluded-summary"]')).toBeNull();
    });

    it('shows the server totals untouched while nothing is excluded', async () => {
        const element = createComponent();
        await flushPromises();

        expect(moneyAt(element, '[data-id="included-count"]')).toBe(4);
        expect(moneyAt(element, '[data-id="carrier-net"]')).toBe(420.5);
        expect(moneyAt(element, '[data-id="computed-payable"]')).toBe(210.25);
    });

    it('takes an unticked line back out of the count, the carrier net and the payable', async () => {
        const element = createComponent();
        await flushPromises();

        await exclude(element, ['a0L2']);

        expect(moneyAt(element, '[data-id="included-count"]')).toBe(3);
        expect(moneyAt(element, '[data-id="carrier-net"]')).toBe(300.5);
        expect(moneyAt(element, '[data-id="computed-payable"]')).toBe(150.25);
    });

    it('shows what was excluded beside what is left, so the money never just disappears', async () => {
        const element = createComponent();
        await flushPromises();

        await exclude(element, ['a0L2', 'a0L3']);

        const summary = element.shadowRoot.querySelector('[data-id="excluded-summary"]');
        expect(summary).not.toBeNull();
        const figures = summary.querySelectorAll('lightning-formatted-number');
        expect(figures[0].value).toBe(2);
        expect(figures[1].value).toBe(240);
    });

    it('pushes the exclusion set back down to the line table', async () => {
        const element = createComponent();
        await flushPromises();

        await exclude(element, ['a0L4']);

        expect(payableTable(element).excludedIds).toEqual(['a0L4']);
    });

    it('re-seeds the amount from the recomputed payable when the exclusions change', async () => {
        const element = createComponent();
        await flushPromises();

        await exclude(element, ['a0L2']);

        const amount = element.shadowRoot.querySelector('lightning-input[data-id="amount-paid"]');
        expect(amount.value).toBe(150.25);
    });

    it('leaves an amount the owner typed alone when the exclusions change', async () => {
        const element = createComponent();
        await flushPromises();

        const amount = element.shadowRoot.querySelector('lightning-input[data-id="amount-paid"]');
        amount.value = '175';
        amount.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        await exclude(element, ['a0L2']);

        expect(
            element.shadowRoot.querySelector('lightning-input[data-id="amount-paid"]').value
        ).toBe('175');
    });

    it('clears the confirmation gate on any exclusion change', async () => {
        const element = createComponent();
        await flushPromises();
        await tickConfirm(element);
        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(false);

        await exclude(element, ['a0L2']);

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
    });

    it('clears the confirmation gate again when a line is ticked back on', async () => {
        const element = createComponent();
        await flushPromises();
        await exclude(element, ['a0L2']);
        await tickConfirm(element);

        await exclude(element, []);

        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
        expect(moneyAt(element, '[data-id="computed-payable"]')).toBe(210.25);
    });

    it('carries the exclusions and the included-set totals in the emitted payload', async () => {
        const element = createComponent();
        await flushPromises();
        const emitted = recordPayload(element);
        await exclude(element, ['a0L2']);
        await tickConfirm(element);

        const payload = await emitted.fire();

        expect(payload.excludedLineIds).toEqual(['a0L2']);
        expect(payload.expectedLineCount).toBe(3);
        expect(payload.expectedLinesNetAmount).toBe(300.5);
        expect(payload.expectedPayableAmount).toBe(150.25);
        expect(payload.amountPaid).toBe(150.25);
    });

    it('emits the full selection and an empty exclusion list on the default path', async () => {
        const element = createComponent();
        await flushPromises();
        const emitted = recordPayload(element);
        await tickConfirm(element);

        const payload = await emitted.fire();

        expect(payload.excludedLineIds).toEqual([]);
        expect(payload.expectedLineCount).toBe(4);
        expect(payload.expectedLinesNetAmount).toBe(420.5);
        expect(payload.expectedPayableAmount).toBe(210.25);
    });

    it('says no money is leaving once every paying line has been unticked', async () => {
        const element = createComponent();
        await flushPromises();

        await exclude(element, ['a0L1', 'a0L2', 'a0L3']);

        // Only the chargeback is left, so the selection nets below zero. A negative is written in
        // accounting parentheses: the magnitude is rendered and the sign is carried by the class
        // and by the assistive text beside it, never by a minus sign alone.
        expect(moneyAt(element, '[data-id="carrier-net"]')).toBe(20);
        expect(element.shadowRoot.querySelector('[data-id="carrier-net"] .money_negative')).not.toBeNull();
        expect(element.shadowRoot.querySelector('[data-id="zero-net"]')).not.toBeNull();
    });

    it('writes a positive figure without the negative treatment', async () => {
        const element = createComponent();
        await flushPromises();

        expect(element.shadowRoot.querySelector('[data-id="computed-payable"] .money')).not.toBeNull();
        expect(
            element.shadowRoot.querySelector('[data-id="computed-payable"] .money_negative')
        ).toBeNull();
    });

    it('dismisses on Escape so the modal behaves like a dialog from the keyboard', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('closereview', handler);
        await flushPromises();

        element.shadowRoot
            .querySelector('[role="dialog"]')
            .dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('ignores Escape while the container is writing, when there is nothing safe to cancel', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('closereview', handler);
        element.isSaving = true;
        await flushPromises();

        element.shadowRoot
            .querySelector('[role="dialog"]')
            .dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        await flushPromises();

        expect(handler).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
    });

    it('drops an exclusion the server no longer offers', async () => {
        const element = createComponent();
        await flushPromises();
        await exclude(element, ['a0L2']);

        element.preflight = {
            ...BASE_PREFLIGHT,
            lineCount: 3,
            linesNetAmount: 300.5,
            computedPayable: 150.25,
            payableLines: PAYABLE_LINES.filter((line) => line.lineId !== 'a0L2')
        };
        await flushPromises();

        expect(payableTable(element).excludedIds).toEqual([]);
        expect(moneyAt(element, '[data-id="included-count"]')).toBe(3);
        expect(moneyAt(element, '[data-id="computed-payable"]')).toBe(150.25);
    });

    it('keeps an exclusion the server still offers across a re-read', async () => {
        const element = createComponent();
        await flushPromises();
        await exclude(element, ['a0L2']);

        element.preflight = { ...BASE_PREFLIGHT, periodLabel: '2026-05 ~ 2026-06 (재조회)' };
        await flushPromises();

        expect(payableTable(element).excludedIds).toEqual(['a0L2']);
        expect(moneyAt(element, '[data-id="computed-payable"]')).toBe(150.25);
    });

    it('tolerates an exclusionchange that carries no detail', async () => {
        const element = createComponent();
        await flushPromises();

        payableTable(element).dispatchEvent(new CustomEvent('exclusionchange'));
        await flushPromises();

        expect(moneyAt(element, '[data-id="included-count"]')).toBe(4);
        expect(moneyAt(element, '[data-id="computed-payable"]')).toBe(210.25);
    });

    it('emits closereview when cancelled', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('closereview', handler);
        await flushPromises();

        element.shadowRoot.querySelector('button[data-id="cancel"]').click();
        await flushPromises();

        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('shows the save failure the container handed down', async () => {
        const element = createComponent();
        element.errorMessage = 'nope';
        await flushPromises();

        expect(element.shadowRoot.querySelector('.review-alert_error').textContent).toContain('nope');
    });

    it('renders an empty preflight without failing', async () => {
        // Passed explicitly rather than through createComponent, whose default would substitute a
        // populated snapshot for `undefined`.
        const element = createElement('c-agent-payout-review', { is: AgentPayoutReview });
        element.methodOptions = [{ label: 'Check', value: 'Check' }];
        element.preflight = undefined;
        document.body.appendChild(element);
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('c-agent-line-table')).toHaveLength(0);
        expect(element.shadowRoot.querySelector('[data-id="excluded-summary"]')).toBeNull();
        expect(moneyAt(element, '[data-id="included-count"]')).toBe(0);
        expect(element.shadowRoot.querySelector('button[data-id="record"]').disabled).toBe(true);
    });
});
