import { createElement } from 'lwc';
import EmployeeRoster from 'c/employeeRoster';
import getEmployees from '@salesforce/apex/EmployeeRosterController.getEmployees';
import offboardEmployee from '@salesforce/apex/EmployeeRosterController.offboardEmployee';
import saveRelationships from '@salesforce/apex/EmployeeRosterController.saveRelationshipsJson';

// Imperative Apex is mocked; wire adapters (getEmployees, getObjectInfo, getPicklistValues) are
// auto-mocked as test wire adapters by sfdx-lwc-jest.
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

const MOCK_ROWS = [
    { acrId: '0aa1', contactId: '003a', name: 'Jong H Yi', contactUrl: '/003a', roles: 'Employee', plans: 'M / D / V', family: '', activeIns: true },
    { acrId: '0aa2', contactId: '003b', name: 'Jina Lim', contactUrl: '/003b', roles: 'Employee', plans: 'M', family: 'EO', activeIns: true }
];

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

        const saveButton = element.shadowRoot.querySelector('lightning-button[variant="brand"]');
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
});
