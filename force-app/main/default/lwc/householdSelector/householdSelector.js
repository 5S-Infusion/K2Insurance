/**
 * @description Flow screen component that lists every lead in a household in one table so the
 *              agent can pick who to convert in a single pass, instead of running the conversion
 *              once per person.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 */
import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

const COLUMNS = [
    { label: '이름', fieldName: 'displayName', type: 'text', wrapText: true },
    { label: '관계', fieldName: 'relationshipLabel', type: 'text', initialWidth: 130 },
    {
        label: '전환 여부',
        fieldName: 'statusLabel',
        type: 'text',
        initialWidth: 130,
        cellAttributes: { class: { fieldName: 'statusClass' } }
    }
];

export default class HouseholdSelector extends LightningElement {
    columns = COLUMNS;

    _leads = [];
    _selectedIds = [];
    _initialised = false;

    @api
    get leads() {
        return this._leads;
    }
    set leads(value) {
        this._leads = Array.isArray(value) ? value : [];
        this.initialiseSelection();
    }

    /** Leads the agent chose to convert. */
    @api selectedLeads = [];

    get rows() {
        return this._leads.map(lead => {
            const converted = Boolean(lead.Contact__c);
            const name = [lead.FirstName, lead.LastName].filter(Boolean).join(' ');

            let relationship = lead.Familial_Relationship__c || '';
            if (lead.Is_Primaryholder__c) {
                relationship = relationship ? `${relationship} · 세대주` : '세대주';
            }

            return {
                Id: lead.Id,
                displayName: name || lead.Id,
                relationshipLabel: relationship || '—',
                statusLabel: converted ? '전환됨' : '대기',
                statusClass: converted ? 'status-converted' : 'status-pending'
            };
        });
    }

    get isEmpty() {
        return this._leads.length === 0;
    }

    get preselectedIds() {
        return this._selectedIds;
    }

    get summaryText() {
        const total = this._leads.length;
        const converted = this._leads.filter(lead => lead.Contact__c).length;
        const chosen = this._selectedIds.length;
        return `가족 ${total}명 · 이미 전환 ${converted}명 · 선택 ${chosen}명`;
    }

    /**
     * Pre-selects everyone who has not been converted yet - that is the common case, and the
     * agent can uncheck anyone they want to leave as a lead.
     */
    initialiseSelection() {
        if (this._initialised || this._leads.length === 0) {
            return;
        }
        this._initialised = true;
        this._selectedIds = this._leads.filter(lead => !lead.Contact__c).map(lead => lead.Id);
        this.publishSelection();
    }

    handleRowSelection(event) {
        this._selectedIds = event.detail.selectedRows.map(row => row.Id);
        this.publishSelection();
    }

    publishSelection() {
        const chosen = new Set(this._selectedIds);
        this.selectedLeads = this._leads.filter(lead => chosen.has(lead.Id));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedLeads', this.selectedLeads));
    }
}
