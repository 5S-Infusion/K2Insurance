/**
 * @description List of commission lines for one section of the payout review: what the carrier paid
 * on each line and, where the policy carries a rate, what it is worth to the agent. Read-only by
 * default; the section that decides a payout turns on a per-line include checkbox.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
import { LightningElement, api } from 'lwc';

import LBL_COL_CARRIER_NET from '@salesforce/label/c.AgentManagement_ColCarrierNet';
import LBL_COL_PAYABLE from '@salesforce/label/c.AgentManagement_ColPayable';
import LBL_RATE_MISSING from '@salesforce/label/c.AgentManagement_RateMissing';
import LBL_NO_LINES from '@salesforce/label/c.AgentManagement_NoLines';
import LBL_INCLUDE_LINE from '@salesforce/label/c.AgentManagement_IncludeLine';
import LBL_NEGATIVE_AMOUNT from '@salesforce/label/c.AgentManagement_NegativeAmount';
import LBL_COUNT_INCLUDED from '@salesforce/label/c.AgentManagement_CountIncluded';
import LBL_COUNT_EXCLUDED from '@salesforce/label/c.AgentManagement_CountExcluded';

/**
 * @description Splits an amount into its magnitude and its sign so a negative renders in accounting
 * parentheses while `lightning-formatted-number` still does the formatting. Kept local to the
 * bundle: the three payout components share no utils bundle, and this is display shaping, not a
 * rule about money.
 * @param {Number} value The signed amount.
 * @param {String} negativeLabel The label read out in place of the parentheses.
 * @return {Object} `{ amount, moneyClass, negativeText }`.
 */
function moneyView(value, negativeLabel) {
    const resolved = Number(value) || 0;
    return {
        amount: Math.abs(resolved),
        moneyClass: resolved < 0 ? 'money money_negative' : 'money',
        negativeText: resolved < 0 ? negativeLabel : ''
    };
}

export default class AgentLineTable extends LightningElement {
    label = {
        colCarrierNet: LBL_COL_CARRIER_NET,
        colPayable: LBL_COL_PAYABLE,
        rateMissing: LBL_RATE_MISSING,
        noLines: LBL_NO_LINES,
        includeLine: LBL_INCLUDE_LINE,
        negativeAmount: LBL_NEGATIVE_AMOUNT,
        countIncluded: LBL_COUNT_INCLUDED,
        countExcluded: LBL_COUNT_EXCLUDED
    };

    _caption = '';
    _lines = [];
    _selectable = false;
    _excludedIds = [];

    /** @description The section heading, describing why these lines are being shown. */
    @api
    get caption() {
        return this._caption;
    }
    set caption(value) {
        this._caption = value || '';
    }

    /**
     * @description The commission lines to list, as LineDto: `lineId`, `lineName`, `period`,
     * `commissionDate`, `clientName`, `clientCompany`, `policyId`, `policyName`, `carrierName`,
     * `commissionAmount`, `rate`, `payableAmount`, `rateMissing`, `paidOut`, `payoutId`,
     * `payoutName`.
     */
    @api
    get lines() {
        return this._lines;
    }
    set lines(value) {
        // Copied rather than held by reference: the parent owns this array and a child must never
        // write back into it.
        this._lines = Array.isArray(value) ? value.map((line) => ({ ...line })) : [];
    }

    /**
     * @description Whether each row carries an include checkbox. Off by default, so every existing
     * read-only section — the drill-down and the four informational lists — is unchanged.
     */
    @api
    get selectable() {
        return this._selectable;
    }
    set selectable(value) {
        // Coerced rather than taken as given, so `selectable="true"` in markup is a real Boolean
        // and any other attribute value can never read as truthy.
        this._selectable = value === true || value === 'true';
    }

    /**
     * @description The ids of the lines the owner has UNTICKED. A row is ticked when its id is not
     * in this list, so the default — an empty list — includes everything.
     */
    @api
    get excludedIds() {
        return this._excludedIds;
    }
    set excludedIds(value) {
        // Copied rather than held by reference: the parent owns the exclusion set and this
        // component only asks it to change.
        this._excludedIds = Array.isArray(value) ? value.map((id) => id) : [];
    }

    get hasLines() {
        return this._lines.length > 0;
    }

    /**
     * @description The lines with their display decisions resolved. A line whose policy carries no
     * commission rate has no payable at all — it is marked, never valued at zero.
     * @return {Object[]} One descriptor per line.
     */
    get rows() {
        const excluded = new Set(this._excludedIds);
        return this._lines.map((line) => {
            const included = !excluded.has(line.lineId);
            return {
                key: line.lineId || line.lineName,
                lineId: line.lineId,
                included,
                // An unticked row is dimmed the moment the parent pushes the new set back down, so
                // the tick and the money it decides never disagree on screen.
                rowClass: included
                    ? 'slds-hint-parent line-row'
                    : 'slds-hint-parent line-row line-row_excluded',
                period: line.period,
                clientName: line.clientName,
                policyName: line.policyName,
                payoutName: line.payoutName,
                hasPayoutName: !!line.payoutName,
                carrierNet: moneyView(line.commissionAmount, this.label.negativeAmount),
                payable: moneyView(line.payableAmount, this.label.negativeAmount),
                hasPayable:
                    !line.rateMissing &&
                    line.payableAmount !== null &&
                    line.payableAmount !== undefined
            };
        });
    }

    /** @description The include/exclude tally, shown only where rows can actually be unticked. */
    get showSummary() {
        return this._selectable && this._lines.length > 0;
    }

    get includedCount() {
        const excluded = new Set(this._excludedIds);
        return this._lines.filter((line) => !excluded.has(line.lineId)).length;
    }

    get excludedCount() {
        return this._lines.length - this.includedCount;
    }

    /**
     * @description Asks the parent for a new exclusion set when one row's checkbox is toggled. The
     * component never writes its own `excludedIds` — the parent owns that state and pushes it back
     * down, so what is rendered is always what the parent believes.
     * @param {Event} event The change event from a row checkbox.
     */
    handleLineToggle(event) {
        const lineId = event.currentTarget.dataset.line;
        if (!lineId) {
            return;
        }
        const included = event.currentTarget.checked;
        const excludedIds = this._excludedIds.filter((id) => id !== lineId);
        if (!included) {
            excludedIds.push(lineId);
        }
        this.dispatchEvent(new CustomEvent('exclusionchange', { detail: { excludedIds } }));
    }
}
