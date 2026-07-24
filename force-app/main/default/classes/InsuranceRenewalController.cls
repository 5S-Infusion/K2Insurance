/**
 * @description LWC adapter for the insuranceRenewalForm component; delegates to
 * InsuranceRenewalService and surfaces controlled, user-friendly errors to the UI.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class InsuranceRenewalController {

    @TestVisible
    private static InsuranceRenewalService service = new InsuranceRenewalService();

    /**
     * @description Loads the renewal-form context (current policy values, record type, member
     * count, and new-term defaults) for a policy.
     * @param insuranceId The policy to renew.
     * @return The renewal context for the form.
     */
    @AuraEnabled(cacheable=true)
    public static InsuranceRenewalService.RenewalContext getRenewalContext(Id insuranceId) {
        try {
            return service.getContext(insuranceId);
        } catch (Exception ex) {
            ExceptionLogger.log('InsuranceRenewalController.getRenewalContext', insuranceId, ex);
            throw new AuraHandledException('Could not load the renewal form. Please try again or contact your admin.');
        }
    }

    /**
     * @description Renews a single policy from the renewal form.
     * @param request The renewal values captured on the form.
     * @return The renewal result — the new policy id and how many members carried over.
     */
    @AuraEnabled
    public static InsuranceRenewalService.RenewalResult renew(InsuranceRenewalService.RenewalRequest request) {
        try {
            return service.renew(new List<InsuranceRenewalService.RenewalRequest>{ request })[0];
        } catch (InsuranceRenewalService.RenewalException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            Id contextId = request == null ? null : request.originalInsuranceId;
            ExceptionLogger.log('InsuranceRenewalController.renew', contextId, ex);
            throw new AuraHandledException('Could not renew this policy. Please try again or contact your admin.');
        }
    }
}
