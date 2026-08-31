/**
 * @description Controller for the Lead Form LWC — creates Leads from public form submissions and
 * serves picklist values. Declared `without sharing` intentionally so Experience Cloud guest users
 * can create Leads regardless of record-sharing context.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public without sharing class LeadFormController {

    // Cache lead record type lookups to avoid repeated describe calls.
    private static Map<String, Id> leadRecordTypeCache = new Map<String, Id>();

    /**
     * @description Wrapper for Lead form data; provides type-safe transfer between LWC and Apex.
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
        @AuraEnabled public String interestedInsurance { get; set; }
        @AuraEnabled public List<FamilyMemberData> familyMembers { get; set; }
    }

    /**
     * @description One additional household member captured on the same form submission.
     *              Each becomes its own Lead, linked back to the submitter as Primaryholder.
     */
    public class FamilyMemberData {
        @AuraEnabled public String relationship { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public Date birthdate { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
    }

    /**
     * @description Custom exception for Lead form validation failures.
     */
    public class LeadFormException extends Exception {}

    /**
     * @description Creates a new Lead record from form data.
     * @param formDataJson JSON string containing LeadFormData.
     * @return Id of the created Lead record.
     */
    @AuraEnabled
    public static Id createLead(String formDataJson) {
        Savepoint sp = Database.setSavepoint();

        try {
            // Parse and validate form data.
            LeadFormData formData = parseFormData(formDataJson);
            validateFormData(formData);

            List<FamilyMemberData> members = getEligibleFamilyMembers(formData);
            Boolean hasFamily = !members.isEmpty();

            // Build the submitter's Lead. When family members came in on the same form the
            // submitter becomes the household's primary holder.
            Lead primaryLead = buildLeadRecord(formData);
            primaryLead.Is_Primaryholder__c = hasFamily;

            Database.SaveResult primaryResult = Database.insert(primaryLead, false);
            if (!primaryResult.isSuccess()) {
                throw new LeadFormException(getErrorMessage(primaryResult.getErrors()));
            }

            Id primaryLeadId = primaryResult.getId();

            if (hasFamily) {
                List<Lead> memberLeads = new List<Lead>();
                for (FamilyMemberData member : members) {
                    memberLeads.add(buildFamilyMemberLead(member, formData, primaryLeadId));
                }

                List<Database.SaveResult> memberResults = Database.insert(memberLeads, false);
                for (Database.SaveResult memberResult : memberResults) {
                    if (!memberResult.isSuccess()) {
                        throw new LeadFormException(getErrorMessage(memberResult.getErrors()));
                    }
                }
            }

            return primaryLeadId;

        } catch (LeadFormException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        } catch (JSONException e) {
            Database.rollback(sp);
            throw new AuraHandledException(System.Label.LeadFormCapture_InvalidFormData);
        } catch (Exception e) {
            Database.rollback(sp);
            ExceptionLogger.log('LeadFormController.createLead', null, e);
            throw new AuraHandledException(System.Label.LeadFormCapture_UnexpectedError);
        }
    }

    /**
     * @description Returns the household members to create Leads for. Family capture only applies
     *              to Health and Medicare - other lines either do not need household data or are
     *              collected directly from the employer. Every submitted member must be complete,
     *              because each one becomes a Lead an agent has to be able to act on.
     * @param formData The submitted form data.
     * @return Household members, or an empty list when the line of business does not collect them.
     */
    private static List<FamilyMemberData> getEligibleFamilyMembers(LeadFormData formData) {
        List<FamilyMemberData> members = new List<FamilyMemberData>();

        if (formData.familyMembers == null || !supportsFamilyCapture(formData.interestedInsurance)) {
            return members;
        }

        for (FamilyMemberData member : formData.familyMembers) {
            if (member == null) {
                continue;
            }

            Boolean isBlankRow = String.isBlank(member.relationship)
                && String.isBlank(member.firstName)
                && String.isBlank(member.lastName)
                && member.birthdate == null
                && String.isBlank(member.email)
                && String.isBlank(member.phone);

            if (isBlankRow) {
                continue;
            }

            if (String.isBlank(member.relationship) || String.isBlank(member.firstName)
                || String.isBlank(member.lastName) || member.birthdate == null) {
                throw new LeadFormException(
                    'Each family member needs a relationship, date of birth, first name and last name.');
            }

            members.add(member);
        }

        return members;
    }

    /**
     * @description Whether the chosen insurance line collects household members.
     * @param interestedInsurance The value chosen on the form.
     * @return True for Health and Medicare.
     */
    @TestVisible
    private static Boolean supportsFamilyCapture(String interestedInsurance) {
        if (String.isBlank(interestedInsurance)) {
            return false;
        }
        String choice = interestedInsurance.trim();
        return choice.equalsIgnoreCase('Health') || choice.equalsIgnoreCase('Medicare');
    }

    /**
     * @description Builds a household member Lead. Shared details (address, insurance interest,
     *              record type) are inherited from the submitter so the customer only types them
     *              once; contact details fall back to the submitter's when left blank.
     * @param member The household member captured on the form.
     * @param formData The submitter's form data.
     * @param primaryLeadId Id of the submitter's Lead.
     * @return Lead sObject ready for insert.
     */
    private static Lead buildFamilyMemberLead(FamilyMemberData member, LeadFormData formData, Id primaryLeadId) {
        Lead memberLead = buildLeadRecord(formData);

        memberLead.FirstName = member.firstName?.trim();
        memberLead.MiddleName = null;
        memberLead.LastName = member.lastName?.trim();
        memberLead.Birthdate__c = member.birthdate;

        // Gender is not collected per household member on the form.
        memberLead.Gender_Identity__c = null;

        memberLead.Email = String.isNotBlank(member.email) ? member.email.trim() : formData.email?.trim();
        memberLead.Phone = String.isNotBlank(member.phone) ? member.phone.trim() : formData.phone?.trim();

        // Household linkage. Is_Primaryholder__c stays false so the Primaryholder lookup filter
        // on Lead accepts the reference.
        memberLead.Is_Primaryholder__c = false;
        memberLead.Primaryholder__c = primaryLeadId;
        memberLead.Familial_Relationship__c = member.relationship;

        return memberLead;
    }

    /**
     * @description Retrieves Gender Identity picklist values.
     * @return List of picklist options with label and value.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getGenderIdentityOptions() {
        try {
            return getPicklistOptions('Lead', 'Gender_Identity__c');
        } catch (Exception e) {
            ExceptionLogger.log('LeadFormController.getGenderIdentityOptions', null, e);
            throw new AuraHandledException(System.Label.LeadFormCapture_GenderOptionsError);
        }
    }

    /**
     * @description Retrieves all active Interested Insurance picklist values for the form.
     * @return List of picklist options with label and value.
     */
    @AuraEnabled
    public static List<PicklistOption> getInterestedInsuranceOptions() {
        try {
            return getPicklistOptions('Lead', 'Interested_Insurance__c');
        } catch (Exception e) {
            ExceptionLogger.log('LeadFormController.getInterestedInsuranceOptions', null, e);
            return new List<PicklistOption>();
        }
    }

    /**
     * @description Returns the active picklist options for a field.
     * @param objectName API name of the object.
     * @param fieldName API name of the picklist field.
     * @return List of PicklistOption records.
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
     * @description Wrapper for a picklist option (label/value pair).
     */
    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        /**
         * @description Constructs a picklist option.
         * @param label Display label.
         * @param value Stored value.
         */
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * @description Parses the JSON payload into a LeadFormData object.
     * @param formDataJson JSON string.
     * @return LeadFormData object.
     */
    private static LeadFormData parseFormData(String formDataJson) {
        if (String.isBlank(formDataJson)) {
            throw new LeadFormException(System.Label.LeadFormCapture_FormDataRequired);
        }
        return (LeadFormData) JSON.deserialize(formDataJson, LeadFormData.class);
    }

    /**
     * @description Validates required form fields, throwing on the first set of failures.
     * @param formData LeadFormData to validate.
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
     * @description Validates email format using a permissive regex.
     * @param email Email string to validate.
     * @return True when the email is well-formed.
     */
    private static Boolean isValidEmail(String email) {
        // Permissive email regex that handles modern TLDs.
        String emailRegex = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher matcher = emailPattern.matcher(email.trim());
        return matcher.matches();
    }

    /**
     * @description Builds a Lead sObject from validated form data.
     * @param formData LeadFormData containing form values.
     * @return Lead sObject ready for insert.
     */
    private static Lead buildLeadRecord(LeadFormData formData) {
        Lead newLead = new Lead();

        // Name fields.
        newLead.FirstName = formData.firstName?.trim();
        newLead.MiddleName = formData.middleName?.trim();
        newLead.LastName = formData.lastName?.trim();

        // Date field.
        newLead.Birthdate__c = formData.birthdate;

        // Picklist field.
        newLead.Gender_Identity__c = formData.genderIdentity;

        // Address fields.
        newLead.Street = formData.street?.trim();
        newLead.City = formData.city?.trim();
        newLead.State = formData.state?.trim();
        newLead.PostalCode = formData.postalCode?.trim();
        newLead.Country = formData.country?.trim();

        // Contact fields.
        newLead.Email = formData.email?.trim();
        newLead.Phone = formData.phone?.trim();

        // Interested Insurance is captured as a single choice on the form. The field itself is
        // still a multi-select picklist, so a lone value is stored without a separator.
        if (String.isNotBlank(formData.interestedInsurance)) {
            newLead.Interested_Insurance__c = formData.interestedInsurance.trim();
        }

        Id resolvedRecordTypeId = resolveLeadRecordTypeId(formData.interestedInsurance);
        if (resolvedRecordTypeId != null) {
            newLead.RecordTypeId = resolvedRecordTypeId;
        }

        // Default values.
        newLead.Company = '[Not Provided]';
        newLead.Status = 'New';
        newLead.LeadSource = 'Web';

        return newLead;
    }

    /**
     * @description Concatenates messages from a list of Database errors.
     * @param errors List of Database.Error objects.
     * @return Concatenated error message string.
     */
    private static String getErrorMessage(List<Database.Error> errors) {
        List<String> errorMessages = new List<String>();
        for (Database.Error err : errors) {
            errorMessages.add(err.getMessage());
        }
        return String.join(errorMessages, ' ');
    }


    /**
     * @description Maps the single Interested Insurance choice onto a Lead record type.
     *              Group Health and Commercial share one record type because both arrive with
     *              company information attached; everything else falls back to Others.
     * @param interestedInsurance The value chosen on the form.
     * @return Record type Id, or null when it cannot be resolved.
     */
    private static Id resolveLeadRecordTypeId(String interestedInsurance) {
        if (String.isBlank(interestedInsurance)) {
            return getLeadRecordTypeId('Others');
        }

        String choice = interestedInsurance.trim();

        if (choice.equalsIgnoreCase('Medicare')) {
            return getLeadRecordTypeId('Medicare');
        }
        if (choice.equalsIgnoreCase('Health')) {
            return getLeadRecordTypeId('Health');
        }
        if (choice.equalsIgnoreCase('Group Health') || choice.equalsIgnoreCase('Commercial')) {
            return getLeadRecordTypeId('Commercial_Group_Health');
        }

        return getLeadRecordTypeId('Others');
    }

    /**
     * @description Resolves a Lead record type Id by name or developer name, with caching.
     * @param recordTypeName Record type name or developer name.
     * @return Record type Id, or null when not found.
     */
    private static Id getLeadRecordTypeId(String recordTypeName) {
        if (String.isBlank(recordTypeName)) {
            return null;
        }

        if (leadRecordTypeCache.containsKey(recordTypeName)) {
            return leadRecordTypeCache.get(recordTypeName);
        }

        Schema.DescribeSObjectResult leadDescribe = Lead.SObjectType.getDescribe();
        Map<String, Schema.RecordTypeInfo> byName = leadDescribe.getRecordTypeInfosByName();
        Map<String, Schema.RecordTypeInfo> byDeveloperName = leadDescribe.getRecordTypeInfosByDeveloperName();

        Schema.RecordTypeInfo info = null;
        if (byName != null && byName.containsKey(recordTypeName)) {
            info = byName.get(recordTypeName);
        } else if (byDeveloperName != null && byDeveloperName.containsKey(recordTypeName)) {
            info = byDeveloperName.get(recordTypeName);
        }

        Id recordTypeId = info == null ? null : info.getRecordTypeId();
        leadRecordTypeCache.put(recordTypeName, recordTypeId);
        return recordTypeId;
    }
}
