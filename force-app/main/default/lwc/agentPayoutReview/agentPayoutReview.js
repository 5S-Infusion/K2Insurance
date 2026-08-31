/**
 * @description Review modal for a subagent payout: what the selection contains, what it is worth,
 * and the form that records it. Presentation only — the container owns every server call.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
import { LightningElement, api } from 'lwc';

import LBL_REVIEW from '@salesforce/label/c.AgentManagement_Review';
import LBL_CANCEL from '@salesforce/label/c.AgentManagement_Cancel';
import LBL_RECORD_PAYOUT from '@salesforce/label/c.AgentManagement_RecordPayout';
import LBL_CONFIRM_PAY from '@salesforce/label/c.AgentManagement_ConfirmPay';
import LBL_CARRIER_NET from '@salesforce/label/c.AgentManagement_CarrierNetToK2';
import LBL_CHARGEBACKS from '@salesforce/label/c.AgentManagement_Chargebacks';
import LBL_COMPUTED_PAYABLE from '@salesforce/label/c.AgentManagement_ComputedPayable';
import LBL_AMOUNT_PAID from '@salesforce/label/c.AgentManagement_AmountPaid';
import LBL_PAID_DATE from '@salesforce/label/c.AgentManagement_PaidDate';
import LBL_METHOD from '@salesforce/label/c.AgentManagement_Method';
import LBL_REFERENCE from '@salesforce/label/c.AgentManagement_Reference';
import LBL_NOTES from '@salesforce/label/c.AgentManagement_Notes';
import LBL_RATE_MISSING from '@salesforce/label/c.AgentManagement_RateMissing';
import LBL_RATE_MISSING_HELP from '@salesforce/label/c.AgentManagement_RateMissingHelp';
import LBL_LATE_LINES from '@salesforce/label/c.AgentManagement_LateLines';
import LBL_ALREADY_STAMPED from '@salesforce/label/c.AgentManagement_AlreadyStamped';
import LBL_ZERO_NET_NOTICE from '@salesforce/label/c.AgentManagement_ZeroNetNotice';
import LBL_STALE_TOTALS from '@salesforce/label/c.AgentManagement_StaleTotals';
import LBL_LINES_TO_PAY from '@salesforce/label/c.AgentManagement_LinesToPay';
import LBL_EXCLUDED_LINES from '@salesforce/label/c.AgentManagement_ExcludedLines';
import LBL_NEGATIVE_AMOUNT from '@salesforce/label/c.AgentManagement_NegativeAmount';
import LBL_SAVING from '@salesforce/label/c.AgentManagement_Saving';

/** @description Selectors for everything inside the dialog that can hold focus, in DOM order. */
const FOCUSABLE =
    'button:not([disabled]), input:not([disabled]), lightning-input, lightning-combobox, lightning-textarea';

/**
 * @description An empty PreflightDto, so the modal renders before the first preflight lands. Every
 * member the server sends is named here, so a missing one reads as zero rather than as undefined.
 */
