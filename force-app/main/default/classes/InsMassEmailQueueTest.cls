/**
 * @description Test class for InsuranceMassEmailQueueable.
 * Verifies the queueable completes and sends in batches using existing org data (SeeAllData).
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
@IsTest(SeeAllData=true)
private class InsMassEmailQueueTest {

    /**
     * @description Verifies the queueable job executes successfully and completes when given valid Insurance IDs.
     */
    @IsTest
    static void testQueueableExecutesSuccessfully() {
        Id templateId = InsuranceMassEmailTestDataFactory.getExistingEmailTemplateId();

        List<Insurance__c> insuranceRecords =
            InsuranceMassEmailTestDataFactory.getExistingInsuranceList(3);

        System.assert(insuranceRecords.size() > 0, 'Need Insurance__c records in sandbox data');

        List<Id> insuranceIds = new List<Id>();
        for (Insurance__c row : insuranceRecords) {
            insuranceIds.add(row.Id);
        }

        Test.startTest();
        Id jobId = System.enqueueJob(
            new InsuranceMassEmailQueueable(
                insuranceIds,
                templateId,
                true
            )
        );
        Test.stopTest();

        AsyncApexJob jobRecord = [
            SELECT Id, Status, JobType
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals('Completed', jobRecord.Status);
        System.assertEquals('Queueable', jobRecord.JobType);
    }

    /**
     * @description Verifies the queueable completes without error when given an empty list of Insurance IDs.
     */
    @IsTest
    static void testQueueableHandlesEmptyIds() {
        Id templateId = InsuranceMassEmailTestDataFactory.getExistingEmailTemplateId();

        Test.startTest();
        Id jobId = System.enqueueJob(
            new InsuranceMassEmailQueueable(
                new List<Id>(),
                templateId,
                true
            )
        );
        Test.stopTest();

        AsyncApexJob jobRecord = [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];

        System.assertEquals('Completed', jobRecord.Status);
    }
}