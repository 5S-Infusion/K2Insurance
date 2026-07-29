/**
 * @description Tests for EmployeeRosterService — roster read and bulk offboard behavior.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class EmployeeRosterServiceTest {

    /**
     * @description getRoster returns one row per employee — active and inactive — with display
     * fields (including Emp.Status) set.
     */
    @isTest
    static void getRosterReturnsAllEmployees() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Id companyId = [SELECT AccountId FROM AccountContactRelation WHERE Id = :relations[0].Id].AccountId;
        // Make one employee inactive; the roster must still return it.
        update new AccountContactRelation(Id = relations[0].Id, Emp_Status__c = false);

        Test.startTest();
        List<EmployeeRosterService.EmployeeRow> rows = new EmployeeRosterService().getRoster(companyId);
        Test.stopTest();

        Assert.areEqual(20, rows.size(), 'Should return every employee, active and inactive');
        Assert.isNotNull(rows[0].name, 'Row should carry the contact name');
        Assert.isNotNull(rows[0].contactUrl, 'Row should carry a contact link');
        Assert.isNotNull(rows[0].acrId, 'Row should carry the relationship id');
        Integer inactive = 0;
        for (EmployeeRosterService.EmployeeRow row : rows) {
            if (row.empStatus == false) {
                inactive++;
            }
        }
        Assert.areEqual(1, inactive, 'The inactive employee should still be present with Emp.Status off');
    }

    /**
     * @description getRoster on a parent company rolls up employees from its sub-companies and
     * labels each row with its own company; getRoster on the sub-company returns only its own.
     */
    @isTest
    static void getRosterRollsUpChildCompanies() {
        List<AccountContactRelation> parentRelations = EmployeeRosterTestData.buildRoster(3);
        Id parentId = [SELECT AccountId FROM AccountContactRelation WHERE Id = :parentRelations[0].Id].AccountId;
        AccountContactRelation childAcr =
            EmployeeRosterTestData.addChildCompanyEmployee(parentId, 'Roster Child Co');
        AccountContactRelation childDetail =
            [SELECT AccountId, ContactId FROM AccountContactRelation WHERE Id = :childAcr.Id];
        Id childId = childDetail.AccountId;
        // Indirect relationship of the sub-company employee back to the parent: it must NOT create
        // a duplicate row in the parent roll-up (the roster shows direct employment only).
        insert new AccountContactRelation(ContactId = childDetail.ContactId, AccountId = parentId);

        Test.startTest();
        List<EmployeeRosterService.EmployeeRow> parentRows = new EmployeeRosterService().getRoster(parentId);
        List<EmployeeRosterService.EmployeeRow> childRows = new EmployeeRosterService().getRoster(childId);
        Test.stopTest();

        Assert.areEqual(4, parentRows.size(),
            'Parent roster should roll up the sub-company employee once, excluding the indirect relationship');
        Boolean sawChild = false;
        for (EmployeeRosterService.EmployeeRow row : parentRows) {
            Assert.isNotNull(row.company, 'Each row should carry its company name');
            Assert.isNotNull(row.companyId, 'Each row should carry its company id');
            if (row.acrId == childAcr.Id) {
                sawChild = true;
                Assert.areEqual('Roster Child Co', row.company, 'Sub-company employee should be labeled with it');
            }
        }
        Assert.isTrue(sawChild, 'The sub-company employee should appear in the parent roster');
        Assert.areEqual(1, childRows.size(), 'A leaf company roster should return only its own employees');
    }

    /**
     * @description Bulk offboard (>=20) ends group-health coverage, clears employment, and
     * marks each Contact inactive.
     */
    @isTest
    static void offboardBulkEndsCoverageEmploymentAndContact() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(25);
        Set<Id> acrIds = new Map<Id, AccountContactRelation>(relations).keySet();
        Set<Id> contactIds = new Set<Id>();
        for (AccountContactRelation acr : [SELECT ContactId FROM AccountContactRelation WHERE Id IN :acrIds]) {
            contactIds.add(acr.ContactId);
        }
        Date endDate = Date.today();

        Test.startTest();
        new EmployeeRosterService().offboard(acrIds, endDate);
        Test.stopTest();

        Integer stillEmployed = [
            SELECT COUNT() FROM AccountContactRelation WHERE Id IN :acrIds AND Emp_Status__c = true
        ];
        Assert.areEqual(0, stillEmployed, 'Every relationship should have Emp.Status turned off');

        Integer inactiveContacts = [
            SELECT COUNT() FROM Contact WHERE Id IN :contactIds AND Status__c = 'Inactive'
        ];
        Assert.areEqual(25, inactiveContacts, 'Every contact should be marked Inactive');

        List<ContactInsuranceAssociation__c> coverage = [
            SELECT Active__c, Coverage_End_Date__c
            FROM ContactInsuranceAssociation__c WHERE Contact__c IN :contactIds
        ];
        Assert.areEqual(25, coverage.size(), 'Coverage junctions should still exist');
        for (ContactInsuranceAssociation__c cia : coverage) {
            Assert.isFalse(cia.Active__c, 'Coverage should be inactivated');
            Assert.areEqual(endDate, cia.Coverage_End_Date__c, 'Coverage end date should be stamped');
        }
    }

    /**
     * @description offboard defaults the end date to today when none is supplied.
     */
    @isTest
    static void offboardDefaultsEndDateToToday() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Set<Id> acrIds = new Map<Id, AccountContactRelation>(relations).keySet();

        Test.startTest();
        new EmployeeRosterService().offboard(acrIds, null);
        Test.stopTest();

        Integer endedToday = [
            SELECT COUNT() FROM ContactInsuranceAssociation__c
            WHERE Coverage_End_Date__c = :Date.today() AND Active__c = false
        ];
        Assert.areEqual(20, endedToday, 'A null end date should default to today');
    }

    /**
     * @description offboard rejects an empty request with a typed exception.
     */
    @isTest
    static void offboardWithNoIdsThrows() {
        Test.startTest();
        try {
            new EmployeeRosterService().offboard(new Set<Id>(), Date.today());
            Assert.fail('Expected EmployeeOffboardException for an empty selection');
        } catch (EmployeeRosterService.EmployeeOffboardException ex) {
            Assert.isNotNull(ex.getMessage(), 'The exception should carry a user message');
        }
        Test.stopTest();
    }

    /**
     * @description saveRelationships applies Roles and coverage-tier edits in bulk (>=20).
     */
    @isTest
    static void saveRelationshipsUpdatesRolesAndFamily() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Set<Id> acrIds = new Map<Id, AccountContactRelation>(relations).keySet();
        List<EmployeeRosterService.RosterEdit> edits = new List<EmployeeRosterService.RosterEdit>();
        for (AccountContactRelation acr : relations) {
            EmployeeRosterService.RosterEdit edit = new EmployeeRosterService.RosterEdit();
            edit.acrId = acr.Id;
            edit.roles = 'Manager';
            edit.family = 'EF';
            edits.add(edit);
        }

        Test.startTest();
        new EmployeeRosterService().saveRelationships(edits);
        Test.stopTest();

        Integer updated = [
            SELECT COUNT() FROM AccountContactRelation
            WHERE Id IN :acrIds AND Roles = 'Manager' AND Family__c = 'EF'
        ];
        Assert.areEqual(20, updated, 'All rows should have Roles and coverage tier updated');
    }

    /**
     * @description saveRelationships is a safe no-op for an empty list.
     */
    @isTest
    static void saveRelationshipsIgnoresEmpty() {
        Test.startTest();
        new EmployeeRosterService().saveRelationships(new List<EmployeeRosterService.RosterEdit>());
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM AccountContactRelation WHERE Roles = 'Manager'],
            'No relationships should be changed for an empty edit list');
    }

    /**
     * @description getFieldOptions returns active Roles and coverage-tier picklist options.
     */
    @isTest
    static void getFieldOptionsReturnsPicklists() {
        Test.startTest();
        Map<String, List<Map<String, String>>> options = new EmployeeRosterService().getFieldOptions();
        Test.stopTest();

        Assert.isTrue(options.containsKey('roles'), 'Roles options should be present');
        Assert.isTrue(options.containsKey('family'), 'Coverage-tier options should be present');
        Assert.isFalse(options.get('family').isEmpty(), 'Coverage tier should expose EO/ES/ED/EF');
        Assert.isNotNull(options.get('family')[0].get('value'), 'Each option should carry a value');
    }
}
