/**
 * @description Tests for EmployeeRosterService — roster read, onboard, and bulk offboard behavior.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class EmployeeRosterServiceTest {

    /**
     * @description Builds a minimal onboard request for a brand-new person at a company.
     * @param accountId The company to employ them at.
     * @param lastName The new person's last name.
     * @return The request, with no coverage attached.
     */
    private static EmployeeRosterService.OnboardRequest newPersonRequest(Id accountId, String lastName) {
        EmployeeRosterService.OnboardRequest req = new EmployeeRosterService.OnboardRequest();
        req.accountId = accountId;
        req.firstName = 'Test';
        req.lastName = lastName;
        req.roles = 'Employee';
        req.family = 'EO';
        req.empStatus = true;
        return req;
    }

    /**
     * @description Returns the company account behind a roster relationship.
     * @param acrId The relationship to read.
     * @return The company account id.
     */
    private static Id companyOf(Id acrId) {
        return [SELECT AccountId FROM AccountContactRelation WHERE Id = :acrId].AccountId;
    }

    /**
     * @description Returns the company's group-health policy created by the test factory.
     * @param companyId The company account id.
     * @return The policy id.
     */
    private static Id policyOf(Id companyId) {
        return [SELECT Id FROM Insurance__c WHERE Company__c = :companyId LIMIT 1].Id;
    }

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
     * @description Onboarding a brand-new person creates the Contact under the company, stamps the
     * platform-created direct relationship, and enrols them into the named policy keeping the
     * member-level start date that was entered — not the group policy's own start date.
     */
    @isTest
    static void onboardCreatesEmployeeRelationshipAndCoverage() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);
        Id policyId = policyOf(companyId);
        Date joinDate = Date.today().addDays(10);

        EmployeeRosterService.OnboardRequest req = newPersonRequest(companyId, 'Onboard Alpha');
        req.insuranceId = policyId;
        req.coverageStartDate = joinDate;
        req.medical = true;
        req.dental = true;
        req.vision = false;

        Test.startTest();
        List<Id> contactIds = new EmployeeRosterService()
            .onboard(new List<EmployeeRosterService.OnboardRequest>{ req });
        Test.stopTest();

        Assert.areEqual(1, contactIds.size(), 'One contact id should be returned');
        Contact created = [
            SELECT AccountId, FirstName, LastName, Status__c FROM Contact WHERE Id = :contactIds[0]
        ];
        Assert.areEqual(companyId, created.AccountId, 'The new employee should belong to the company');
        Assert.areEqual('Active', created.Status__c, 'A new employee should be Active');

        List<AccountContactRelation> employment = [
            SELECT Roles, Family__c, Emp_Status__c, IsDirect
            FROM AccountContactRelation
            WHERE AccountId = :companyId AND ContactId = :contactIds[0]
        ];
        Assert.areEqual(1, employment.size(), 'Exactly one relationship should exist — updated, not inserted');
        Assert.isTrue(employment[0].IsDirect, 'The relationship must be direct so the roster lists it');
        Assert.areEqual('Employee', employment[0].Roles, 'Roles should be stamped');
        Assert.areEqual('EO', employment[0].Family__c, 'Coverage tier should be stamped');
        Assert.isTrue(employment[0].Emp_Status__c, 'The new employee should be marked employed');

        List<ContactInsuranceAssociation__c> coverage = [
            SELECT Insurance__c, Coverage_Start_Date__c, Active__c, Medical__c, Dental__c, Vision__c
            FROM ContactInsuranceAssociation__c WHERE Contact__c = :contactIds[0]
        ];
        Assert.areEqual(1, coverage.size(), 'One coverage junction should be created');
        Assert.areEqual(policyId, coverage[0].Insurance__c, 'Coverage should point at the chosen policy');
        Assert.areEqual(joinDate, coverage[0].Coverage_Start_Date__c,
            'The entered member start date must survive the date-sync automation');
        Assert.isTrue(coverage[0].Active__c, 'New coverage should be active');
        Assert.isTrue(coverage[0].Medical__c, 'Medical should be recorded');
        Assert.isTrue(coverage[0].Dental__c, 'Dental should be recorded');
        Assert.isFalse(coverage[0].Vision__c, 'Vision was not selected');
    }

    /**
     * @description Onboarding without a policy creates the employment relationship only.
     */
    @isTest
    static void onboardWithoutPolicyCreatesNoCoverage() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);

        Test.startTest();
        List<Id> contactIds = new EmployeeRosterService().onboard(
            new List<EmployeeRosterService.OnboardRequest>{ newPersonRequest(companyId, 'Onboard NoCover') });
        Test.stopTest();

        Assert.areEqual(1, [
            SELECT COUNT() FROM AccountContactRelation
            WHERE AccountId = :companyId AND ContactId = :contactIds[0]
        ], 'The employment relationship should still be created');
        Assert.areEqual(0, [
            SELECT COUNT() FROM ContactInsuranceAssociation__c WHERE Contact__c = :contactIds[0]
        ], 'No coverage should be created when no policy was chosen');
    }

    /**
     * @description An existing contact with no company is attached to this one, reusing the direct
     * relationship the platform creates rather than inserting a second one.
     */
    @isTest
    static void onboardExistingContactAttachesToCompany() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);
        Contact freeAgent = new Contact(LastName = 'Onboard Existing', Status__c = 'Inactive');
        insert freeAgent;

        EmployeeRosterService.OnboardRequest req = newPersonRequest(companyId, null);
        req.contactId = freeAgent.Id;
        req.firstName = null;

        Test.startTest();
        new EmployeeRosterService().onboard(new List<EmployeeRosterService.OnboardRequest>{ req });
        Test.stopTest();

        Contact attached = [SELECT AccountId, Status__c FROM Contact WHERE Id = :freeAgent.Id];
        Assert.areEqual(companyId, attached.AccountId, 'The contact should now belong to the company');
        Assert.areEqual('Active', attached.Status__c, 'Onboarding should reactivate the contact');
        Assert.areEqual(1, [
            SELECT COUNT() FROM AccountContactRelation
            WHERE AccountId = :companyId AND ContactId = :freeAgent.Id
        ], 'Only the platform-created direct relationship should exist');
    }

    /**
     * @description A contact already employed by a different company is rejected rather than
     * silently reparented.
     */
    @isTest
    static void onboardExistingContactAtAnotherCompanyThrows() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);
        Id otherContactId = [SELECT ContactId FROM AccountContactRelation WHERE Id = :relations[0].Id].ContactId;
        Account otherCompany = new Account(Name = 'Roster Other Co');
        insert otherCompany;
        update new Contact(Id = otherContactId, AccountId = otherCompany.Id);

        EmployeeRosterService.OnboardRequest req = newPersonRequest(companyId, null);
        req.contactId = otherContactId;

        Test.startTest();
        try {
            new EmployeeRosterService().onboard(new List<EmployeeRosterService.OnboardRequest>{ req });
            Assert.fail('Expected EmployeeOnboardException for a contact at another company');
        } catch (EmployeeRosterService.EmployeeOnboardException ex) {
            Assert.isTrue(ex.getMessage().contains('Roster Other Co'),
                'The message should name the company the contact already belongs to');
        }
        Test.stopTest();
    }

    /**
     * @description Bulk onboard (>=20) creates every employee and their coverage in one pass.
     */
    @isTest
    static void onboardBulkCreatesEveryEmployee() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);
        Id policyId = policyOf(companyId);

        List<EmployeeRosterService.OnboardRequest> requests = new List<EmployeeRosterService.OnboardRequest>();
        for (Integer i = 0; i < 25; i++) {
            EmployeeRosterService.OnboardRequest req = newPersonRequest(companyId, 'Onboard Bulk ' + i);
            req.insuranceId = policyId;
            req.coverageStartDate = Date.today();
            req.medical = true;
            requests.add(req);
        }

        Test.startTest();
        List<Id> contactIds = new EmployeeRosterService().onboard(requests);
        Test.stopTest();

        Assert.areEqual(25, contactIds.size(), 'Every request should resolve to a contact');
        Assert.areEqual(25, [
            SELECT COUNT() FROM AccountContactRelation
            WHERE AccountId = :companyId AND ContactId IN :contactIds AND Emp_Status__c = true
        ], 'Every employee should have an employed relationship');
        Assert.areEqual(25, [
            SELECT COUNT() FROM ContactInsuranceAssociation__c
            WHERE Contact__c IN :contactIds AND Insurance__c = :policyId
        ], 'Every employee should be enrolled');
    }

    /**
     * @description onboard rejects an empty batch and a request with no name and no contact.
     */
    @isTest
    static void onboardRejectsIncompleteRequests() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);
        EmployeeRosterService service = new EmployeeRosterService();

        Test.startTest();
        try {
            service.onboard(new List<EmployeeRosterService.OnboardRequest>());
            Assert.fail('Expected EmployeeOnboardException for an empty batch');
        } catch (EmployeeRosterService.EmployeeOnboardException ex) {
            Assert.isNotNull(ex.getMessage(), 'The exception should carry a user message');
        }

        EmployeeRosterService.OnboardRequest nameless = newPersonRequest(companyId, null);
        try {
            service.onboard(new List<EmployeeRosterService.OnboardRequest>{ nameless });
            Assert.fail('Expected EmployeeOnboardException when neither a name nor a contact is given');
        } catch (EmployeeRosterService.EmployeeOnboardException ex) {
            Assert.isNotNull(ex.getMessage(), 'The exception should carry a user message');
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE LastName LIKE 'Onboard%'],
            'A rejected request should create nothing');
    }

    /**
     * @description getGroupHealthPolicies lists the company's active group-health policies, and
     * nothing for a company that has none.
     */
    @isTest
    static void getGroupHealthPoliciesListsActivePolicies() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = companyOf(relations[0].Id);
        Account emptyCompany = new Account(Name = 'Roster Empty Co');
        insert emptyCompany;

        Test.startTest();
        EmployeeRosterService service = new EmployeeRosterService();
        List<EmployeeRosterService.PolicyOption> options = service.getGroupHealthPolicies(companyId);
        List<EmployeeRosterService.PolicyOption> none = service.getGroupHealthPolicies(emptyCompany.Id);
        List<EmployeeRosterService.PolicyOption> noAccount = service.getGroupHealthPolicies(null);
        Test.stopTest();

        Assert.areEqual(1, options.size(), 'The company has one active group-health policy');
        Assert.areEqual(policyOf(companyId), options[0].policyId, 'The policy id should be returned');
        Assert.isTrue(options[0].label.contains('ROSTER-GH-TEST'), 'The label should name the policy');
        Assert.isTrue(none.isEmpty(), 'A company with no policy should offer none');
        Assert.isTrue(noAccount.isEmpty(), 'A null company should offer none');
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
