/**
 * @description Tests for EmployeeRosterController — delegation to the service and controlled UI errors.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class EmployeeRosterControllerTest {

    /**
     * @description getEmployees returns the roster produced by the service.
     */
    @isTest
    static void getEmployeesReturnsRoster() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Id companyId = [SELECT AccountId FROM AccountContactRelation WHERE Id = :relations[0].Id].AccountId;

        Test.startTest();
        List<EmployeeRosterService.EmployeeRow> rows = EmployeeRosterController.getEmployees(companyId);
        Test.stopTest();

        Assert.areEqual(20, rows.size(), 'Controller should return the employees from the service');
    }

    /**
     * @description getGroupHealthPolicies returns the company's enrollable policies.
     */
    @isTest
    static void getGroupHealthPoliciesReturnsOptions() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = [SELECT AccountId FROM AccountContactRelation WHERE Id = :relations[0].Id].AccountId;

        Test.startTest();
        List<EmployeeRosterService.PolicyOption> options =
            EmployeeRosterController.getGroupHealthPolicies(companyId);
        Test.stopTest();

        Assert.areEqual(1, options.size(), 'The company has one active group-health policy');
        Assert.isNotNull(options[0].label, 'Each option should carry a display label');
    }

    /**
     * @description onboardEmployeeJson deserializes the form payload and creates the employee, the
     * employment relationship, and the coverage junction.
     */
    @isTest
    static void onboardEmployeeJsonCreatesEmployee() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = [SELECT AccountId FROM AccountContactRelation WHERE Id = :relations[0].Id].AccountId;
        Id policyId = [SELECT Id FROM Insurance__c WHERE Company__c = :companyId LIMIT 1].Id;
        Date joinDate = Date.today().addDays(5);
        String payload = JSON.serialize(new Map<String, Object>{
            'accountId' => companyId,
            'firstName' => 'Alison',
            'lastName' => 'Controller',
            'roles' => 'Employee',
            'family' => 'EO',
            'empStatus' => true,
            'insuranceId' => policyId,
            'coverageStartDate' => String.valueOf(joinDate),
            'medical' => true,
            'dental' => false,
            'vision' => false
        });

        Test.startTest();
        Id contactId = EmployeeRosterController.onboardEmployeeJson(payload);
        Test.stopTest();

        Assert.isNotNull(contactId, 'The new contact id should be returned');
        Assert.areEqual(companyId, [SELECT AccountId FROM Contact WHERE Id = :contactId].AccountId,
            'The employee should belong to the company');
        Assert.areEqual(joinDate, [
            SELECT Coverage_Start_Date__c FROM ContactInsuranceAssociation__c WHERE Contact__c = :contactId
        ].Coverage_Start_Date__c, 'The entered member start date should be stored');
    }

    /**
     * @description onboardEmployeeJson surfaces the service's own message for a request it can
     * refuse (no name and no contact), rather than a generic failure.
     */
    @isTest
    static void onboardEmployeeJsonInvalidThrowsAuraHandled() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(1);
        Id companyId = [SELECT AccountId FROM AccountContactRelation WHERE Id = :relations[0].Id].AccountId;
        String payload = JSON.serialize(new Map<String, Object>{ 'accountId' => companyId });

        Test.startTest();
        try {
            EmployeeRosterController.onboardEmployeeJson(payload);
            Assert.fail('Expected an AuraHandledException for an unnamed employee');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled UI exception should be thrown');
        }
        Test.stopTest();
    }

    /**
     * @description offboardEmployee delegates to the service and turns off employment for each row.
     */
    @isTest
    static void offboardEmployeeInactivatesEmployees() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Set<Id> acrIds = new Map<Id, AccountContactRelation>(relations).keySet();

        Test.startTest();
        for (Id acrId : acrIds) {
            EmployeeRosterController.offboardEmployee(acrId, Date.today());
        }
        Test.stopTest();

        Integer stillEmployed = [
            SELECT COUNT() FROM AccountContactRelation WHERE Id IN :acrIds AND Emp_Status__c = true
        ];
        Assert.areEqual(0, stillEmployed, 'All offboarded relationships should have Emp.Status off');
    }

    /**
     * @description offboardEmployee surfaces a controlled AuraHandledException when the request is invalid.
     */
    @isTest
    static void offboardEmployeeInvalidThrowsAuraHandled() {
        Test.startTest();
        try {
            EmployeeRosterController.offboardEmployee(null, Date.today());
            Assert.fail('Expected an AuraHandledException for a missing relationship');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled UI exception should be thrown');
        }
        Test.stopTest();
    }

    /**
     * @description Both controller entry points log and surface a controlled error when the
     * service fails unexpectedly.
     */
    @isTest
    static void controllerSurfacesServiceFailures() {
        EmployeeRosterService mock = (EmployeeRosterService) Test.createStub(
            EmployeeRosterService.class, new ThrowingServiceMock()
        );
        EmployeeRosterController.service = mock;
        Id fakeId = '001000000000000AAA';

        Test.startTest();
        try {
            EmployeeRosterController.getEmployees(fakeId);
            Assert.fail('getEmployees should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled load error should be thrown');
        }
        try {
            EmployeeRosterController.offboardEmployee(fakeId, Date.today());
            Assert.fail('offboardEmployee should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled offboard error should be thrown');
        }
        try {
            EmployeeRosterController.saveRelationships(new List<EmployeeRosterService.RosterEdit>{
                new EmployeeRosterService.RosterEdit()
            });
            Assert.fail('saveRelationships should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled save error should be thrown');
        }
        try {
            EmployeeRosterController.getFieldOptions();
            Assert.fail('getFieldOptions should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled options error should be thrown');
        }
        Test.stopTest();
    }

    /**
     * @description getFieldOptions delegates to the service and returns the editable picklist options.
     */
    @isTest
    static void getFieldOptionsReturnsData() {
        Test.startTest();
        Map<String, List<Map<String, String>>> options = EmployeeRosterController.getFieldOptions();
        Test.stopTest();

        Assert.isFalse(options.get('family').isEmpty(), 'Controller should return coverage-tier options');
    }

    /**
     * @description saveRelationships delegates to the service and applies the edits.
     */
    @isTest
    static void saveRelationshipsDelegates() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Set<Id> acrIds = new Map<Id, AccountContactRelation>(relations).keySet();
        List<EmployeeRosterService.RosterEdit> edits = new List<EmployeeRosterService.RosterEdit>();
        for (AccountContactRelation acr : relations) {
            EmployeeRosterService.RosterEdit edit = new EmployeeRosterService.RosterEdit();
            edit.acrId = acr.Id;
            edit.roles = 'Employee';
            edit.family = 'EO';
            edits.add(edit);
        }

        Test.startTest();
        EmployeeRosterController.saveRelationships(edits);
        Test.stopTest();

        Assert.areEqual(20, [SELECT COUNT() FROM AccountContactRelation WHERE Id IN :acrIds AND Family__c = 'EO'],
            'Controller should persist the coverage tier via the service');
    }

    /**
     * @description saveRelationshipsJson deserializes the JSON payload and applies the edits,
     * matching the object-list path. This is the path the LWC uses.
     */
    @isTest
    static void saveRelationshipsJsonDelegates() {
        List<AccountContactRelation> relations = EmployeeRosterTestData.buildRoster(20);
        Set<Id> acrIds = new Map<Id, AccountContactRelation>(relations).keySet();
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (AccountContactRelation acr : relations) {
            rows.add(new Map<String, Object>{ 'acrId' => acr.Id, 'roles' => 'Employee', 'family' => 'ES' });
        }

        Test.startTest();
        EmployeeRosterController.saveRelationshipsJson(JSON.serialize(rows));
        Test.stopTest();

        Assert.areEqual(20, [SELECT COUNT() FROM AccountContactRelation WHERE Id IN :acrIds AND Family__c = 'ES'],
            'Controller should persist edits supplied as a JSON string');
    }

    /**
     * @description saveRelationshipsJson surfaces a controlled error when the service fails.
     */
    @isTest
    static void saveRelationshipsJsonSurfacesError() {
        EmployeeRosterController.service =
            (EmployeeRosterService) Test.createStub(EmployeeRosterService.class, new ThrowingServiceMock());
        Test.startTest();
        try {
            EmployeeRosterController.saveRelationshipsJson('[{"acrId":null,"roles":"Employee","family":"EO"}]');
            Assert.fail('saveRelationshipsJson should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled save error should be thrown');
        }
        Test.stopTest();
    }

    /**
     * @description Stub that fails every service call to exercise the controller fault paths.
     */
    private class ThrowingServiceMock implements System.StubProvider {
        public Object handleMethodCall(
            Object stubbedObject, String methodName, Type returnType,
            List<Type> paramTypes, List<String> paramNames, List<Object> args
        ) {
            throw new MockServiceException('Simulated service failure');
        }
    }

    /**
     * @description Generic (non-offboard) exception used by the failing service stub.
     */
    private class MockServiceException extends Exception {}
}
