/**
 * @description Test class for LeadFormController
 * Provides comprehensive test coverage for Lead form operations
 * Note: Controller is publicly accessible (without sharing) for guest user access
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class LeadFormControllerTest {
    
    /**
     * @description Test successful Lead creation with all required fields
     */
    @isTest
    static void testCreateLeadSuccess() {
        // Prepare test data
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'John',
            'middleName' => 'Michael',
            'lastName' => 'Doe',
            'birthdate' => Date.today().addYears(-30),
            'genderIdentity' => 'Male',
            'street' => '123 Main Street',
            'city' => 'Los Angeles',
            'state' => 'CA',
            'postalCode' => '90001',
            'country' => 'USA',
            'email' => 'john.doe@example.com',
            'phone' => '+12025551234',
            'interestedInsurance' => 'Health'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Id leadId = LeadFormController.createLead(formDataJson);
        Test.stopTest();

        // Verify Lead was created
        System.assertNotEquals(null, leadId, 'Lead ID should not be null');
        
        Lead createdLead = [
            SELECT Id, FirstName, MiddleName, LastName, Birthdate__c, Gender_Identity__c,
                   Street, City, State, PostalCode, Country, Email, Phone,
                   Interested_Insurance__c, Company, Status, LeadSource
            FROM Lead 
            WHERE Id = :leadId
        ];
        
        System.assertEquals('John', createdLead.FirstName, 'FirstName should match');
        System.assertEquals('Michael', createdLead.MiddleName, 'MiddleName should match');
        System.assertEquals('Doe', createdLead.LastName, 'LastName should match');
        System.assertEquals('Male', createdLead.Gender_Identity__c, 'Gender Identity should match');
        System.assertEquals('123 Main Street', createdLead.Street, 'Street should match');
        System.assertEquals('john.doe@example.com', createdLead.Email, 'Email should match');
        System.assertEquals('+12025551234', createdLead.Phone, 'Phone should match');
        System.assertEquals('Health', createdLead.Interested_Insurance__c, 'Interested Insurance should hold the single choice');
        System.assertEquals('[Not Provided]', createdLead.Company, 'Company should be default value');
        System.assertEquals('New', createdLead.Status, 'Status should be New');
        System.assertEquals('Web', createdLead.LeadSource, 'LeadSource should be Web');
    }

    /**
     * @description Test Lead creation with minimum required fields
     */
    @isTest
    static void testCreateLeadMinimumFields() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'Jane',
            'lastName' => 'Smith',
            'genderIdentity' => 'Female',
            'street' => '456 Oak Ave',
            'city' => 'New York',
            'email' => 'jane.smith@example.com',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Id leadId = LeadFormController.createLead(formDataJson);
        Test.stopTest();

        System.assertNotEquals(null, leadId, 'Lead should be created with minimum fields');
    }

    /**
     * @description Test Lead creation fails with missing first name
     */
    @isTest
    static void testCreateLeadMissingFirstName() {
        Map<String, Object> formData = new Map<String, Object>{
            'lastName' => 'Doe',
            'genderIdentity' => 'Male',
            'street' => '123 Main St',
            'city' => 'Los Angeles',
            'email' => 'test@example.com',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead(formDataJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // Verify exception contains the label value
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_FirstNameRequired) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for missing first name');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with missing last name
     */
    @isTest
    static void testCreateLeadMissingLastName() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'John',
            'genderIdentity' => 'Male',
            'street' => '123 Main St',
            'city' => 'Los Angeles',
            'email' => 'test@example.com',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead(formDataJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_LastNameRequired) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for missing last name');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with missing email
     */
    @isTest
    static void testCreateLeadMissingEmail() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'Test',
            'lastName' => 'User',
            'genderIdentity' => 'Male',
            'street' => '123 Main St',
            'city' => 'Los Angeles',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead(formDataJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_EmailRequired) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for missing email');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with invalid email format
     */
    @isTest
    static void testCreateLeadInvalidEmail() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'Test',
            'lastName' => 'User',
            'genderIdentity' => 'Male',
            'street' => '123 Main St',
            'city' => 'Los Angeles',
            'email' => 'invalid-email',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead(formDataJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_EmailInvalid) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for invalid email');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with missing gender identity
     */
    @isTest
    static void testCreateLeadMissingGenderIdentity() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'Test',
            'lastName' => 'User',
            'street' => '123 Main St',
            'city' => 'Los Angeles',
            'email' => 'test@example.com',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead(formDataJson);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_GenderIdentityRequired) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for missing gender identity');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with empty form data
     */
    @isTest
    static void testCreateLeadEmptyFormData() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_FormDataRequired) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for empty form data');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with null form data
     */
    @isTest
    static void testCreateLeadNullFormData() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_FormDataRequired) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for null form data');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test Lead creation fails with invalid JSON
     */
    @isTest
    static void testCreateLeadInvalidJson() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            LeadFormController.createLead('invalid json{');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains(System.Label.LeadFormCapture_InvalidFormData) || 
                         e.getMessage().contains('Script-thrown exception'), 
                'Exception should be thrown for invalid JSON');
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should have thrown an exception');
    }

    /**
     * @description Test getGenderIdentityOptions returns valid options
     */
    @isTest
    static void testGetGenderIdentityOptions() {
        Test.startTest();
        List<LeadFormController.PicklistOption> options = LeadFormController.getGenderIdentityOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options should not be null');
        System.assert(options.size() > 0, 'Should return at least one option');
        
        // Verify each option has label and value
        for (LeadFormController.PicklistOption opt : options) {
            System.assertNotEquals(null, opt.label, 'Label should not be null');
            System.assertNotEquals(null, opt.value, 'Value should not be null');
        }
    }

    /**
     * @description Test getInterestedInsuranceOptions returns valid options
     */
    @isTest
    static void testGetInterestedInsuranceOptions() {
        Test.startTest();
        List<LeadFormController.PicklistOption> options = LeadFormController.getInterestedInsuranceOptions();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options should not be null');
        System.assert(options.size() > 0, 'Should return at least one option');
        
        // Verify each option has label and value
        for (LeadFormController.PicklistOption opt : options) {
            System.assertNotEquals(null, opt.label, 'Label should not be null');
            System.assertNotEquals(null, opt.value, 'Value should not be null');
        }
    }

    /**
     * @description Test Lead creation without middle name (optional field)
     */
    @isTest
    static void testCreateLeadWithoutMiddleName() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => 'John',
            'lastName' => 'Doe',
            'genderIdentity' => 'Male',
            'street' => '123 Main St',
            'city' => 'Los Angeles',
            'email' => 'john@example.com',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Id leadId = LeadFormController.createLead(formDataJson);
        Test.stopTest();

        Lead createdLead = [SELECT FirstName, MiddleName, LastName FROM Lead WHERE Id = :leadId];
        System.assertEquals('John', createdLead.FirstName, 'FirstName should be set');
        System.assertEquals(null, createdLead.MiddleName, 'MiddleName should be null');
        System.assertEquals('Doe', createdLead.LastName, 'LastName should be set');
    }

    /**
     * @description Test Lead creation with whitespace in fields (should be trimmed)
     */
    @isTest
    static void testCreateLeadTrimsWhitespace() {
        Map<String, Object> formData = new Map<String, Object>{
            'firstName' => '  John  ',
            'middleName' => '  Michael  ',
            'lastName' => '  Doe  ',
            'genderIdentity' => 'Male',
            'street' => '  123 Main St  ',
            'city' => '  Los Angeles  ',
            'email' => 'john@example.com',
            'phone' => '5551234567'
        };
        String formDataJson = JSON.serialize(formData);

        Test.startTest();
        Id leadId = LeadFormController.createLead(formDataJson);
        Test.stopTest();

        Lead createdLead = [SELECT FirstName, MiddleName, LastName, Street, Email FROM Lead WHERE Id = :leadId];
        System.assertEquals('John', createdLead.FirstName, 'FirstName should be trimmed');
        System.assertEquals('Michael', createdLead.MiddleName, 'MiddleName should be trimmed');
        System.assertEquals('Doe', createdLead.LastName, 'LastName should be trimmed');
        System.assertEquals('123 Main St', createdLead.Street, 'Street should be trimmed');
        System.assertEquals('john@example.com', createdLead.Email, 'Email should be trimmed');
    }

    /**
     * @description Each insurance choice must land on the right Lead record type.
     *              Group Health and Commercial deliberately share one record type.
     */
    @isTest
    static void testRecordTypeMappingPerInsuranceChoice() {
        Map<String, String> expectedByChoice = new Map<String, String>{
            'Medicare' => 'Medicare',
            'Health' => 'Health',
            'Group Health' => 'Commercial_Group_Health',
            'Commercial' => 'Commercial_Group_Health',
            'Auto/Home' => 'Others',
            'Life' => 'Others',
            'Other' => 'Others'
        };

        Map<Id, String> devNameByRecordTypeId = new Map<Id, String>();
        for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Lead']) {
            devNameByRecordTypeId.put(rt.Id, rt.DeveloperName);
        }

        Test.startTest();
        for (String choice : expectedByChoice.keySet()) {
            Id leadId = LeadFormController.createLead(JSON.serialize(baseFormData(choice)));
            Lead created = [SELECT RecordTypeId, Interested_Insurance__c FROM Lead WHERE Id = :leadId];

            System.assertEquals(choice, created.Interested_Insurance__c,
                'Stored interest should match the submitted choice for ' + choice);
            System.assertEquals(expectedByChoice.get(choice), devNameByRecordTypeId.get(created.RecordTypeId),
                'Unexpected record type for ' + choice);
        }
        Test.stopTest();
    }

    /**
     * @description A Health submission with household members creates one Lead per person,
     *              all linked back to the submitter, with shared details copied down.
     */
    @isTest
    static void testCreateLeadWithFamilyMembers() {
        Map<String, Object> formData = baseFormData('Health');
        formData.put('familyMembers', new List<Map<String, Object>>{
            new Map<String, Object>{
                'relationship' => 'Spouse', 'firstName' => 'Jane', 'lastName' => 'Doe',
                'birthdate' => Date.today().addYears(-28), 'email' => 'jane@example.com', 'phone' => null
            },
            new Map<String, Object>{
                'relationship' => 'Son', 'firstName' => 'Sam', 'lastName' => 'Doe',
                'birthdate' => Date.today().addYears(-8), 'email' => null, 'phone' => null
            }
        });

        Test.startTest();
        Id primaryId = LeadFormController.createLead(JSON.serialize(formData));
        Test.stopTest();

        Lead primary = [SELECT Is_Primaryholder__c, Primaryholder__c, Street, Email FROM Lead WHERE Id = :primaryId];
        System.assertEquals(true, primary.Is_Primaryholder__c, 'Submitter should be the primary holder');
        System.assertEquals(null, primary.Primaryholder__c, 'Primary holder must not point at anyone');

        List<Lead> members = [
            SELECT FirstName, LastName, Familial_Relationship__c, Primaryholder__c,
                   Is_Primaryholder__c, Street, Email, Phone, Interested_Insurance__c
            FROM Lead WHERE Primaryholder__c = :primaryId ORDER BY FirstName
        ];
        System.assertEquals(2, members.size(), 'One Lead per household member');

        for (Lead member : members) {
            System.assertEquals(false, member.Is_Primaryholder__c, 'Members are not primary holders');
            System.assertEquals(primary.Street, member.Street, 'Address is inherited, not retyped');
            System.assertEquals('Health', member.Interested_Insurance__c, 'Insurance interest is inherited');
        }

        System.assertEquals('Spouse', members[0].Familial_Relationship__c, 'Jane is the spouse');
        System.assertEquals('jane@example.com', members[0].Email, 'Member keeps their own email');
        System.assertEquals(primary.Email, members[1].Email, 'Blank member email falls back to the submitter');
    }

    /**
     * @description Household capture is limited to Health and Medicare; members submitted
     *              alongside any other line of business are ignored.
     */
    @isTest
    static void testFamilyMembersIgnoredForNonHealthLines() {
        Map<String, Object> formData = baseFormData('Auto/Home');
        formData.put('familyMembers', new List<Map<String, Object>>{
            new Map<String, Object>{ 'relationship' => 'Spouse', 'firstName' => 'Jane',
                                     'lastName' => 'Doe', 'birthdate' => Date.today().addYears(-30) }
        });

        Test.startTest();
        Id primaryId = LeadFormController.createLead(JSON.serialize(formData));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Primaryholder__c = :primaryId],
            'Household members should not be created for Auto/Home');
        System.assertEquals(false, [SELECT Is_Primaryholder__c FROM Lead WHERE Id = :primaryId].Is_Primaryholder__c,
            'Without household members the submitter is not flagged as primary holder');
    }

    /**
     * @description A fully blank row is ignored, but a half-filled one is rejected rather than
     *              creating a Lead the agent cannot follow up on.
     */
    @isTest
    static void testIncompleteFamilyMemberIsRejected() {
        Map<String, Object> blankRowData = baseFormData('Medicare');
        blankRowData.put('familyMembers', new List<Map<String, Object>>{
            new Map<String, Object>{ 'relationship' => null, 'firstName' => '', 'lastName' => '' },
            new Map<String, Object>{ 'relationship' => 'Daughter', 'firstName' => 'Amy',
                                     'lastName' => 'Doe', 'birthdate' => Date.today().addYears(-10) }
        });

        Map<String, Object> partialRowData = baseFormData('Medicare');
        partialRowData.put('email', 'partial@example.com');
        partialRowData.put('familyMembers', new List<Map<String, Object>>{
            new Map<String, Object>{ 'relationship' => 'Son', 'firstName' => 'Max', 'lastName' => 'Doe' }
        });

        Test.startTest();
        Id primaryId = LeadFormController.createLead(JSON.serialize(blankRowData));

        Boolean rejected = false;
        try {
            LeadFormController.createLead(JSON.serialize(partialRowData));
        } catch (AuraHandledException e) {
            rejected = true;
        }
        Test.stopTest();

        List<Lead> members = [SELECT FirstName FROM Lead WHERE Primaryholder__c = :primaryId];
        System.assertEquals(1, members.size(), 'The blank row is ignored, the complete one is created');
        System.assertEquals('Amy', members[0].FirstName, 'The completed member is the one created');
        System.assertEquals(true, rejected, 'A member missing a date of birth must be rejected');
    }

    /**
     * @description Builds a valid submission for the given insurance choice.
     * @param insuranceChoice Value for Interested Insurance.
     * @return Form data map ready to serialize.
     */
    private static Map<String, Object> baseFormData(String insuranceChoice) {
        return new Map<String, Object>{
            'firstName' => 'John',
            'lastName' => 'Doe',
            'birthdate' => Date.today().addYears(-40),
            'genderIdentity' => 'Male',
            'street' => '123 Main Street',
            'city' => 'Los Angeles',
            'state' => 'CA',
            'postalCode' => '90001',
            'country' => 'USA',
            'email' => 'john.doe@example.com',
            'phone' => '+12025551234',
            'interestedInsurance' => insuranceChoice
        };
    }
}
