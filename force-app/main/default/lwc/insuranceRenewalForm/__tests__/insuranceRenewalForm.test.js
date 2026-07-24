import { createElement } from 'lwc';
import InsuranceRenewalForm from 'c/insuranceRenewalForm';
import getRenewalContext from '@salesforce/apex/InsuranceRenewalController.getRenewalContext';
import renew from '@salesforce/apex/InsuranceRenewalController.renew';

jest.mock(
    '@salesforce/apex/InsuranceRenewalController.getRenewalContext',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/InsuranceRenewalController.renew',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const CONTEXT = {
    recordId: 'a0m00000000001',
    name: 'ROSTER-GH-TEST (Active)',
    recordTypeDeveloperName: 'Group_Health',
    recordTypeLabel: 'Group Health',
    currentStartDate: '2026-05-01',
    currentEndDate: '2027-04-30',
    currentTermMonths: 12,
    suggestedStartDate: '2027-05-01',
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

    it('calls the renew controller when Renew is clicked', async () => {
        renew.mockResolvedValue({ newInsuranceId: 'a0m00000000002', membersCarried: 12 });
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
        const passed = renew.mock.calls[0][0].request;
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
