/**
 * @description Test class for InsuranceMassEmailListButtonController.
 * Verifies selectedIdsCsv is built from list view selection using existing org data (SeeAllData).
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
@IsTest(SeeAllData=true)
private class InsMassEmailListBtnCtrlTest {

    /**
     * @description Verifies selectedIdsCsv contains the selected Insurance Ids as a comma-separated string.
     */
    @IsTest
    static void testSelectedIdsCsvIsBuiltFromSelectedRecords() {
        List<Insurance__c> insuranceRecords =
            InsuranceMassEmailTestDataFactory.getExistingInsuranceList(2);

        System.assertEquals(2, insuranceRecords.size(), 'Need at least 2 Insurance__c records in sandbox data');

        ApexPages.StandardSetController ssc =
            new ApexPages.StandardSetController(
                [SELECT Id FROM Insurance__c WHERE Id IN :new List<Id>{ insuranceRecords[0].Id, insuranceRecords[1].Id }]
            );

        ssc.setSelected(new List<SObject>{ insuranceRecords[0], insuranceRecords[1] });

        Test.startTest();
        InsuranceMassEmailListButtonController controller =
            new InsuranceMassEmailListButtonController(ssc);
        Test.stopTest();

        System.assertNotEquals(null, controller.selectedIdsCsv);
        System.assert(controller.selectedIdsCsv.contains((String) insuranceRecords[0].Id));
        System.assert(controller.selectedIdsCsv.contains((String) insuranceRecords[1].Id));
        System.assert(controller.selectedIdsCsv.contains(','));
    }

    /**
     * @description Verifies selectedIdsCsv is empty when no rows are selected in the list view.
     */
    @IsTest
    static void testSelectedIdsCsvIsEmptyWhenNothingSelected() {
        ApexPages.StandardSetController ssc =
            new ApexPages.StandardSetController(new List<Insurance__c>());

        Test.startTest();
        InsuranceMassEmailListButtonController controller =
            new InsuranceMassEmailListButtonController(ssc);
        Test.stopTest();

        System.assertEquals('', controller.selectedIdsCsv);
    }
}