const EMPTY_SNAPSHOT = {
    agentId: null,
    agentName: '',
    periodLabel: '',
    periodStart: '',
    periodEnd: '',
    periods: [],
    lineCount: 0,
    linesNetAmount: 0,
    chargebackAmount: 0,
    chargebackLineCount: 0,
    computedPayable: 0,
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

/**
 * @description All-included totals, so the money block renders before the first preflight lands.
 */
const EMPTY_TOTALS = {
    includedLineCount: 0,
    includedNet: 0,
    includedChargeback: 0,
    includedPayable: 0,
    excludedCount: 0,
    excludedNet: 0
};

/**
 * @description Today as `YYYY-MM-DD` in the user's own time zone, so a late-evening entry west of
 * UTC does not default the payment to tomorrow.
 * @return {String} The local date, ISO formatted.
 */
function today() {
    const now = new Date();
    return new Date(now.getTime() - now.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

/**
 * @description Rounds an amount to cents, half away from zero, matching the server's
 * `Decimal.setScale(2, HALF_UP)`. Every figure this modal echoes back is compared for exact
 * equality server-side, so the two must round the same way. The inputs are all two-decimal
 * currency values and sums of them, so this only ever clears binary-float dust.
 * @param {Number} value The amount to round.
 * @return {Number} The amount at two decimal places.
 */
function money(value) {
    const resolved = Number(value) || 0;
    const cents = Math.round(Math.abs(resolved) * 100 + Number.EPSILON);
    return resolved < 0 ? -cents / 100 : cents / 100;
}

/**
 * @description Splits an amount into its magnitude and its sign so a negative renders in accounting
 * parentheses while `lightning-formatted-number` still does the formatting. Kept local to the
 * bundle: the three payout components share no utils bundle, and this is display shaping, not a
 * rule about money.
 * @param {Number} value The signed amount.
 * @param {String} negativeLabel The label read out in place of the parentheses.
 * @param {String} extraClass An extra class for the wrapper, or undefined.
 * @return {Object} `{ amount, moneyClass, negativeText }`.
 */
function moneyView(value, negativeLabel, extraClass) {
    const resolved = Number(value) || 0;
    const base = extraClass ? `money ${extraClass}` : 'money';
    return {
        amount: Math.abs(resolved),
        moneyClass: resolved < 0 ? `${base} money_negative` : base,
        negativeText: resolved < 0 ? negativeLabel : ''
    };
}

/**
 * @description Whether one line can be valued at all. A line whose policy carries no commission
 * rate is unknown, never zero, so it contributes to no payable — the same rule the server applies.
 * @param {Object} line The LineDto.
 * @return {Boolean} True when the line carries a payable amount.
 */
function hasPayable(line) {
    return !line.rateMissing && line.payableAmount !== null && line.payableAmount !== undefined;
}

/**
 * @description The three numbers the owner is asked to confirm, and the same three the container
 * echoes back to the server as `expectedLineCount` / `expectedLinesNetAmount` /
 * `expectedPayableAmount`. They are compared as values, never hashed.
 * @param {Object} snapshot The preflight snapshot.
 * @return {Object} The three totals.
 */
function confirmedTotals(snapshot) {
    return {
        lineCount: snapshot.lineCount,
        linesNetAmount: snapshot.linesNetAmount,
        computedPayable: snapshot.computedPayable
    };
}

/**
 * @description Whether two sets of confirmed totals are the same figures.
 * @param {Object} left One set of totals.
 * @param {Object} right The other set.
 * @return {Boolean} True when all three match.
 */
function sameTotals(left, right) {
    return (
        left.lineCount === right.lineCount &&
        left.linesNetAmount === right.linesNetAmount &&
        left.computedPayable === right.computedPayable
    );
}

export default class AgentPayoutReview extends LightningElement {
    label = {
        review: LBL_REVIEW,
        cancel: LBL_CANCEL,
        recordPayout: LBL_RECORD_PAYOUT,
        confirmPay: LBL_CONFIRM_PAY,
        carrierNet: LBL_CARRIER_NET,
        chargebacks: LBL_CHARGEBACKS,
        computedPayable: LBL_COMPUTED_PAYABLE,
        amountPaid: LBL_AMOUNT_PAID,
        paidDate: LBL_PAID_DATE,
        method: LBL_METHOD,
        reference: LBL_REFERENCE,
        notes: LBL_NOTES,
        rateMissing: LBL_RATE_MISSING,
        rateMissingHelp: LBL_RATE_MISSING_HELP,
        lateLines: LBL_LATE_LINES,
        alreadyStamped: LBL_ALREADY_STAMPED,
        zeroNetNotice: LBL_ZERO_NET_NOTICE,
        staleTotals: LBL_STALE_TOTALS,
        linesToPay: LBL_LINES_TO_PAY,
        excludedLines: LBL_EXCLUDED_LINES,
        negativeAmount: LBL_NEGATIVE_AMOUNT,
        saving: LBL_SAVING
    };

    snapshot = { ...EMPTY_SNAPSHOT };
    /** @description The lines the owner has UNTICKED. Empty is the default: pay everything. */
    excludedIds = [];
    totals = { ...EMPTY_TOTALS };
    form = {
        amountPaid: 0,
        paidDate: today(),
        paymentMethod: '',
        referenceNumber: '',
        notes: ''
    };
    confirmed = false;
    staleNotice;

    _confirmedTotals;
    _errorMessage;
    _methodOptions = [];
    _focused = false;
    _amountTouched = false;

    /**
     * @description The server's answer for the selected agent and periods: the lines that would be
     * stamped, the money they represent, and the exceptions worth looking at first.
     */
    @api
    get preflight() {
        return this.snapshot;
    }
    set preflight(value) {
        this.applyPreflight(value);
    }

    /** @description The Payment Method picklist, as `{label, value}` entries. */
    @api
    get methodOptions() {
        return this._methodOptions;
    }
    set methodOptions(value) {
        this._methodOptions = Array.isArray(value) ? value.map((option) => ({ ...option })) : [];
    }

    /** @description True while the container is writing, which locks every control. */
    @api isSaving = false;

    /**
     * @description A save failure to show inline, already normalized by the container. A rejected
     * save re-arms the confirmation gate: whatever the owner ticked was ticked against numbers the
     * server has just refused.
     */
    @api
    get errorMessage() {
        return this._errorMessage;
    }
    set errorMessage(value) {
        this._errorMessage = value;
        if (value) {
            this.confirmed = false;
        }
    }

    /**
     * @description Copies the incoming snapshot into local state and reseeds the amount from the
     * included payable. A snapshot whose three totals differ from the ones the owner already
     * confirmed clears the confirmation and says so — nothing is ever recorded against stale
     * figures.
     * @param {Object} value The PreflightDto from the container.
     */
    applyPreflight(value) {
        const incoming = value ? { ...EMPTY_SNAPSHOT, ...value } : { ...EMPTY_SNAPSHOT };
        const next = confirmedTotals(incoming);
        const changed = this._confirmedTotals !== undefined && !sameTotals(this._confirmedTotals, next);
        this.snapshot = incoming;
        // An exclusion only means anything while the line it names is still on offer; one the
        // server no longer lists is dropped rather than carried as a phantom.
        const offered = new Set((incoming.payableLines || []).map((line) => line.lineId));
        this.excludedIds = this.excludedIds.filter((id) => offered.has(id));
        this.recomputeTotals();
        this.form = { ...this.form, amountPaid: this.totals.includedPayable };
        if (changed) {
            this.confirmed = false;
            this.staleNotice = this.label.staleTotals;
        }
        this._confirmedTotals = next;
    }

    /**
     * @description Re-derives what is actually being settled, by taking the excluded lines back out
     * of the server's all-included totals. Subtracting rather than re-adding keeps the default —
     * nothing excluded — bit-identical to the figures the server itself computed, so the routine
     * path can never trip the stale-totals guard on a rounding difference.
     */
    recomputeTotals() {
        const excluded = new Set(this.excludedIds);
        let count = 0;
        let net = 0;
        let chargeback = 0;
        let payable = 0;
        (this.snapshot.payableLines || []).forEach((line) => {
            if (!excluded.has(line.lineId)) {
                return;
            }
            const amount = Number(line.commissionAmount) || 0;
            count += 1;
            net += amount;
            if (amount < 0) {
                chargeback += amount;
            }
            if (hasPayable(line)) {
                payable += Number(line.payableAmount);
            }
        });
        this.totals = {
            includedLineCount: (this.snapshot.lineCount || 0) - count,
            includedNet: money((this.snapshot.linesNetAmount || 0) - net),
            includedChargeback: money((this.snapshot.chargebackAmount || 0) - chargeback),
            includedPayable: money((this.snapshot.computedPayable || 0) - payable),
            excludedCount: count,
            excludedNet: money(net)
        };
    }

    renderedCallback() {
        if (this._focused) {
            return;
        }
        const first = this.template.querySelector('lightning-input[data-id="amount-paid"]');
        if (first) {
            this._focused = true;
            this.focusNode(first);
        }
    }

    get heading() {
        return this.label.review;
    }

    get agentName() {
        return this.snapshot.agentName;
    }

    get periodLabel() {
        return this.snapshot.periodLabel;
    }

    get hasLateLines() {
        return (this.snapshot.lateLineCount || 0) > 0;
    }

    get hasChargebacks() {
        return (this.snapshot.chargebackLineCount || 0) > 0;
    }

    get hasAlreadyStamped() {
        return (this.snapshot.alreadyStampedLineCount || 0) > 0;
    }

    get hasUnrated() {
        return (this.snapshot.unratedLineCount || 0) > 0;
    }

    get hasPayableLines() {
        return this.payableLines.length > 0;
    }

    get hasExclusions() {
        return this.totals.excludedCount > 0;
    }

    /** @description Every open line in the selection — the list the owner ticks and unticks. */
    get payableLines() {
        return this.snapshot.payableLines || [];
    }

    get lateLines() {
        return this.snapshot.lateLines || [];
    }

    get chargebackLines() {
        return this.snapshot.chargebackLines || [];
    }

    get alreadyStampedLines() {
        return this.snapshot.alreadyStampedLines || [];
    }

    get rateMissingLines() {
        return this.snapshot.rateMissingLines || [];
    }

    get includedLineCount() {
        return this.totals.includedLineCount;
    }

    get linesNetAmount() {
        return moneyView(this.totals.includedNet, this.label.negativeAmount);
    }

    get chargebackAmount() {
        return moneyView(this.totals.includedChargeback, this.label.negativeAmount);
    }

    /** @description The figure that seeds the payment, so it is the one the block is built around. */
    get computedPayable() {
        return moneyView(this.totals.includedPayable, this.label.negativeAmount, 'money_primary');
    }

    get excludedCount() {
        return this.totals.excludedCount;
    }

    get excludedNet() {
        return moneyView(this.totals.excludedNet, this.label.negativeAmount);
    }

    get unratedLineCount() {
        return this.snapshot.unratedLineCount;
    }

    get unratedNetAmount() {
        return moneyView(this.snapshot.unratedNetAmount, this.label.negativeAmount);
    }

    /** @description The amount named on the confirmation gate, in the page's money language. */
    get confirmAmount() {
        return moneyView(this.form.amountPaid, this.label.negativeAmount, 'money_gate');
    }

    /**
     * @description True when the carrier paid nothing, or took more back than it paid, across the
     * lines still ticked. Recording it stays possible — the lines still need settling — but the
     * owner is told plainly that no money is leaving.
     */
    get isZeroOrNegativeNet() {
        return (this.totals.includedNet || 0) <= 0;
    }

    get amountPaid() {
        return this.form.amountPaid;
    }

    get paidDate() {
        return this.form.paidDate;
    }

    get paymentMethod() {
        return this.form.paymentMethod;
    }

    get referenceNumber() {
        return this.form.referenceNumber;
    }

    get notes() {
        return this.form.notes;
    }

    get isRecordDisabled() {
        return !this.confirmed || this.isSaving;
    }

    /**
     * @description Updates one form field. Touching the amount invalidates a confirmation that was
     * ticked against the previous one.
     * @param {Event} event The change event from a form control.
     */
    handleFormChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.currentTarget.value;
        this.form = { ...this.form, [field]: value };
        if (field === 'amountPaid') {
            // Once the owner has named their own figure, no later recalculation overwrites it.
            this._amountTouched = true;
            this.confirmed = false;
        }
    }

    /**
     * @description Takes the new exclusion set from the line table and re-prices the payout around
     * it. The amount follows the recomputed payable unless the owner has already typed a figure of
     * their own, which is left exactly as they left it. Either way the confirmation gate re-arms:
     * whatever was ticked was ticked against a different set of lines.
     * @param {CustomEvent} event The table's `exclusionchange` event.
     */
    handleExclusionChange(event) {
        const detail = event.detail || {};
        const incoming = Array.isArray(detail.excludedIds) ? detail.excludedIds : [];
        this.excludedIds = incoming.map((id) => id);
        this.recomputeTotals();
        if (!this._amountTouched) {
            this.form = { ...this.form, amountPaid: this.totals.includedPayable };
        }
        this.confirmed = false;
    }

    handleMethodChange(event) {
        this.form = { ...this.form, paymentMethod: event.detail.value };
    }

    handleConfirmChange(event) {
        this.confirmed = event.currentTarget.checked;
        this.staleNotice = undefined;
    }

    /**
     * @description Hands the completed form up to the container, which owns the write. The payload
     * travels as a JSON string so no reactive proxy can cross the boundary and arrive empty. The
     * three expected totals are the INCLUDED figures, so an exclusion the server does not receive
     * shows up there as a refused save rather than as a silent overpayment.
     */
    handleRecord() {
        const payload = {
            amountPaid: this.form.amountPaid === '' ? null : Number(this.form.amountPaid),
            paidDate: this.form.paidDate,
            paymentMethod: this.form.paymentMethod,
            referenceNumber: this.form.referenceNumber,
            notes: this.form.notes,
            excludedLineIds: this.excludedIds.map((id) => id),
            expectedLineCount: this.totals.includedLineCount,
            expectedLinesNetAmount: this.totals.includedNet,
            expectedPayableAmount: this.totals.includedPayable
        };
        this.dispatchEvent(
            new CustomEvent('recordpayout', { detail: { formJson: JSON.stringify(payload) } })
        );
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('closereview'));
    }

    /**
     * @description Keeps the modal behaving like a dialog from the keyboard: Escape asks the
     * container to close it, and Tab cycles inside it instead of walking out into the board behind
     * the backdrop. Escape is ignored mid-save, when there is nothing safe to cancel.
     * @param {KeyboardEvent} event The key press inside the dialog.
     */
    handleKeyDown(event) {
        if (event.key === 'Escape') {
            if (!this.isSaving) {
                this.handleCancel();
            }
            return;
        }
        if (event.key !== 'Tab') {
            return;
        }
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
}
