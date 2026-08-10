import { createElement } from 'lwc';
import EmployeeRoster from 'c/employeeRoster';
import getEmployees from '@salesforce/apex/EmployeeRosterController.getEmployees';
import offboardEmployee from '@salesforce/apex/EmployeeRosterController.offboardEmployee';
import saveRelationships from '@salesforce/apex/EmployeeRosterController.saveRelationshipsJson';
import getGroupHealthPolicies from '@salesforce/apex/EmployeeRosterController.getGroupHealthPolicies';
import getFieldOptions from '@salesforce/apex/EmployeeRosterController.getFieldOptions';
import onboardEmployee from '@salesforce/apex/EmployeeRosterController.onboardEmployeeJson';

// Imperative Apex is mocked; wire adapters (getEmployees, getGroupHealthPolicies, getObjectInfo,
// getPicklistValues) are auto-mocked as test wire adapters by sfdx-lwc-jest.
jest.mock(
    '@salesforce/apex/EmployeeRosterController.offboardEmployee',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/EmployeeRosterController.saveRelationshipsJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/EmployeeRosterController.onboardEmployeeJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const MOCK_ROWS = [
    { acrId: '0aa1', contactId: '003a', name: 'Jong H Yi', contactUrl: '/003a', roles: 'Employee', plans: 'M / D / V', family: '', activeIns: true },
    { acrId: '0aa2', contactId: '003b', name: 'Jina Lim', contactUrl: '/003b', roles: 'Employee', plans: 'M', family: 'EO', activeIns: true }
];

const MOCK_POLICIES = [
    { policyId: 'a0P1', label: 'GH-1001 — Blue Cross — 2026-05-01 ~ 2027-04-30', withDental: true, withVision: false }
];

/** @description Opens the Add Employee modal on a freshly rendered roster. */
async function openAddEmployee(element) {
    element.shadowRoot.querySelector('lightning-button[data-id="add-employee"]').click();
    await flushPromises();
}

function flushPromises() {
    return Promise.resolve();
}

function createComponent() {
    const element = createElement('c-employee-roster', { is: EmployeeRoster });
    element.recordId = '001TESTACCOUNT';
    document.body.appendChild(element);
    return element;
}

describe('c-employee-roster', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders a table row per employee', async () => {
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        await flushPromises();

        const bodyRows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(bodyRows).toHaveLength(2);
    });

    it('renders editable Roles and Family comboboxes per row', async () => {
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        await flushPromises();

        const comboboxes = element.shadowRoot.querySelectorAll('lightning-combobox');
        // Two editable columns (roles, family) per row.
        expect(comboboxes.length).toBe(MOCK_ROWS.length * 2);
    });

    it('shows the empty-state message when no employees are returned', async () => {
        const element = createComponent();
        getEmployees.emit([]);
        await flushPromises();

        const table = element.shadowRoot.querySelector('table');
        expect(table).toBeNull();
    });

    it('saves inline edits through the controller', async () => {
        saveRelationships.mockResolvedValue();
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        await flushPromises();

        const rolesCombobox = element.shadowRoot.querySelector('lightning-combobox[data-acr="0aa1"]');
        rolesCombobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'Manager' } }));
        await flushPromises();

        const saveButton = element.shadowRoot.querySelector('lightning-button[data-id="save-edits"]');
        saveButton.click();
        await flushPromises();

        expect(saveRelationships).toHaveBeenCalledTimes(1);
        // Guard the regression where reactive-membrane proxies serialized to {} and Apex
        // received null acrId. The edit is sent as a JSON string; parse it and verify the
        // real acrId and the changed value survived.
        const { editsJson } = saveRelationships.mock.calls[0][0];
        const edits = JSON.parse(editsJson);
        expect(edits).toHaveLength(1);
        expect(edits[0]).toEqual(
            expect.objectContaining({ acrId: '0aa1', roles: 'Manager' })
        );
        expect(edits[0].acrId).toBe('0aa1');
    });

    it('offboards a row through the controller', async () => {
        offboardEmployee.mockResolvedValue();
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        await flushPromises();

        const offboardButton = element.shadowRoot.querySelector('lightning-button[data-acr="0aa1"]');
        offboardButton.click();
        await flushPromises();

        const confirmButton = element.shadowRoot.querySelector('button.slds-button_destructive');
        confirmButton.click();
        await flushPromises();

        expect(offboardEmployee).toHaveBeenCalledTimes(1);
    });

    it('surfaces an error toast when the wire returns an error', async () => {
        const element = createComponent();
        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        getEmployees.error();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
    });

    it('opens the Add Employee modal with the coverage section when the company has a policy', async () => {
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        getGroupHealthPolicies.emit(MOCK_POLICIES);
        await flushPromises();
        await openAddEmployee(element);

        expect(element.shadowRoot.querySelector('section[aria-labelledby="onboard-heading"]')).not.toBeNull();
        // Enrolment is on by default, so the policy picker is rendered.
        expect(element.shadowRoot.querySelector('lightning-combobox[data-id="policy"]')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-input[data-id="enroll-toggle"]')).not.toBeNull();
    });

    it('hides the enrolment controls when the company has no active policy', async () => {
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        getGroupHealthPolicies.emit([]);
        await flushPromises();
        await openAddEmployee(element);

        expect(element.shadowRoot.querySelector('lightning-input[data-id="enroll-toggle"]')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-combobox[data-id="policy"]')).toBeNull();
    });

    it('toggles a role pill on and off', async () => {
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        getGroupHealthPolicies.emit([]);
        getFieldOptions.emit({
            roles: [{ label: 'Manager', value: 'Manager' }, { label: 'Employee', value: 'Employee' }],
            family: [{ label: 'EO', value: 'EO' }]
        });
        await flushPromises();
        await openAddEmployee(element);

        const chip = element.shadowRoot.querySelector('button.onboard-chip[data-role]');
        expect(chip.className).not.toContain('onboard-chip_selected');
        chip.click();
        await flushPromises();

        const selected = element.shadowRoot.querySelector('button.onboard-chip[data-role]');
        expect(selected.className).toContain('onboard-chip_selected');
    });

    it('blocks the save and shows an inline error when the last name is missing', async () => {
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        getGroupHealthPolicies.emit([]);
        await flushPromises();
        await openAddEmployee(element);

        element.shadowRoot.querySelector('button.slds-button_brand').click();
        await flushPromises();

        expect(onboardEmployee).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('[role="alert"]')).not.toBeNull();
    });

    it('sends the entered coverage start date to the controller as JSON', async () => {
        onboardEmployee.mockResolvedValue('003NEW');
        const element = createComponent();
        getEmployees.emit(MOCK_ROWS);
        getGroupHealthPolicies.emit(MOCK_POLICIES);
        await flushPromises();
        await openAddEmployee(element);

        const modal = element.shadowRoot.querySelector('section[aria-labelledby="onboard-heading"]');
        modal.querySelector('lightning-input[data-field="lastName"]').dispatchEvent(
            new CustomEvent('change', { detail: {} })
        );
        // lightning-input is stubbed, so drive the handler through the element's own value.
        const lastName = modal.querySelector('lightning-input[data-field="lastName"]');
        lastName.value = 'Alison';
        lastName.dispatchEvent(new CustomEvent('change'));
        const startDate = modal.querySelector('lightning-input[data-field="coverageStartDate"]');
        startDate.value = '2026-08-01';
        startDate.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        element.shadowRoot.querySelector('button.slds-button_brand').click();
        await flushPromises();

        expect(onboardEmployee).toHaveBeenCalledTimes(1);
        const { requestJson } = onboardEmployee.mock.calls[0][0];
        const request = JSON.parse(requestJson);
        expect(request.lastName).toBe('Alison');
        expect(request.coverageStartDate).toBe('2026-08-01');
        expect(request.insuranceId).toBe('a0P1');
        // Medical is the only coverage ticked by default, even though the policy carries Dental.
        expect(request.medical).toBe(true);
        expect(request.dental).toBe(false);
        expect(request.vision).toBe(false);
    });
});
