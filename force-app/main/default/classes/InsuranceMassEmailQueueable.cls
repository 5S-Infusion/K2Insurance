/**
 * @description Queueable job that sends one templated email per Insurance record to its Policy Holder (Contact).
 * Sends in batches of 10; skips records without Policy Holder or email.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
public with sharing class InsuranceMassEmailQueueable implements Queueable {

    private final List<Id> insuranceIds;
    private final Id templateId;
    private final Boolean saveAsActivity;

    /**
     * @description Constructs the queueable with the given parameters.
     * @param insuranceIds List of Insurance__c Ids to process
     * @param templateId Id of the EmailTemplate to use
     * @param saveAsActivity Whether to save each email as an activity
     */
    public InsuranceMassEmailQueueable(List<Id> insuranceIds, Id templateId, Boolean saveAsActivity) {
        this.insuranceIds = insuranceIds;
        this.templateId = templateId;
        this.saveAsActivity = saveAsActivity;
    }

    /**
     * @description Sends templated emails to each Insurance record's Policy Holder in batches of 10.
     * @param context QueueableContext provided by the platform
     */
    public void execute(QueueableContext context) {
        if (insuranceIds == null || insuranceIds.isEmpty()) {
            return;
        }

        List<Insurance__c> insurances = [
            SELECT Id,
                   Name,
                   Policy_Holder__c,
                   Policy_Holder__r.Email
            FROM Insurance__c
            WHERE Id IN :insuranceIds
        ];

        List<Messaging.SingleEmailMessage> emailBatch = new List<Messaging.SingleEmailMessage>();

        for (Insurance__c insuranceRecord : insurances) {
            if (insuranceRecord.Policy_Holder__c == null) {
                continue;
            }
            if (insuranceRecord.Policy_Holder__r == null || String.isBlank(insuranceRecord.Policy_Holder__r.Email)) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(insuranceRecord.Policy_Holder__c);
            mail.setWhatId(insuranceRecord.Id);
            mail.setTemplateId(templateId);
            mail.setSaveAsActivity(saveAsActivity);

            emailBatch.add(mail);

            if (emailBatch.size() == 10) {
                Messaging.sendEmail(emailBatch, false);
                emailBatch.clear();
            }
        }

        if (!emailBatch.isEmpty()) {
            Messaging.sendEmail(emailBatch, false);
        }
    }
}