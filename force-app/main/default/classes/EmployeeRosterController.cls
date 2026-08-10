/**
 * @description LWC adapter for the company Employee Roster component; delegates to EmployeeRosterService
 * and surfaces controlled errors to the UI.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class EmployeeRosterController {

    @TestVisible
    private static EmployeeRosterService service = new EmployeeRosterService();

    /**
     * @description Lists every employee (active and inactive) for a company account.
     * @param accountId The company account record id.
     * @return The employee rows for the roster.
     */
    @AuraEnabled(cacheable=true)
    public static List<EmployeeRosterService.EmployeeRow> getEmployees(Id accountId) {
        try {
            return service.getRoster(accountId);
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.getEmployees', accountId, ex);
            throw new AuraHandledException(Label.EmployeeRoster_LoadError);
        }
    }

    /**
     * @description Returns the picklist options for the inline-editable Roles and coverage-tier columns.
     * @return Options keyed 'roles' and 'family', each a list of {label, value} maps.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getFieldOptions() {
        try {
            return service.getFieldOptions();
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.getFieldOptions', null, ex);
            throw new AuraHandledException(Label.EmployeeRoster_LoadError);
        }
    }

    /**
     * @description Lists the company's active group-health policies a new employee can be enrolled
     * into, for the Add Employee form.
     * @param accountId The company account record id.
     * @return One option per active group-health policy; empty when the company has none.
     */
    @AuraEnabled(cacheable=true)
    public static List<EmployeeRosterService.PolicyOption> getGroupHealthPolicies(Id accountId) {
        try {
            return service.getGroupHealthPolicies(accountId);
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.getGroupHealthPolicies', accountId, ex);
            throw new AuraHandledException(Label.EmployeeRoster_LoadError);
        }
    }

    /**
     * @description Adds one person to the company as an employee, optionally enrolling them into a
     * group-health policy in the same save. The request arrives as a JSON string for the same
     * reason as saveRelationshipsJson: reactive-proxy objects serialize to empty {} at Apex.
     * @param requestJson JSON object matching EmployeeRosterService.OnboardRequest.
     * @return The contact id of the onboarded employee.
     */
    @AuraEnabled
    public static Id onboardEmployeeJson(String requestJson) {
        try {
            EmployeeRosterService.OnboardRequest request =
                (EmployeeRosterService.OnboardRequest) JSON.deserialize(
                    requestJson, EmployeeRosterService.OnboardRequest.class);
            return service.onboard(new List<EmployeeRosterService.OnboardRequest>{ request })[0];
        } catch (EmployeeRosterService.EmployeeOnboardException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.onboardEmployeeJson', null, ex);
            throw new AuraHandledException('Could not add this employee. Please try again or contact your admin.');
        }
    }

    /**
     * @description Offboards a single employee relationship from the roster UI.
     * @param acrId The AccountContactRelation id of the employee to offboard.
     * @param endDate The coverage end date; defaults to today when null.
     */
    @AuraEnabled
    public static void offboardEmployee(Id acrId, Date endDate) {
        try {
            service.offboard(new Set<Id>{ acrId }, endDate);
        } catch (EmployeeRosterService.EmployeeOffboardException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.offboardEmployee', acrId, ex);
            throw new AuraHandledException('Could not offboard this employee. Please try again or contact your admin.');
        }
    }

    /**
     * @description Saves inline edits to Roles and coverage tier (Family) for the given rows.
     * @param edits The relationship rows to update.
     */
    @AuraEnabled
    public static void saveRelationships(List<EmployeeRosterService.RosterEdit> edits) {
        try {
            service.saveRelationships(edits);
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.saveRelationships', null, ex);
            throw new AuraHandledException('Could not save your changes. Please try again or contact your admin.');
        }
    }

    /**
     * @description Saves inline edits supplied as a JSON string. Passing a serialized string
     * (rather than a list of objects) sidesteps a serialization issue where reactive-proxy
     * draft objects arrive at Apex as empty {} — the client's own JSON.stringify preserves the
     * fields. This is the path the LWC uses for saves.
     * @param editsJson JSON array of {acrId, roles, family} rows to update.
     */
    @AuraEnabled
    public static void saveRelationshipsJson(String editsJson) {
        try {
            List<EmployeeRosterService.RosterEdit> edits =
                (List<EmployeeRosterService.RosterEdit>) JSON.deserialize(
                    editsJson, List<EmployeeRosterService.RosterEdit>.class);
            service.saveRelationships(edits);
        } catch (Exception ex) {
            ExceptionLogger.log('EmployeeRosterController.saveRelationshipsJson', null, ex);
            throw new AuraHandledException('Could not save your changes. Please try again or contact your admin.');
        }
    }
}
