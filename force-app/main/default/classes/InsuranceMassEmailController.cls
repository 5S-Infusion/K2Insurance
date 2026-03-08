/**
 * @description Server-side controller for the Insurance Mass Email LWC.
 * Provides init data (recipients and templates), template preview, and enqueue of the mass email job.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
public with sharing class InsuranceMassEmailController {

    /**
     * @description DTO for an email template option in the template dropdown.
     */
    public class TemplateOption {
        @AuraEnabled public Id templateId;
        @AuraEnabled public String label;

        public TemplateOption(Id templateId, String label) {
            this.templateId = templateId;
            this.label = label;
        }
    }

    /**
     * @description DTO for a single recipient row (Insurance + Policy Holder) in the recipients table.
     */
    public class RecipientRow {
        @AuraEnabled public Id insuranceId;
        @AuraEnabled public String insuranceName;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public String status;
    }

    /**
     * @description Response DTO for getInitData: counts and lists of recipients and templates.
     */
    public class InitResponse {
        @AuraEnabled public Integer selectedCount;
        @AuraEnabled public Integer validCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<RecipientRow> recipients;
        @AuraEnabled public List<TemplateOption> templates;
    }

    /**
     * @description Response DTO for getTemplatePreview: template metadata and body for preview.
     */
    public class PreviewResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String subject;
        @AuraEnabled public String htmlBody;
        @AuraEnabled public String plainTextBody;
        @AuraEnabled public String templateName;
    }

    /**
     * @description Loads recipients (from selected Insurance records) and available email templates for the mass email UI.
     * @param insuranceIds List of Insurance__c Ids selected by the user
     * @return InitResponse with selectedCount, validCount, skippedCount, recipients, and templates
     * @throws AuraHandledException when insuranceIds is null or empty
     */
    @AuraEnabled(cacheable=true)
    public static InitResponse getInitData(List<Id> insuranceIds) {
        if (insuranceIds == null || insuranceIds.isEmpty()) {
            throw new AuraHandledException('No Insurance records were selected.');
        }

        List<Insurance__c> insurances = [
            SELECT Id,
                   Name,
                   Policy_Holder__c,
                   Policy_Holder__r.Name,
                   Policy_Holder__r.Email
            FROM Insurance__c
            WHERE Id IN :insuranceIds
            ORDER BY Name
        ];

        InitResponse response = new InitResponse();
        response.selectedCount = insurances.size();
        response.validCount = 0;
        response.skippedCount = 0;
        response.recipients = new List<RecipientRow>();
        response.templates = new List<TemplateOption>();

        for (EmailTemplate templateRecord : [
            SELECT Id, Name
            FROM EmailTemplate
            ORDER BY Name
        ]) {
            response.templates.add(
                new TemplateOption(
                    templateRecord.Id,
                    String.isBlank(templateRecord.Name) ? 'Untitled Template' : templateRecord.Name
                )
            );
        }

        for (Insurance__c insuranceRecord : insurances) {
            RecipientRow row = new RecipientRow();
            row.insuranceId = insuranceRecord.Id;
            row.insuranceName = insuranceRecord.Name;
            row.contactId = insuranceRecord.Policy_Holder__c;
            row.contactName = insuranceRecord.Policy_Holder__r != null
                ? insuranceRecord.Policy_Holder__r.Name
                : null;
            row.contactEmail = insuranceRecord.Policy_Holder__r != null
                ? insuranceRecord.Policy_Holder__r.Email
                : null;

            if (insuranceRecord.Policy_Holder__c == null) {
                row.status = 'Skipped: No Policy Holder';
                response.skippedCount++;
            } else if (String.isBlank(row.contactEmail)) {
                row.status = 'Skipped: No Contact Email';
                response.skippedCount++;
            } else {
                row.status = 'Ready';
                response.validCount++;
            }

            response.recipients.add(row);
        }

        return response;
    }

    /**
     * @description Loads template subject and body for preview (merge fields preserved as-is).
     * @param templateId Id of the EmailTemplate to preview
     * @return PreviewResponse with success, templateName, subject, htmlBody, plainTextBody; message set on error or empty body
     */
    @AuraEnabled(cacheable=true)
    public static PreviewResponse getTemplatePreview(Id templateId) {
        PreviewResponse response = new PreviewResponse();
        response.success = false;
        response.message = null;
        response.subject = null;
        response.htmlBody = null;
        response.plainTextBody = null;
        response.templateName = null;

        if (templateId == null) {
            return response;
        }

        try {
            EmailTemplate templateRecord = [
                SELECT Id, Name, Subject, HtmlValue, Body
                FROM EmailTemplate
                WHERE Id = :templateId
                LIMIT 1
            ];

            response.templateName = templateRecord.Name;
            response.subject = templateRecord.Subject;
            response.htmlBody = templateRecord.HtmlValue;
            response.plainTextBody = templateRecord.Body;
            response.success = true;

            if (String.isBlank(response.htmlBody) && String.isBlank(response.plainTextBody)) {
                response.message = 'Preview is not available for this template body.';
            }

            return response;
        } catch (Exception ex) {
            response.success = false;
            response.message = 'Unable to load template preview. ' + ex.getMessage();
            return response;
        }
    }

    /**
     * @description Enqueues a Queueable job to send one templated email per selected Insurance to its Policy Holder.
     * @param insuranceIds List of Insurance__c Ids to process
     * @param templateId Id of the EmailTemplate to use
     * @param saveAsActivity Whether to save each email as an activity on the related record
     * @return Success message string
     * @throws AuraHandledException when insuranceIds is null/empty or templateId is null
     */
    @AuraEnabled
    public static String enqueueSendEmails(List<Id> insuranceIds, Id templateId, Boolean saveAsActivity) {
        if (insuranceIds == null || insuranceIds.isEmpty()) {
            throw new AuraHandledException('No Insurance records were selected.');
        }
        if (templateId == null) {
            throw new AuraHandledException('Please select an email template.');
        }

        System.enqueueJob(new InsuranceMassEmailQueueable(
            insuranceIds,
            templateId,
            saveAsActivity == null ? true : saveAsActivity
        ));

        return 'Email job submitted successfully.';
    }
}