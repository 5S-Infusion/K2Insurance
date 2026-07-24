import { LightningElement, api } from 'lwc';

/**
 * @description Reusable high-visibility error panel for Flow screens: renders the SLDS error
 * pattern (error theme, alert role, icon, headline, next action, and the fault detail in a
 * de-emphasized block) so a fault path reads clearly to a non-technical user.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
export default class FlowErrorPanel extends LightningElement {
    /** @description Bold headline stating what went wrong. */
    @api headline;
    /** @description The specific next action the user should take. */
    @api nextAction;
    /** @description The raw fault detail (e.g. {!$Flow.FaultMessage}), shown de-emphasized. */
    @api message;
    /** @description Optional record context (name/Id and the step that failed). */
    @api context;

    get resolvedHeadline() {
        return this.headline || 'Something went wrong';
    }

    get resolvedNextAction() {
        return (
            this.nextAction ||
            'Please try again. If it keeps happening, contact your Salesforce administrator with the detail below.'
        );
    }
}
