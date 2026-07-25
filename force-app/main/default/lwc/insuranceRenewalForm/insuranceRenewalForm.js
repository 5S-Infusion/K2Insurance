import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';
import getRenewalContext from '@salesforce/apex/InsuranceRenewalController.getRenewalContext';
import renew from '@salesforce/apex/InsuranceRenewalController.renewJson';

import LBL_TITLE from '@salesforce/label/c.InsuranceRenewal_Title';
import LBL_CURRENT_TERM from '@salesforce/label/c.InsuranceRenewal_CurrentTerm';
import LBL_NEW_TERM from '@salesforce/label/c.InsuranceRenewal_NewTerm';
import LBL_MEMBERS_CARRY from '@salesforce/label/c.InsuranceRenewal_MembersCarry';
import LBL_NEW_START_DATE from '@salesforce/label/c.InsuranceRenewal_NewStartDate';
import LBL_TERM_MONTHS from '@salesforce/label/c.InsuranceRenewal_TermMonths';
import LBL_PROVIDER from '@salesforce/label/c.InsuranceRenewal_Provider';
import LBL_PREMIUM from '@salesforce/label/c.InsuranceRenewal_Premium';
import LBL_DEDUCTIBLE from '@salesforce/label/c.InsuranceRenewal_Deductible';
import LBL_POLICY_NUMBER from '@salesforce/label/c.InsuranceRenewal_PolicyNumber';
import LBL_BUILDING_LIMIT from '@salesforce/label/c.InsuranceRenewal_BuildingLimit';
import LBL_BPP from '@salesforce/label/c.InsuranceRenewal_BPP';
import LBL_CARRY_MEMBERS from '@salesforce/label/c.InsuranceRenewal_CarryMembers';
import LBL_RENEW from '@salesforce/label/c.InsuranceRenewal_Renew';
import LBL_CANCEL from '@salesforce/label/c.InsuranceRenewal_Cancel';
import LBL_SUCCESS_TITLE from '@salesforce/label/c.InsuranceRenewal_SuccessTitle';
import LBL_SUCCESS_MSG from '@salesforce/label/c.InsuranceRenewal_SuccessMessage';
import LBL_ERROR_TITLE from '@salesforce/label/c.InsuranceRenewal_ErrorTitle';
import LBL_LOAD_ERROR from '@salesforce/label/c.InsuranceRenewal_LoadError';

const GROUP_HEALTH = 'Group_Health';
const AUTO_HOME = 'Auto_Home_Insurance';

/**
 * @description Coerces a form input value to a number, treating blank as null.
 * @param value The raw input value.
 * @return The numeric value, or null when blank.
 */
function toNumber(value) {
    return value === '' || value === null || value === undefined ? null : Number(value);
}

