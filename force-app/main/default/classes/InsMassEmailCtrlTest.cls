/**
 * @description Test class for InsuranceMassEmailController.
 * Exercises getInitData, getTemplatePreview, and enqueueSendEmails using existing
 * org data (Insurance__c, Contact, EmailTemplate) via InsuranceMassEmailTestDataFactory.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
@IsTest(SeeAllData=true)
private class InsMassEmailCtrlTest {

    /**
     * @description Verifies getInitData returns selected count, recipient rows, and template list
     * when given a list of Insurance IDs from existing data.
     */
    @IsTest
    static void testGetInitData() {
        List<Insurance__c> insuranceRecords =
            InsuranceMassEmailTestDataFactory.getExistingInsuranceList(3);

        System.assert(insuranceRecords.size() > 0, 'Need at least 1 Insurance__c record in sandbox data');

        List<Id> insuranceIds = new List<Id>();
        for (Insurance__c row : insuranceRecords) {
            insuranceIds.add(row.Id);
        }

        Test.startTest();
        InsuranceMassEmailController.InitResponse response =
            InsuranceMassEmailController.getInitData(insuranceIds);
        Test.stopTest();

        System.assertNotEquals(null, response);
        System.assertEquals(insuranceRecords.size(), response.selectedCount);
        System.assertEquals(insuranceRecords.size(), response.recipients.size());
        System.assert(response.templates.size() > 0, 'Expected at least one email template');
    }

    /**
     * @description Verifies getTemplatePreview returns success and template name when given a valid template Id.
     */
    @IsTest
    static void testGetTemplatePreview() {
        Id templateId = InsuranceMassEmailTestDataFactory.getExistingEmailTemplateId();

        Test.startTest();
        InsuranceMassEmailController.PreviewResponse response =
            InsuranceMassEmailController.getTemplatePreview(templateId);
        Test.stopTest();

        System.assertEquals(true, response.success);
        System.assertNotEquals(null, response.templateName);
    }

    /**
     * @description Verifies getTemplatePreview returns success=false and null subject/body when templateId is null.
     */
    @IsTest
    static void testGetTemplatePreviewWhenTemplateIdIsNull() {
        Test.startTest();
        InsuranceMassEmailController.PreviewResponse response =
            InsuranceMassEmailController.getTemplatePreview(null);
        Test.stopTest();

        System.assertEquals(false, response.success);
        System.assertEquals(null, response.subject);
        System.assertEquals(null, response.plainTextBody);
    }

    /**
     * @description Verifies enqueueSendEmails submits the job and returns the success message
     * when given valid Insurance IDs and template Id.
     */
    @IsTest
    static void testEnqueueSendEmails() {
        Id templateId = InsuranceMassEmailTestDataFactory.getExistingEmailTemplateId();
        Insurance__c insuranceRecord = InsuranceMassEmailTestDataFactory.getExistingInsuranceWithEmail();

        System.assertNotEquals(null, insuranceRecord, 'Need one Insurance__c record with Policy Holder email');

        Test.startTest();
        String resultMessage = InsuranceMassEmailController.enqueueSendEmails(
            new List<Id>{ insuranceRecord.Id },
            templateId,
            true
        );
        Test.stopTest();

        System.assertEquals('Email job submitted successfully.', resultMessage);
    }

    /**
     * @description Verifies enqueueSendEmails throws when templateId is null.
     */
    @IsTest
    static void testEnqueueSendEmailsThrowsWhenNoTemplate() {
        Insurance__c insuranceRecord = InsuranceMassEmailTestDataFactory.getExistingInsuranceWithEmail();

        System.assertNotEquals(null, insuranceRecord, 'Need one Insurance__c record with Policy Holder email');

        Boolean didThrow = false;

        try {
            Test.startTest();
            InsuranceMassEmailController.enqueueSendEmails(
                new List<Id>{ insuranceRecord.Id },
                null,
                true
            );
            Test.stopTest();
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow);
    }

    /**
     * @description Verifies getInitData throws when an empty list of Insurance IDs is passed.
     */
    @IsTest
    static void testGetInitDataThrowsWhenNoIdsPassed() {
        Boolean didThrow = false;

        try {
            Test.startTest();
            InsuranceMassEmailController.getInitData(new List<Id>());
            Test.stopTest();
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow);
    }
}