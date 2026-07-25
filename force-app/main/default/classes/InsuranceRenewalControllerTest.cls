/**
 * @description Tests for InsuranceRenewalController — delegation to the service and controlled UI errors.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class InsuranceRenewalControllerTest {

    private static Insurance__c buildActivePolicy(String rtDeveloperName, Integer term) {
        Id providerRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'Insurance_Provider' LIMIT 1
        ].Id;
        Account carrier = new Account(Name = 'Renewal Ctl Carrier', RecordTypeId = providerRt);
        insert carrier;
        Id insRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Insurance__c' AND DeveloperName = :rtDeveloperName LIMIT 1
        ].Id;
        Contact holder = new Contact(LastName = 'Renewal Ctl Holder', Status__c = 'Active');
        insert holder;
        Insurance__c policy = new Insurance__c(
            Name = 'RENCTL-' + rtDeveloperName,
            RecordTypeId = insRt,
            Insurance_Provider__c = carrier.Id,
            Policy_Holder__c = holder.Id,
            Status__c = 'Active',
            Insurance_Start_Date__c = Date.today().addMonths(-12),
            Insurance_Term_months__c = term
        );
        insert policy;
        return policy;
    }

    private static InsuranceRenewalService.RenewalRequest request(Id oldId) {
        InsuranceRenewalService.RenewalRequest req = new InsuranceRenewalService.RenewalRequest();
        req.originalInsuranceId = oldId;
        req.startDate = Date.today();
        req.termMonths = 12;
        return req;
    }

    /**
     * @description getRenewalContext returns the policy context produced by the service.
     */
    @isTest
    static void getRenewalContextReturnsData() {
        Insurance__c policy = buildActivePolicy('Other', 12);

        Test.startTest();
        InsuranceRenewalService.RenewalContext ctx = InsuranceRenewalController.getRenewalContext(policy.Id);
        Test.stopTest();

        Assert.areEqual('Other', ctx.recordTypeDeveloperName, 'Controller returns the resolved record type');
        Assert.areEqual(0, ctx.activeMemberCount, 'A non-group policy has no members');
    }

    /**
     * @description renew delegates to the service and returns the new policy.
     */
    @isTest
    static void renewDelegates() {
        Insurance__c policy = buildActivePolicy('Other', 12);

        Test.startTest();
        InsuranceRenewalService.RenewalResult result = InsuranceRenewalController.renew(request(policy.Id));
        Test.stopTest();

        Assert.isNotNull(result.newInsuranceId, 'Controller returns the new policy id');
        Assert.areEqual('Inactive',
            [SELECT Status__c FROM Insurance__c WHERE Id = :policy.Id].Status__c,
            'The source policy is inactivated');
    }

    /**
     * @description renewJson deserializes the JSON payload and renews (the path the LWC uses).
     */
    @isTest
    static void renewJsonDelegates() {
        Insurance__c policy = buildActivePolicy('Other', 12);

        Test.startTest();
        InsuranceRenewalService.RenewalResult result =
            InsuranceRenewalController.renewJson(JSON.serialize(request(policy.Id)));
        Test.stopTest();

        Assert.isNotNull(result.newInsuranceId, 'Controller renews from a JSON payload');
        Assert.areEqual('Inactive',
            [SELECT Status__c FROM Insurance__c WHERE Id = :policy.Id].Status__c,
            'The source policy is inactivated');
    }

    /**
     * @description renewJson surfaces a controlled error for an unreadable payload.
     */
    @isTest
    static void renewJsonInvalidPayloadThrows() {
        Test.startTest();
        try {
            InsuranceRenewalController.renewJson('not valid json');
            Assert.fail('Expected an AuraHandledException for an unreadable payload');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled error is thrown');
        }
        Test.stopTest();
    }

    /**
     * @description A RenewalException from the service surfaces as a controlled AuraHandledException.
     */
    @isTest
    static void renewInvalidThrowsAuraHandled() {
        Insurance__c policy = buildActivePolicy('Other', 12);
        update new Insurance__c(Id = policy.Id, Status__c = 'Inactive');

        Test.startTest();
        try {
            InsuranceRenewalController.renew(request(policy.Id));
            Assert.fail('Expected an AuraHandledException for an inactive policy');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled UI exception is thrown');
        }
        Test.stopTest();
    }

    /**
     * @description Both controller entry points log and surface a controlled error when the service
     * fails unexpectedly.
     */
    @isTest
    static void controllerSurfacesServiceFailures() {
        InsuranceRenewalService mock = (InsuranceRenewalService) Test.createStub(
            InsuranceRenewalService.class, new ThrowingServiceMock()
        );
        InsuranceRenewalController.service = mock;
        Id fakeId = 'a0m000000000000AAA';

        Test.startTest();
        try {
            InsuranceRenewalController.getRenewalContext(fakeId);
            Assert.fail('getRenewalContext should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled load error is thrown');
        }
        try {
            InsuranceRenewalController.renew(request(fakeId));
            Assert.fail('renew should surface a controlled error');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex, 'A controlled renew error is thrown');
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
     * @description Generic exception used by the failing service stub.
     */
    private class MockServiceException extends Exception {}
}