/**
 * @description Record-page action that renews an insurance policy of any record type: shows the
 * current term against the proposed new term, lets the user adjust the new-term values (dates,
 * provider, premium, coverage), and renews via InsuranceRenewalController — cloning the policy,
 * carrying active members (Group Health), and inactivating the old policy.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
export default class InsuranceRenewalForm extends NavigationMixin(LightningElement) {
    /** @description The insurance policy record being renewed. */
    @api recordId;

    label = {
        title: LBL_TITLE,
        currentTerm: LBL_CURRENT_TERM,
        newTerm: LBL_NEW_TERM,
        membersCarry: LBL_MEMBERS_CARRY,
        newStartDate: LBL_NEW_START_DATE,
        termMonths: LBL_TERM_MONTHS,
        provider: LBL_PROVIDER,
        premium: LBL_PREMIUM,
        deductible: LBL_DEDUCTIBLE,
        policyNumber: LBL_POLICY_NUMBER,
        buildingLimit: LBL_BUILDING_LIMIT,
        bpp: LBL_BPP,
        carryMembers: LBL_CARRY_MEMBERS,
        renew: LBL_RENEW,
        cancel: LBL_CANCEL,
        errorTitle: LBL_ERROR_TITLE,
        loadError: LBL_LOAD_ERROR
    };

    context;
    loadError;
    isSaving = false;
    errors = [];

    startDate;
    termMonths;
    providerId;
    premium;
    deductible;
    policyName;
    carryMembers = true;
    buildingCoverageLimit;
    businessPersonalProperty;

    @wire(getRenewalContext, { insuranceId: '$recordId' })
    wiredContext({ data, error }) {
        if (data) {
            this.context = data;
            this.applyDefaults(data);
            this.loadError = undefined;
        } else if (error) {
            this.loadError = reduceErrors(error).join(', ') || this.label.loadError;
        }
    }

    applyDefaults(ctx) {
        this.startDate = ctx.suggestedStartDate;
        this.termMonths = ctx.currentTermMonths;
        this.providerId = ctx.providerId;
        this.premium = ctx.premium;
        this.deductible = ctx.deductible;
        this.policyName = ctx.policyNumber;
        this.buildingCoverageLimit = ctx.buildingCoverageLimit;
        this.businessPersonalProperty = ctx.businessPersonalProperty;
    }

    get hasContext() {
        return this.context && !this.loadError;
    }

    get isGroupHealth() {
        return this.context && this.context.recordTypeDeveloperName === GROUP_HEALTH;
    }

    get isAutoHome() {
        return this.context && this.context.recordTypeDeveloperName === AUTO_HOME;
    }

    get hasMembers() {
        return this.isGroupHealth && this.context.activeMemberCount > 0;
    }

    get memberMessage() {
        return `${this.context.activeMemberCount} ${this.label.membersCarry}`;
    }

    get newEndDate() {
        if (!this.startDate || !this.termMonths) {
            return null;
        }
        // Compute purely from the date parts in UTC so it matches the UTC-rendered display and
        // never shifts a day across the local timezone boundary.
        const [year, month, day] = this.startDate.split('-').map(Number);
        const end = new Date(Date.UTC(year, month - 1 + Number(this.termMonths), day));
        return end.toISOString().slice(0, 10);
    }

    get hasErrors() {
        return this.errors.length > 0;
    }

    get errorMessage() {
        return this.errors.join(', ');
    }

    handleStartDate(event) {
        this.startDate = event.target.value;
    }
    handleTermMonths(event) {
        this.termMonths = event.target.value;
    }
    handleProviderChange(event) {
        this.providerId = event.detail.recordId;
    }
    handlePremium(event) {
        this.premium = event.target.value;
    }
    handleDeductible(event) {
        this.deductible = event.target.value;
    }
    handlePolicyNumber(event) {
        this.policyName = event.target.value;
    }
    handleBuildingLimit(event) {
        this.buildingCoverageLimit = event.target.value;
    }
    handleBpp(event) {
        this.businessPersonalProperty = event.target.value;
    }
    handleCarryToggle(event) {
        this.carryMembers = event.target.checked;
    }

    async handleRenew() {
        this.isSaving = true;
        this.errors = [];
        try {
            // Build a fresh plain literal and send it as a JSON string: an object read off a
            // reactive field can reach Apex as an empty {} (all fields null). JSON.stringify
            // preserves the values across the boundary.
            const request = {
                originalInsuranceId: this.context ? this.context.recordId : this.recordId,
                startDate: this.startDate || null,
                termMonths: toNumber(this.termMonths),
                providerId: this.providerId || null,
                premium: toNumber(this.premium),
                deductible: toNumber(this.deductible),
                policyName: this.policyName || null,
                carryMembers: this.carryMembers,
                buildingCoverageLimit: toNumber(this.buildingCoverageLimit),
                businessPersonalProperty: toNumber(this.businessPersonalProperty)
            };
            const result = await renew({ requestJson: JSON.stringify(request) });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: LBL_SUCCESS_TITLE,
                    message: LBL_SUCCESS_MSG,
                    variant: 'success'
                })
            );
            this.close();
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: result.newInsuranceId,
                    objectApiName: 'Insurance__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.errors = reduceErrors(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: LBL_ERROR_TITLE,
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.close();
    }

    close() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
