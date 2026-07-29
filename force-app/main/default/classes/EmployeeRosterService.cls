/**
 * @description Business logic for the company Employee Roster: lists a company's active employees
 * and offboards them (ends group-health coverage, clears employment, marks the Contact inactive).
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class EmployeeRosterService {

    private static final String GROUP_HEALTH_RT = 'Group_Health';
    private static final String CONTACT_INACTIVE = 'Inactive';

    /**
     * @description Raised when an offboard request is empty or resolves to no employee relationship.
     */
    public class EmployeeOffboardException extends Exception {}

    /**
     * @description Returns the active picklist options for the inline-editable relationship fields
     * (Roles and coverage tier), keyed 'roles' and 'family', each a list of {label, value} maps.
     * @return The picklist options for the editable columns.
     */
    public Map<String, List<Map<String, String>>> getFieldOptions() {
        return new Map<String, List<Map<String, String>>>{
            'roles' => picklistOptions(AccountContactRelation.Roles.getDescribe().getPicklistValues()),
            'family' => picklistOptions(AccountContactRelation.Family__c.getDescribe().getPicklistValues())
        };
    }

    /**
     * @description Maps active picklist entries to {label, value} option maps.
     * @param entries The picklist entries to map.
     * @return The active options.
     */
    private List<Map<String, String>> picklistOptions(List<Schema.PicklistEntry> entries) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{ 'label' => entry.getLabel(), 'value' => entry.getValue() });
            }
        }
        return options;
    }

    /**
     * @description Inbound inline edit for one employment relationship row.
     */
    public class RosterEdit {
        @AuraEnabled public Id acrId;
        @AuraEnabled public String roles;
        @AuraEnabled public String family;
    }

    /**
     * @description Display model for one employee row in the roster datatable.
     */
    public class EmployeeRow {
        @AuraEnabled public Id acrId;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String contactUrl;
        @AuraEnabled public String roles;
        @AuraEnabled public String plans;
        @AuraEnabled public String family;
        @AuraEnabled public Boolean activeIns;
        @AuraEnabled public Boolean empStatus;
        @AuraEnabled public String company;
        @AuraEnabled public Id companyId;
        @AuraEnabled public String companyUrl;
    }

    /**
     * @description Returns every employee (active and inactive) for a company account AND all of
     * its sub-companies in the account hierarchy, with the roster display fields, in the running
     * user's context. On a parent this rolls up the whole hierarchy so all employees are visible at
     * once; on a leaf company it returns only that company. Emp.Status is display-only here; it is
     * changed only through offboard.
     * @param accountId The company account whose roster to list (root of the roll-up).
     * @return The employee rows, ordered by company then contact name.
     */
    public List<EmployeeRow> getRoster(Id accountId) {
        Set<Id> accountIds = collectHierarchy(accountId);
        List<EmployeeRow> rows = new List<EmployeeRow>();
        // IsDirect = true keeps the roster to people directly employed by each company; it also
        // prevents a contact who was reparented to a sub-company (leaving an indirect relationship
        // on the parent) from appearing twice in a parent's hierarchy roll-up.
        for (AccountContactRelation acr : [
            SELECT Id, ContactId, Contact.Name, Roles, Emp_Status__c, AccountId, Account.Name,
                   Family__c, Contact.Active_Insurance_Summary__c, Contact.Has_Active_Insurance__c
            FROM AccountContactRelation
            WHERE AccountId IN :accountIds AND IsDirect = true
            WITH USER_MODE
            ORDER BY Account.Name, Contact.Name
        ]) {
            EmployeeRow row = new EmployeeRow();
            row.acrId = acr.Id;
            row.contactId = acr.ContactId;
            row.name = acr.Contact.Name;
            row.contactUrl = '/' + acr.ContactId;
            row.roles = acr.Roles;
            row.plans = acr.Contact.Active_Insurance_Summary__c;
            row.family = acr.Family__c;
            row.activeIns = acr.Contact.Has_Active_Insurance__c;
            row.empStatus = acr.Emp_Status__c;
            row.company = acr.Account.Name;
            row.companyId = acr.AccountId;
            row.companyUrl = '/' + acr.AccountId;
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description Collects a company account and every descendant company in the account
     * hierarchy, so a parent's roster rolls up all sub-company employees. Bulk-safe and
     * cycle-safe (each account is visited once).
     * @param rootId The account to start the walk from.
     * @return The root account id plus every descendant account id.
     */
    private Set<Id> collectHierarchy(Id rootId) {
        Set<Id> accountIds = new Set<Id>{ rootId };
        Set<Id> frontier = new Set<Id>{ rootId };
        while (!frontier.isEmpty()) {
            List<Account> children = [
                SELECT Id FROM Account WHERE ParentId IN :frontier WITH USER_MODE
            ];
            frontier = new Set<Id>();
            for (Account child : children) {
                if (accountIds.add(child.Id)) {
                    frontier.add(child.Id);
                }
            }
        }
        return accountIds;
    }

    /**
     * @description Offboards one or more employees: ends and inactivates their active group-health
     * coverage junctions (the shared group policy itself is left intact), turns off employment
     * (Emp.Status) on the relationship, and marks their Contacts inactive. Bulk-safe, user-mode DML.
     * @param acrIds The AccountContactRelation ids to offboard.
     * @param endDate The coverage end date to stamp on the junctions; defaults to today when null.
     */
    public void offboard(Set<Id> acrIds, Date endDate) {
        if (acrIds == null || acrIds.isEmpty()) {
            throw new EmployeeOffboardException('No employee was selected to offboard.');
        }
        Date effectiveEnd = endDate == null ? Date.today() : endDate;

        Map<Id, AccountContactRelation> acrById = new Map<Id, AccountContactRelation>([
            SELECT Id, ContactId
            FROM AccountContactRelation
            WHERE Id IN :acrIds
            WITH USER_MODE
        ]);
        if (acrById.isEmpty()) {
            throw new EmployeeOffboardException('The selected employee relationship no longer exists.');
        }

        Set<Id> contactIds = new Set<Id>();
        for (AccountContactRelation acr : acrById.values()) {
            contactIds.add(acr.ContactId);
        }

        List<ContactInsuranceAssociation__c> coverageToEnd = [
            SELECT Id
            FROM ContactInsuranceAssociation__c
            WHERE Contact__c IN :contactIds
              AND Active__c = true
              AND Insurance__r.RecordType.DeveloperName = :GROUP_HEALTH_RT
            WITH USER_MODE
        ];
        for (ContactInsuranceAssociation__c cia : coverageToEnd) {
            cia.Coverage_End_Date__c = effectiveEnd;
            cia.Active__c = false;
        }

        List<AccountContactRelation> employmentUpdates = new List<AccountContactRelation>();
        for (Id acrId : acrById.keySet()) {
            employmentUpdates.add(new AccountContactRelation(Id = acrId, Emp_Status__c = false));
        }

        List<Contact> contactUpdates = new List<Contact>();
        for (Id contactId : contactIds) {
            contactUpdates.add(new Contact(Id = contactId, Status__c = CONTACT_INACTIVE));
        }

        if (!coverageToEnd.isEmpty()) {
            Database.update(coverageToEnd, AccessLevel.USER_MODE);
        }
        Database.update(employmentUpdates, AccessLevel.USER_MODE);
        Database.update(contactUpdates, AccessLevel.USER_MODE);
    }

    /**
     * @description Applies inline edits to the Roles and coverage-tier (Family) fields on the
     * given employment relationships. Bulk-safe, user-mode DML.
     * @param edits The relationship rows to update.
     */
    public void saveRelationships(List<RosterEdit> edits) {
        if (edits == null || edits.isEmpty()) {
            return;
        }
        List<AccountContactRelation> updates = new List<AccountContactRelation>();
        for (RosterEdit edit : edits) {
            if (edit.acrId == null) {
                continue;
            }
            updates.add(new AccountContactRelation(
                Id = edit.acrId,
                Roles = edit.roles,
                Family__c = edit.family
            ));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.USER_MODE);
        }
    }
}
