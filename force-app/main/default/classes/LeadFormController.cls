/**
 * @description Controller class for Lead Form LWC component
 * Handles Lead creation and retrieval of picklist values
 * Follows Salesforce best practices: proper error handling, input validation
 * Note: This controller is publicly accessible (without sharing) for guest user access
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-11-29
 */
public without sharing class LeadFormController {
    
    /**
     * @description Wrapper class for Lead form data
     * Ensures type safety and clean data transfer between LWC and Apex
     */
    public class LeadFormData {
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String middleName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public Date birthdate { get; set; }
        @AuraEnabled public String genderIdentity { get; set; }
        @AuraEnabled public String street { get; set; }
        @AuraEnabled public String city { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public String country { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public List<String> interestedInsurance { get; set; }
    }

    /**
     * @description Custom exception for Lead form operations
     */
    public class LeadFormException extends Exception {}

    /**
     * @description Creates a new Lead record from form data
     * @param formDataJson JSON string containing LeadFormData
     * @return Id of the created Lead record
     * @throws AuraHandledException if validation fails or DML errors occur
     */
    @AuraEnabled
    public static Id createLead(String formDataJson) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Parse and validate form data
            LeadFormData formData = parseFormData(formDataJson);
            validateFormData(formData);

            // Build Lead record
            Lead newLead = buildLeadRecord(formData);

            // Insert Lead
            Database.SaveResult result = Database.insert(newLead, false);
            
            if (!result.isSuccess()) {
                String errorMessage = getErrorMessage(result.getErrors());
                throw new LeadFormException(errorMessage);
            }

            return result.getId();

        } catch (LeadFormException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        } catch (JSONException e) {
            Database.rollback(sp);
            throw new AuraHandledException(System.Label.LeadFormCapture_InvalidFormData);
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(System.Label.LeadFormCapture_UnexpectedError + ': ' + e.getMessage());
        }
    }

    /**
     * @description Retrieves Gender Identity picklist values
     * @return List of picklist options with label and value
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getGenderIdentityOptions() {
        try {
            return getPicklistOptions('Lead', 'Gender_Identity__c');
        } catch (Exception e) {
            throw new AuraHandledException(System.Label.LeadFormCapture_GenderOptionsError + ': ' + e.getMessage());
        }
    }

    /**
     * @description Retrieves Interested Insurance picklist values
     * Filters out Auto/Home and Commercial options
     * @return List of picklist options with label and value
     */
    @AuraEnabled
    public static List<PicklistOption> getInterestedInsuranceOptions() {
        try {
            List<PicklistOption> allOptions = getPicklistOptions('Lead', 'Interested_Insurance__c');
            List<PicklistOption> filteredOptions = new List<PicklistOption>();
            
            // Values to exclude from the form
            Set<String> excludedValues = new Set<String>{'Auto/Home', 'Commercial'};
            
            for (PicklistOption option : allOptions) {
                if (!excludedValues.contains(option.value)) {
                    filteredOptions.add(option);
                }
            }
            
            return filteredOptions;
        } catch (Exception e) {
            throw new AuraHandledException(System.Label.LeadFormCapture_InsuranceOptionsError + ': ' + e.getMessage());
        }
    }

    /**
     * @description Generic method to get picklist options for any field
     * @param objectName API name of the object
     * @param fieldName API name of the picklist field
     * @return List of PicklistOption records
     */
    private static List<PicklistOption> getPicklistOptions(String objectName, String fieldName) {
        List<PicklistOption> options = new List<PicklistOption>();
        
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
        if (objType == null) {
            return options;
        }

        Schema.DescribeFieldResult fieldDescribe = objType.getDescribe()
            .fields.getMap().get(fieldName)?.getDescribe();
        
        if (fieldDescribe == null) {
            return options;
        }

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }

        return options;
    }

    /**
     * @description Wrapper class for picklist options
     */
    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * @description Parses JSON string to LeadFormData object
     * @param formDataJson JSON string
     * @return LeadFormData object
     */
    private static LeadFormData parseFormData(String formDataJson) {
        if (String.isBlank(formDataJson)) {
            throw new LeadFormException(System.Label.LeadFormCapture_FormDataRequired);
        }
        return (LeadFormData) JSON.deserialize(formDataJson, LeadFormData.class);
    }

    /**
     * @description Validates required form fields
     * @param formData LeadFormData to validate
     * @throws LeadFormException if validation fails
     */
    private static void validateFormData(LeadFormData formData) {
        List<String> errors = new List<String>();

        if (String.isBlank(formData.firstName)) {
            errors.add(System.Label.LeadFormCapture_FirstNameRequired);
        }

        if (String.isBlank(formData.lastName)) {
            errors.add(System.Label.LeadFormCapture_LastNameRequired);
        }

        if (String.isBlank(formData.genderIdentity)) {
            errors.add(System.Label.LeadFormCapture_GenderIdentityRequired);
        }

        if (String.isBlank(formData.street) && String.isBlank(formData.city)) {
            errors.add(System.Label.LeadFormCapture_AddressRequired);
        }

        if (String.isBlank(formData.email)) {
            errors.add(System.Label.LeadFormCapture_EmailRequired);
        } else if (!isValidEmail(formData.email)) {
            errors.add(System.Label.LeadFormCapture_EmailInvalid);
        }

        if (String.isBlank(formData.phone)) {
            errors.add(System.Label.LeadFormCapture_PhoneRequired);
        }

        if (!errors.isEmpty()) {
            throw new LeadFormException(String.join(errors, ' '));
        }
    }

    /**
     * @description Validates email format using regex
     * @param email Email string to validate
     * @return Boolean indicating if email is valid
     */
    private static Boolean isValidEmail(String email) {
        // More permissive email regex that handles modern TLDs
        String emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher matcher = emailPattern.matcher(email.trim());
        return matcher.matches();
    }

    /**
     * @description Builds Lead record from form data
     * @param formData LeadFormData containing form values
     * @return Lead sObject ready for insert
     */
    private static Lead buildLeadRecord(LeadFormData formData) {
        Lead newLead = new Lead();
        
        // Set name fields
        newLead.FirstName = formData.firstName?.trim();
        newLead.MiddleName = formData.middleName?.trim();
        newLead.LastName = formData.lastName?.trim();
        
        // Set date field
        newLead.Birthdate__c = formData.birthdate;
        
        // Set picklist field
        newLead.Gender_Identity__c = formData.genderIdentity;
        
        // Set address fields
        newLead.Street = formData.street?.trim();
        newLead.City = formData.city?.trim();
        newLead.State = formData.state?.trim();
        newLead.PostalCode = formData.postalCode?.trim();
        newLead.Country = formData.country?.trim();
        
        // Set contact fields
        newLead.Email = formData.email?.trim();
        newLead.Phone = formData.phone?.trim();
        
        // Set multi-select picklist (semicolon-separated)
        if (formData.interestedInsurance != null && !formData.interestedInsurance.isEmpty()) {
            newLead.Interested_Insurance__c = String.join(formData.interestedInsurance, ';');
        }
        
        // Set default values        
        newLead.Company = '[Not Provided]';
        newLead.Status = 'New';
        newLead.LeadSource = 'Web';

        return newLead;
    }

    /**
     * @description Extracts error messages from Database errors
     * @param errors List of Database.Error objects
     * @return Concatenated error message string
     */
    private static String getErrorMessage(List<Database.Error> errors) {
        List<String> errorMessages = new List<String>();
        for (Database.Error err : errors) {
            errorMessages.add(err.getMessage());
        }
        return String.join(errorMessages, ' ');
    }
}