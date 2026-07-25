/**
 * @description Core renewal engine for Insurance policies of any record type. Clones the expiring
 * policy into a new active term (inheriting every field, including record-type-specific coverage
 * fields), applies the caller's overrides (dates, term, provider, premium, ...), carries the
 * expiring policy's active coverage junctions (ContactInsuranceAssociation) onto the new term, and
 * marks the old policy and its coverage inactive. Caller-agnostic and bulk-safe (accepts a List)
 * so the renewal LWC controller today, and a scheduled job later, can share one implementation.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class InsuranceRenewalService {

    private static final String STATUS_ACTIVE = 'Active';
    private static final String STATUS_INACTIVE = 'Inactive';

    /**
     * @description Raised when a renewal request is missing its source policy or that policy no
     * longer exists / is not renewable.
     */
    public class RenewalException extends Exception {}

    /**
     * @description One renewal request. Only non-null overrides are applied; date and term are
     * always taken from the request (term may be intentionally null, e.g. whole life). Fields are
     * `@AuraEnabled` so the renewal LWC can pass them; the Service stays caller-agnostic.
     */
    public class RenewalRequest {
        @AuraEnabled public Id originalInsuranceId;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Integer termMonths;
        @AuraEnabled public Id providerId;
        @AuraEnabled public Decimal premium;
        @AuraEnabled public Decimal deductible;
        @AuraEnabled public String policyName;
        @AuraEnabled public Boolean carryMembers;
        @AuraEnabled public Decimal buildingCoverageLimit;
        @AuraEnabled public Decimal businessPersonalProperty;
        @AuraEnabled public String onOffMarket;
        @AuraEnabled public String policyType;
    }

    /**
     * @description Result of a renewal: the new policy and how many members were carried over.
     */
    public class RenewalResult {
        @AuraEnabled public Id newInsuranceId;
        @AuraEnabled public Integer membersCarried;
    }

    /**
     * @description The current policy's values and sensible new-term defaults, used to render the
     * renewal form. Read-only; carries no logic.
     */
    public class RenewalContext {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public Date currentStartDate;
        @AuraEnabled public Date currentEndDate;
        @AuraEnabled public Integer currentTermMonths;
        @AuraEnabled public Date suggestedStartDate;
        @AuraEnabled public Id providerId;
        @AuraEnabled public String providerName;
        @AuraEnabled public Decimal premium;
        @AuraEnabled public Decimal deductible;
        @AuraEnabled public String policyNumber;
        @AuraEnabled public String companyName;
        @AuraEnabled public Decimal buildingCoverageLimit;
        @AuraEnabled public Decimal businessPersonalProperty;
        @AuraEnabled public String onOffMarket;
        @AuraEnabled public String policyType;
        @AuraEnabled public Integer activeMemberCount;
    }

    /**
     * @description Loads the current policy's values and new-term defaults for the renewal form.
     * @param insuranceId The policy being renewed.
     * @return The renewal context for that policy.
     */
    public RenewalContext getContext(Id insuranceId) {
        Insurance__c ins = [
            SELECT Id, Name, RecordType.DeveloperName, RecordType.Name,
                   Insurance_Start_Date__c, Insurance_End_Date__c, Insurance_Term_months__c,
                   Insurance_Provider__c, Insurance_Provider__r.Name, Premium__c, Deductible__c,
                   Policy_Number__c, Company__r.Name, Building_Coverage_Limit__c,
                   Business_Personal_Property__c, Type__c
            FROM Insurance__c
            WHERE Id = :insuranceId
            WITH USER_MODE
        ];
        Integer members = [
            SELECT COUNT()
            FROM ContactInsuranceAssociation__c
            WHERE Insurance__c = :insuranceId AND Active__c = true
            WITH USER_MODE
        ];
        RenewalContext ctx = new RenewalContext();
        ctx.recordId = ins.Id;
        ctx.name = ins.Name;
        ctx.recordTypeDeveloperName = ins.RecordType.DeveloperName;
        ctx.recordTypeLabel = ins.RecordType.Name;
        ctx.currentStartDate = ins.Insurance_Start_Date__c;
        ctx.currentEndDate = ins.Insurance_End_Date__c;
        ctx.currentTermMonths = ins.Insurance_Term_months__c == null ? null : Integer.valueOf(ins.Insurance_Term_months__c);
        ctx.suggestedStartDate = ins.Insurance_End_Date__c != null
            ? ins.Insurance_End_Date__c.addDays(1) : Date.today();
        ctx.providerId = ins.Insurance_Provider__c;
        ctx.providerName = ins.Insurance_Provider__r.Name;
        ctx.premium = ins.Premium__c;
        ctx.deductible = ins.Deductible__c;
        ctx.policyNumber = ins.Policy_Number__c;
        ctx.companyName = ins.Company__r.Name;
        ctx.buildingCoverageLimit = ins.Building_Coverage_Limit__c;
        ctx.businessPersonalProperty = ins.Business_Personal_Property__c;
        ctx.policyType = ins.Type__c;
        ctx.activeMemberCount = members;
        return ctx;
    }

    /**
     * @description Renews each requested policy. Bulk-safe: all reads and writes are batched across
     * the whole request list (no SOQL/DML inside per-record loops).
     * @param requests The renewal requests to process.
     * @return One RenewalResult per request, in request order.
     */
    public List<RenewalResult> renew(List<RenewalRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return new List<RenewalResult>();
        }

        Map<Id, RenewalRequest> requestByOldId = new Map<Id, RenewalRequest>();
        for (RenewalRequest req : requests) {
            if (req.originalInsuranceId == null) {
                throw new RenewalException('A renewal request is missing its original policy.');
            }
            requestByOldId.put(req.originalInsuranceId, req);
        }

        Map<Id, Insurance__c> oldById = loadPolicies(requestByOldId.keySet());
        if (oldById.isEmpty()) {
            throw new RenewalException('The policy to renew no longer exists.');
        }

        // Clone each old policy into a new active term (parallel list preserves request order).
        List<Insurance__c> oldOrdered = new List<Insurance__c>();
        List<Insurance__c> newPolicies = new List<Insurance__c>();
        for (RenewalRequest req : requests) {
            Insurance__c old = oldById.get(req.originalInsuranceId);
            if (old == null) {
                throw new RenewalException('The policy to renew no longer exists: ' + req.originalInsuranceId);
            }
            // Idempotency guard: only an active policy renews. A renewed policy is set inactive, so a
            // repeat request cannot create a duplicate renewal term.
            if (old.Status__c != STATUS_ACTIVE) {
                throw new RenewalException('Only an active policy can be renewed: ' + req.originalInsuranceId);
            }
            oldOrdered.add(old);
            newPolicies.add(buildRenewalPolicy(old, req));
        }
        // Writes run in system mode: renewal is a Flow-invoked administrative cascade over
        // system-managed policy and coverage-junction records, so it must complete regardless of
        // the initiating user's field-create permissions. Sharing is still enforced (with sharing)
        // and reads stay in user mode.
        Database.insert(newPolicies, AccessLevel.SYSTEM_MODE);

        Map<Id, Id> oldToNew = new Map<Id, Id>();
        for (Integer i = 0; i < oldOrdered.size(); i++) {
            oldToNew.put(oldOrdered[i].Id, newPolicies[i].Id);
        }

        // Capture the members to carry BEFORE the old policies (and their coverage) are inactivated.
        List<ContactInsuranceAssociation__c> membersToCarry = captureActiveMembers(requestByOldId);
        inactivateOldMembers(membersToCarry);
        inactivateOld(oldById.values());
        // Create the new-term coverage LAST — after every old-policy inactivation cascade has run —
        // so no downstream automation can flip the new coverage inactive.
        Map<Id, Integer> carriedByOldId = createNewMembers(membersToCarry, oldToNew, requestByOldId);

        List<RenewalResult> results = new List<RenewalResult>();
        for (RenewalRequest req : requests) {
            RenewalResult res = new RenewalResult();
            res.newInsuranceId = oldToNew.get(req.originalInsuranceId);
            Integer carried = carriedByOldId.get(req.originalInsuranceId);
            res.membersCarried = carried == null ? 0 : carried;
            results.add(res);
        }
        return results;
    }

    /**
     * @description Loads the source policies with every createable field, so the clone inherits all
     * record-type-specific coverage fields. Insurance_End_Date__c (a formula) is included to stamp
     * the outgoing coverage's end date.
     * @param oldIds The source policy ids.
     * @return The source policies by id.
     */
    private Map<Id, Insurance__c> loadPolicies(Set<Id> oldIds) {
        List<String> fields = new List<String>();
        for (Schema.SObjectField f : Insurance__c.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isCreateable()) {
                fields.add(d.getName());
            }
        }
        fields.add('Id');
        fields.add('Insurance_End_Date__c');
        String soql = 'SELECT ' + String.join(fields, ',') +
            ' FROM Insurance__c WHERE Id IN :oldIds';
        Map<Id, Insurance__c> result = new Map<Id, Insurance__c>();
        for (Insurance__c ins : (List<Insurance__c>) Database.queryWithBinds(
            soql, new Map<String, Object>{ 'oldIds' => oldIds }, AccessLevel.USER_MODE
        )) {
            result.put(ins.Id, ins);
        }
        return result;
    }

    /**
     * @description Clones one source policy into a new active-term policy: copies all fields, resets
     * lifecycle fields, links back to the source via Parent_Insurance__c, and applies the request's
     * overrides (start date and term always; the rest only when provided).
     * @param old The source policy (with all createable fields loaded).
     * @param req The renewal request carrying the new-term values.
     * @return The unsaved new policy.
     */
    private Insurance__c buildRenewalPolicy(Insurance__c old, RenewalRequest req) {
        Insurance__c neu = old.clone(false, false, false, false);
        neu.Status__c = STATUS_ACTIVE;
        neu.Parent_Insurance__c = old.Id;
        neu.Cancellation_Date__c = null;
        neu.Cancellation_Reason__c = null;
        neu.Renewal_Opportunity__c = null;
        neu.Paid__c = false;

        // Start date and term are authoritative from the request (term may be null, e.g. whole life,
        // which the End Date formula treats as no end date).
        neu.Insurance_Start_Date__c = req.startDate;
        neu.Insurance_Term_months__c = req.termMonths;

        if (req.providerId != null) {
            neu.Insurance_Provider__c = req.providerId;
        }
        if (req.premium != null) {
            neu.Premium__c = req.premium;
        }
        if (req.deductible != null) {
            neu.Deductible__c = req.deductible;
        }
        if (String.isNotBlank(req.policyName)) {
            neu.Name = req.policyName;
        }
        if (req.buildingCoverageLimit != null) {
            neu.Building_Coverage_Limit__c = req.buildingCoverageLimit;
        }
        if (req.businessPersonalProperty != null) {
            neu.Business_Personal_Property__c = req.businessPersonalProperty;
        }
        if (String.isNotBlank(req.onOffMarket)) {
            neu.On_Off_Market__c = req.onOffMarket;
        }
        if (String.isNotBlank(req.policyType)) {
            neu.Type__c = req.policyType;
        }
        return neu;
    }

    /**
     * @description Reads the active coverage members of the source policies (unless the request
     * opted out), before those policies are inactivated. Members offboarded mid-term are already
     * inactive and so are naturally excluded.
     * @param requestByOldId Source policy id → request (for the carry-members flag).
     * @return The active coverage junctions to carry.
     */
    private List<ContactInsuranceAssociation__c> captureActiveMembers(Map<Id, RenewalRequest> requestByOldId) {
        Set<Id> carryOldIds = new Set<Id>();
        for (Id oldId : requestByOldId.keySet()) {
            RenewalRequest req = requestByOldId.get(oldId);
            if (req.carryMembers == null || req.carryMembers == true) {
                carryOldIds.add(oldId);
            }
        }
        if (carryOldIds.isEmpty()) {
            return new List<ContactInsuranceAssociation__c>();
        }
        return [
            SELECT Id, Contact__c, Insurance__c, Medical__c, Dental__c, Vision__c
            FROM ContactInsuranceAssociation__c
            WHERE Insurance__c IN :carryOldIds AND Active__c = true
            WITH USER_MODE
        ];
    }

    /**
     * @description Inactivates the captured (outgoing-term) coverage members. Deterministic, so it
     * does not depend on the Group Health status orchestration to cascade.
     * @param members The outgoing coverage junctions.
     */
    private void inactivateOldMembers(List<ContactInsuranceAssociation__c> members) {
        if (members.isEmpty()) {
            return;
        }
        List<ContactInsuranceAssociation__c> updates = new List<ContactInsuranceAssociation__c>();
        for (ContactInsuranceAssociation__c cia : members) {
            updates.add(new ContactInsuranceAssociation__c(Id = cia.Id, Active__c = false));
        }
        Database.update(updates, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Clones the captured members onto their new-term policies (Contact and M/D/V
     * copied, active, new dates). Called last so no downstream cascade flips the new rows inactive.
     * @param members The coverage junctions captured from the source policies.
     * @param oldToNew Source policy id → new policy id.
     * @param requestByOldId Source policy id → request (for the new-term dates).
     * @return Count of members carried, by source policy id.
     */
    private Map<Id, Integer> createNewMembers(
        List<ContactInsuranceAssociation__c> members, Map<Id, Id> oldToNew,
        Map<Id, RenewalRequest> requestByOldId
    ) {
        Map<Id, Integer> carriedByOldId = new Map<Id, Integer>();
        if (members.isEmpty()) {
            return carriedByOldId;
        }
        List<ContactInsuranceAssociation__c> newCias = new List<ContactInsuranceAssociation__c>();
        for (ContactInsuranceAssociation__c cia : members) {
            RenewalRequest req = requestByOldId.get(cia.Insurance__c);
            Date newStart = req.startDate;
            Date newEnd = (newStart != null && req.termMonths != null)
                ? newStart.addMonths(req.termMonths) : null;

            ContactInsuranceAssociation__c copy = cia.clone(false, false, false, false);
            copy.Insurance__c = oldToNew.get(cia.Insurance__c);
            copy.Active__c = true;
            copy.Insurance_Start_Date__c = newStart;
            copy.Insurance_End_Date__c = newEnd;
            newCias.add(copy);

            Integer running = carriedByOldId.get(cia.Insurance__c);
            carriedByOldId.put(cia.Insurance__c, running == null ? 1 : running + 1);
        }
        Database.insert(newCias, AccessLevel.SYSTEM_MODE);
        return carriedByOldId;
    }

    /**
     * @description Marks the source policies inactive (their remaining active coverage, for Group
     * Health, is also inactivated by the existing Insurance status-change orchestration).
     * @param oldPolicies The source policies to inactivate.
     */
    private void inactivateOld(List<Insurance__c> oldPolicies) {
        List<Insurance__c> updates = new List<Insurance__c>();
        for (Insurance__c old : oldPolicies) {
            updates.add(new Insurance__c(Id = old.Id, Status__c = STATUS_INACTIVE));
        }
        Database.update(updates, AccessLevel.SYSTEM_MODE);
    }
}
