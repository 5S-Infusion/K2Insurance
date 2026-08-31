import { createElement } from 'lwc';
import AgentLineTable from 'c/agentLineTable';

// LineDto, exactly as the controller sends it.
const LINES = [
    {
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
    },
    {
        lineId: 'a0L2',
        lineName: 'CL-00002',
        period: '2026-06',
        commissionDate: '2026-06-14',
        clientName: 'Jina Lim',
        clientCompany: '',
        policyId: 'a0P2',
        policyName: 'H-10044',
        carrierName: 'Oscar',
        commissionAmount: 55,
        rate: null,
        payableAmount: null,
        rateMissing: true,
        paidOut: false,
        payoutId: null,
        payoutName: null
    }
];

function flushPromises() {
    return Promise.resolve();
}

function createComponent(lines) {
    const element = createElement('c-agent-line-table', { is: AgentLineTable });
    element.caption = 'Late lines';
    element.lines = lines;
    document.body.appendChild(element);
    return element;
}

function createSelectable(lines, excludedIds = []) {
    const element = createElement('c-agent-line-table', { is: AgentLineTable });
    element.caption = 'Lines to pay';
    element.selectable = true;
    element.excludedIds = excludedIds;
    element.lines = lines;
    document.body.appendChild(element);
    return element;
}

function toggle(element, index) {
    const box = element.shadowRoot.querySelectorAll('input[data-id="line-check"]')[index];
    box.checked = !box.checked;
    box.dispatchEvent(new CustomEvent('change'));
    return flushPromises();
}

