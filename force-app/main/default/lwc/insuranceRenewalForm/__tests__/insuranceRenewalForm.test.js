import { createElement } from 'lwc';
import InsuranceRenewalForm from 'c/insuranceRenewalForm';
import getRenewalContext from '@salesforce/apex/InsuranceRenewalController.getRenewalContext';
import renew from '@salesforce/apex/InsuranceRenewalController.renewJson';

jest.mock(
    '@salesforce/apex/InsuranceRenewalController.getRenewalContext',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/InsuranceRenewalController.renewJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

/**
 * @description A date offset from today as yyyy-MM-dd, so the future/immediate branches under test
 * stay on the right side of "today" no matter when the suite runs.
 */
function isoDaysFromToday(days) {
    const date = new Date();
    date.setDate(date.getDate() + days);
    return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

const CONTEXT = {
    recordId: 'a0m00000000001',
    name: 'ROSTER-GH-TEST (Active)',
    recordTypeDeveloperName: 'Group_Health',
    recordTypeLabel: 'Group Health',
    currentStartDate: '2026-05-01',
    currentEndDate: '2027-04-30',
    currentTermMonths: 12,
    suggestedStartDate: isoDaysFromToday(60),
    providerId: '001000000000001',
    providerName: 'Blue Cross',
    premium: 4200,
    deductible: 1000,
    policyNumber: 'GH-2026-001',
    companyName: 'Legacy Investment',
    activeMemberCount: 12
};

function flush() {
    return Promise.resolve();
}

function toggleInput(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find(
        (input) => input.type === 'toggle'
    );
}

describe('c-insurance-renewal-form', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the policy header and member preview for Group Health', async () => {
        const element = createElement('c-insurance-renewal-form', { is: InsuranceRenewalForm });
        element.recordId = 'a0m00000000001';
        document.body.appendChild(element);

        getRenewalContext.emit(CONTEXT);
        await flush();

        expect(element.shadowRoot.querySelector('.header-name').textContent).toBe('ROSTER-GH-TEST (Active)');
        expect(element.shadowRoot.querySelector('.member-callout')).not.toBeNull();
    });

    it('flags a future-dated term as Draft and defers the member move', async () => {
        const element = createElement('c-insurance-renewal-form', { is: InsuranceRenewalForm });
        element.recordId = 'a0m00000000001';
        document.body.appendChild(element);

        getRenewalContext.emit(CONTEXT);
        await flush();

        expect(element.shadowRoot.querySelector('.future-callout')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.status-pill').textContent).toBe('Draft');
        // Nothing carries on save, so the carry-members toggle has nothing to control.
        expect(toggleInput(element)).toBeUndefined();
    });

    it('keeps a term that has already started on the immediate Active path', async () => {
        const element = createElement('c-insurance-renewal-form', { is: InsuranceRenewalForm });
        element.recordId = 'a0m00000000001';
        document.body.appendChild(element);

        getRenewalContext.emit({ ...CONTEXT, suggestedStartDate: isoDaysFromToday(0) });
        await flush();

        expect(element.shadowRoot.querySelector('.future-callout')).toBeNull();
        expect(element.shadowRoot.querySelector('.status-pill').textContent).toBe('Active');
        expect(toggleInput(element)).toBeDefined();
    });

    it('calls the renew controller when Renew is clicked', async () => {
        renew.mockResolvedValue({
            newInsuranceId: 'a0m00000000002',
            membersCarried: 0,
            newStatus: 'Draft'
        });
        const element = createElement('c-insurance-renewal-form', { is: InsuranceRenewalForm });
        element.recordId = 'a0m00000000001';
        document.body.appendChild(element);

        getRenewalContext.emit(CONTEXT);
        await flush();

        const renewButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find(
            (button) => button.variant === 'brand'
        );
        renewButton.click();
        await flush();

        expect(renew).toHaveBeenCalledTimes(1);
        const passed = JSON.parse(renew.mock.calls[0][0].requestJson);
        expect(passed.originalInsuranceId).toBe('a0m00000000001');
        expect(passed.termMonths).toBe(12);
    });

    it('shows an error panel when the context fails to load', async () => {
        const element = createElement('c-insurance-renewal-form', { is: InsuranceRenewalForm });
        element.recordId = 'a0m00000000001';
        document.body.appendChild(element);

        getRenewalContext.error({ body: { message: 'boom' } });
        await flush();

        expect(element.shadowRoot.querySelector('c-flow-error-panel')).not.toBeNull();
    });
});