describe('c-agent-line-table', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders one row per line', async () => {
        const element = createComponent(LINES);
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(2);
    });

    it('renders the caption as the section heading', async () => {
        const element = createComponent(LINES);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.line-section__caption').textContent).toBe('Late lines');
    });

    it('names a missing policy rate instead of pricing it at zero', async () => {
        const element = createComponent(LINES);
        await flushPromises();

        const badges = element.shadowRoot.querySelectorAll('.line-rate-missing');
        expect(badges).toHaveLength(1);
        // The rated line shows commissionAmount and payableAmount; the unrated one shows only the
        // carrier's commissionAmount.
        expect(element.shadowRoot.querySelectorAll('lightning-formatted-number')).toHaveLength(3);
    });

    it('reads the money off commissionAmount and payableAmount', async () => {
        const element = createComponent([LINES[0]]);
        await flushPromises();

        const amounts = element.shadowRoot.querySelectorAll('lightning-formatted-number');
        expect(amounts[0].value).toBe(28.91);
        expect(amounts[1].value).toBe(14.46);
    });

    it('renders the owning payout on a line that is already stamped', async () => {
        const element = createComponent([
            { ...LINES[0], paidOut: true, payoutId: 'a0X1', payoutName: 'AP-202604-0001' }
        ]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.line-payout').textContent).toBe('AP-202604-0001');
    });

    it('shows the empty message and no table when there are no lines', async () => {
        const element = createComponent([]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('table')).toBeNull();
        expect(element.shadowRoot.querySelector('.line-empty')).not.toBeNull();
    });

    it('tolerates a missing lines property', async () => {
        const element = createComponent(undefined);
        await flushPromises();

        expect(element.shadowRoot.querySelector('table')).toBeNull();
    });

    it('copies the incoming lines rather than holding the parent array', async () => {
        const source = [{ ...LINES[0] }];
        const element = createComponent(source);
        await flushPromises();

        expect(element.lines).not.toBe(source);
        expect(element.lines[0]).not.toBe(source[0]);
        expect(element.lines[0].lineId).toBe('a0L1');
    });

    it('renders no checkbox at all when it is not selectable', async () => {
        const element = createComponent(LINES);
        await flushPromises();

        expect(element.shadowRoot.querySelectorAll('input[type="checkbox"]')).toHaveLength(0);
        expect(element.shadowRoot.querySelector('.line-table__check')).toBeNull();
    });

    it('renders one checkbox per row and ticks them all by default', async () => {
        const element = createSelectable(LINES);
        await flushPromises();

        const boxes = element.shadowRoot.querySelectorAll('input[data-id="line-check"]');
        expect(boxes).toHaveLength(2);
        expect([...boxes].every((box) => box.checked)).toBe(true);
    });

    it('unticks exactly the rows named in excludedIds', async () => {
        const element = createSelectable(LINES, ['a0L2']);
        await flushPromises();

        const boxes = element.shadowRoot.querySelectorAll('input[data-id="line-check"]');
        expect(boxes[0].checked).toBe(true);
        expect(boxes[1].checked).toBe(false);
    });

    it('names the checkbox from a label rather than from the row it sits on', async () => {
        const element = createSelectable(LINES);
        await flushPromises();

        const box = element.shadowRoot.querySelector('input[data-id="line-check"]');
        const name = box.getAttribute('aria-label');
        expect(name).toBeTruthy();
        expect(name).not.toContain('Jong H Yi');
        expect(name).not.toContain('H-10021');
    });

    it('emits the whole new exclusion set when a row is unticked', async () => {
        const element = createSelectable(LINES);
        const handler = jest.fn();
        element.addEventListener('exclusionchange', handler);
        await flushPromises();

        await toggle(element, 1);

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.excludedIds).toEqual(['a0L2']);
    });

    it('emits the remaining exclusions when a row is ticked back on', async () => {
        const element = createSelectable(LINES, ['a0L1', 'a0L2']);
        const handler = jest.fn();
        element.addEventListener('exclusionchange', handler);
        await flushPromises();

        await toggle(element, 0);

        expect(handler.mock.calls[0][0].detail.excludedIds).toEqual(['a0L2']);
    });

    it('emits plain ids rather than a reference to its own exclusion set', async () => {
        const source = ['a0L1'];
        const element = createSelectable(LINES, source);
        const handler = jest.fn();
        element.addEventListener('exclusionchange', handler);
        await flushPromises();

        await toggle(element, 1);

        const emitted = handler.mock.calls[0][0].detail.excludedIds;
        expect(emitted).not.toBe(source);
        expect(emitted).not.toBe(element.excludedIds);
        expect(emitted).toEqual(['a0L1', 'a0L2']);
        expect(emitted.every((id) => typeof id === 'string')).toBe(true);
    });

    it('leaves its own exclusion set alone until the parent pushes a new one down', async () => {
        const element = createSelectable(LINES);
        await flushPromises();

        await toggle(element, 0);

        // The parent owns the state. The child only asked; it wrote nothing back into its @api
        // property, so what it believes is still exactly what the parent last handed it.
        expect(element.excludedIds).toEqual([]);
    });

    it('tallies what is in and what is out, only where rows can be unticked', async () => {
        const readOnly = createComponent(LINES);
        await flushPromises();
        expect(readOnly.shadowRoot.querySelector('[data-id="line-summary"]')).toBeNull();

        const element = createSelectable(LINES, ['a0L2']);
        await flushPromises();

        const counts = element.shadowRoot
            .querySelector('[data-id="line-summary"]')
            .querySelectorAll('lightning-formatted-number');
        expect(counts[0].value).toBe(1);
        expect(counts[1].value).toBe(1);
    });

    it('marks an unticked row so the tick and the money it decides never disagree', async () => {
        const element = createSelectable(LINES, ['a0L2']);
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows[0].classList.contains('line-row_excluded')).toBe(false);
        expect(rows[1].classList.contains('line-row_excluded')).toBe(true);
    });

    it('writes a negative amount in accounting parentheses rather than with a minus sign', async () => {
        const element = createComponent([
            { ...LINES[0], commissionAmount: -28.91, payableAmount: -14.46 }
        ]);
        await flushPromises();

        const amounts = element.shadowRoot.querySelectorAll('.money_negative');
        expect(amounts).toHaveLength(2);
        // The magnitude is what is rendered; the sign is carried by the class and by the assistive
        // text beside it, so a screen reader still hears a negative.
        expect(
            amounts[0].querySelector('lightning-formatted-number').value
        ).toBe(28.91);
        expect(amounts[0].querySelector('.slds-assistive-text').textContent).toBeTruthy();
    });

    it('does not bubble or cross the shadow boundary', async () => {
        const element = createSelectable(LINES);
        const handler = jest.fn();
        element.addEventListener('exclusionchange', handler);
        await flushPromises();

        const box = element.shadowRoot.querySelector('input[data-id="line-check"]');
        box.checked = false;
        box.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const event = handler.mock.calls[0][0];
        expect(event.bubbles).toBe(false);
        expect(event.composed).toBe(false);
    });

    it('tolerates a missing excludedIds property', async () => {
        const element = createElement('c-agent-line-table', { is: AgentLineTable });
        element.selectable = true;
        element.excludedIds = undefined;
        element.lines = LINES;
        document.body.appendChild(element);
        await flushPromises();

        expect(element.excludedIds).toEqual([]);
        const boxes = element.shadowRoot.querySelectorAll('input[data-id="line-check"]');
        expect([...boxes].every((box) => box.checked)).toBe(true);
    });

    it('reads selectable="true" from markup as a real Boolean', async () => {
        const element = createElement('c-agent-line-table', { is: AgentLineTable });
        element.selectable = 'true';
        element.lines = LINES;
        document.body.appendChild(element);
        await flushPromises();

        expect(element.selectable).toBe(true);
        expect(element.shadowRoot.querySelectorAll('input[data-id="line-check"]')).toHaveLength(2);
    });

    it('treats any other selectable value as read-only', async () => {
        const element = createElement('c-agent-line-table', { is: AgentLineTable });
        element.selectable = 'yes';
        element.lines = LINES;
        document.body.appendChild(element);
        await flushPromises();

        expect(element.selectable).toBe(false);
        expect(element.shadowRoot.querySelectorAll('input[data-id="line-check"]')).toHaveLength(0);
    });
});
