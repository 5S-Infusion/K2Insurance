/**
 * @description Tests for InsuranceRenewalService — policy clone, coverage carryover, old-policy
 * inactivation, overrides, whole-life (no term), fault paths, and bulk behavior.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
private class InsuranceRenewalServiceTest {

    private static Map<String, Id> insuranceRt() {
        Map<String, Id> byName = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = 'Insurance__c'
        ]) {
            byName.put(rt.DeveloperName, rt.Id);
        }
        return byName;
    }

    private static Id providerAccountId() {
        Id providerRt = [
            SELECT Id FROM RecordType
            WHERE SobjectType = 'Account' AND DeveloperName = 'Insurance_Provider' LIMIT 1
        ].Id;
        Account carrier = new Account(Name = 'Renewal Test Carrier', RecordTypeId = providerRt);
        insert carrier;
        return carrier.Id;
    }

    private static Insurance__c buildPolicy(String rtDeveloperName, Integer term, Id providerId) {
        Contact holder = new Contact(LastName = 'Renewal Holder ' + rtDeveloperName, Status__c = 'Active');
        insert holder;
        Insurance__c policy = new Insurance__c(
            Name = 'REN-' + rtDeveloperName,
            RecordTypeId = insuranceRt().get(rtDeveloperName),
            Insurance_Provider__c = providerId,
            Policy_Holder__c = holder.Id,
            Status__c = 'Active',
            Insurance_Start_Date__c = Date.today().addMonths(-12),
            Insurance_Term_months__c = term
        );
        insert policy;
        return policy;
    }

    private static InsuranceRenewalService.RenewalRequest request(Id oldId, Date start, Integer term) {
        InsuranceRenewalService.RenewalRequest req = new InsuranceRenewalService.RenewalRequest();
        req.originalInsuranceId = oldId;
        req.startDate = start;
        req.termMonths = term;
        return req;
    }

    /**
     * @description Renewing a Group Health policy clones it, carries every active member onto the new
     * term, inactivates the old policy and its coverage, and links the new policy to the old.
     */
    @isTest
    static void renewGroupHealthCarriesMembers() {
        EmployeeRosterTestData.buildRoster(5);
        // The org decorates Insurance Name with its status, so match by prefix.
        Insurance__c gh = [
            SELECT Id FROM Insurance__c WHERE Name LIKE 'ROSTER-GH-TEST%' LIMIT 1
        ];
        Integer activeBefore = [
            SELECT COUNT() FROM ContactInsuranceAssociation__c
            WHERE Insurance__c = :gh.Id AND Active__c = true
        ];

        Test.startTest();
        List<InsuranceRenewalService.RenewalResult> results = new InsuranceRenewalService().renew(
            new List<InsuranceRenewalService.RenewalRequest>{ request(gh.Id, Date.today(), 12) }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One result per request');
        Id newId = results[0].newInsuranceId;
        Assert.isNotNull(newId, 'A new policy should be created');
        Assert.areEqual(activeBefore, results[0].membersCarried, 'Every active member carried');

        Insurance__c neu = [
            SELECT Status__c, Parent_Insurance__c, Insurance_Start_Date__c, Insurance_Term_months__c
            FROM Insurance__c WHERE Id = :newId
        ];
        Assert.areEqual('Active', neu.Status__c, 'New policy is active');
        Assert.areEqual(gh.Id, neu.Parent_Insurance__c, 'New policy links to the old policy');
        Assert.areEqual(Date.today(), neu.Insurance_Start_Date__c, 'New start date applied');
        Assert.areEqual(12, neu.Insurance_Term_months__c, 'New term applied');

        Assert.areEqual('Inactive',
            [SELECT Status__c FROM Insurance__c WHERE Id = :gh.Id].Status__c,
            'Old policy inactivated');
        Assert.areEqual(activeBefore,
            [SELECT COUNT() FROM ContactInsuranceAssociation__c WHERE Insurance__c = :newId AND Active__c = true],
            'New term carries an active coverage row per member');
        Assert.areEqual(0,
            [SELECT COUNT() FROM ContactInsuranceAssociation__c WHERE Insurance__c = :gh.Id AND Active__c = true],
            'Old coverage inactivated');
    }

    /**
     * @description getContext returns the current policy values, its record type, active member
     * count, and a suggested new start date one day after the current term ends.
     */
    @isTest
    static void getContextReturnsPolicyAndMemberCount() {
        EmployeeRosterTestData.buildRoster(5);
        Insurance__c gh = [
            SELECT Id, Insurance_End_Date__c FROM Insurance__c WHERE Name LIKE 'ROSTER-GH-TEST%' LIMIT 1
        ];

        Test.startTest();
        InsuranceRenewalService.RenewalContext ctx = new InsuranceRenewalService().getContext(gh.Id);
        Test.stopTest();

        Assert.areEqual('Group_Health', ctx.recordTypeDeveloperName, 'Record type resolved');
        Assert.areEqual(5, ctx.activeMemberCount, 'Active members counted');
        Assert.areEqual(gh.Insurance_End_Date__c.addDays(1), ctx.suggestedStartDate,
            'Suggested start is the day after the current term ends');
        Assert.isNotNull(ctx.providerName, 'Provider name carried for display');
    }

    /**
     * @description A record type with no coverage junctions (e.g. Auto/Home) renews as a pure policy
     * clone with zero members carried.
     */
    @isTest
    static void renewNonGroupHealthCarriesNoMembers() {
        Insurance__c auto = buildPolicy('Auto_Home_Insurance', 6, providerAccountId());

        Test.startTest();
        List<InsuranceRenewalService.RenewalResult> results = new InsuranceRenewalService().renew(
            new List<InsuranceRenewalService.RenewalRequest>{ request(auto.Id, Date.today(), 6) }
        );
        Test.stopTest();

        Assert.areEqual(0, results[0].membersCarried, 'No coverage rows to carry');
        Assert.areEqual('Active',
            [SELECT Status__c FROM Insurance__c WHERE Id = :results[0].newInsuranceId].Status__c,
            'New policy is active');
        Assert.areEqual('Inactive',
            [SELECT Status__c FROM Insurance__c WHERE Id = :auto.Id].Status__c,
            'Old policy inactivated');
    }

    /**
     * @description Non-null overrides (provider, premium, deductible, name, coverage limits) are
     * applied to the new policy; the record-type-specific fields are inherited from the clone.
     */
    @isTest
    static void renewAppliesOverrides() {
        Id firstProvider = providerAccountId();
        Insurance__c auto = buildPolicy('Auto_Home_Insurance', 6, firstProvider);
        Id secondProvider = providerAccountId();

        InsuranceRenewalService.RenewalRequest req = request(auto.Id, Date.today(), 6);
        req.providerId = secondProvider;
        req.premium = 1234.56;
        req.deductible = 500;
        req.policyName = 'REN-AUTO-2027';
        req.buildingCoverageLimit = 250000;
        req.businessPersonalProperty = 75000;

        Test.startTest();
        List<InsuranceRenewalService.RenewalResult> results = new InsuranceRenewalService().renew(
            new List<InsuranceRenewalService.RenewalRequest>{ req }
        );
        Test.stopTest();

        Insurance__c neu = [
            SELECT Name, Insurance_Provider__c, Premium__c, Deductible__c,
                   Building_Coverage_Limit__c, Business_Personal_Property__c
            FROM Insurance__c WHERE Id = :results[0].newInsuranceId
        ];
        Assert.areEqual(secondProvider, neu.Insurance_Provider__c, 'Provider override applied');
        Assert.areEqual(1234.56, neu.Premium__c, 'Premium override applied');
        Assert.areEqual(500, neu.Deductible__c, 'Deductible override applied');
        Assert.isTrue(neu.Name.startsWith('REN-AUTO-2027'), 'Policy name override applied (org appends status)');
        Assert.areEqual(250000, neu.Building_Coverage_Limit__c, 'Building limit override applied');
        Assert.areEqual(75000, neu.Business_Personal_Property__c, 'BPP override applied');
    }

    /**
     * @description Whole-life renewal passes a null term straight through to the new policy. (Note:
     * the End Date formula treats a blank term as zero (BlankAsZero), so it does not resolve to a
     * true "no end date" — the Life screen behavior is finalized in a later phase.)
     */
    @isTest
    static void renewLifePreservesNullTerm() {
        Insurance__c life = buildPolicy('Life_Insurance', 12, providerAccountId());

        Test.startTest();
        List<InsuranceRenewalService.RenewalResult> results = new InsuranceRenewalService().renew(
            new List<InsuranceRenewalService.RenewalRequest>{ request(life.Id, Date.today(), null) }
        );
        Test.stopTest();

        Assert.isNull(
            [SELECT Insurance_Term_months__c FROM Insurance__c WHERE Id = :results[0].newInsuranceId]
                .Insurance_Term_months__c,
            'A null term is preserved on the renewed whole-life policy');
    }

    /**
     * @description An empty request list is a safe no-op.
     */
    @isTest
    static void renewEmptyReturnsEmpty() {
        Test.startTest();
        List<InsuranceRenewalService.RenewalResult> results =
            new InsuranceRenewalService().renew(new List<InsuranceRenewalService.RenewalRequest>());
        Test.stopTest();
        Assert.areEqual(0, results.size(), 'Empty in, empty out');
    }

    /**
     * @description A request without an original policy id is rejected with a typed exception.
     */
    @isTest
    static void renewNullOriginalThrows() {
        Test.startTest();
        try {
            new InsuranceRenewalService().renew(
                new List<InsuranceRenewalService.RenewalRequest>{
                    request(null, Date.today(), 12)
                }
            );
            Assert.fail('Expected a RenewalException for a missing original policy');
        } catch (InsuranceRenewalService.RenewalException ex) {
            Assert.isNotNull(ex.getMessage(), 'The exception carries a message');
        }
        Test.stopTest();
    }

    /**
     * @description A request whose original policy does not exist is rejected.
     */
    @isTest
    static void renewNonexistentThrows() {
        Test.startTest();
        try {
            new InsuranceRenewalService().renew(
                new List<InsuranceRenewalService.RenewalRequest>{
                    request('a0m000000000000AAA', Date.today(), 12)
                }
            );
            Assert.fail('Expected a RenewalException for a nonexistent policy');
        } catch (InsuranceRenewalService.RenewalException ex) {
            Assert.isNotNull(ex.getMessage(), 'The exception carries a message');
        } catch (System.QueryException ex) {
            Assert.isNotNull(ex, 'A bad id may fail at query binding');
        }
        Test.stopTest();
    }

    /**
     * @description A policy that is not active cannot be renewed (idempotency guard).
     */
    @isTest
    static void renewInactivePolicyThrows() {
        Insurance__c policy = buildPolicy('Other', 12, providerAccountId());
        update new Insurance__c(Id = policy.Id, Status__c = 'Inactive');

        Test.startTest();
        try {
            new InsuranceRenewalService().renew(
                new List<InsuranceRenewalService.RenewalRequest>{ request(policy.Id, Date.today(), 12) }
            );
            Assert.fail('Expected a RenewalException for an inactive policy');
        } catch (InsuranceRenewalService.RenewalException ex) {
            Assert.isTrue(ex.getMessage().contains('active'), 'The message explains only active policies renew');
        }
        Test.stopTest();
    }

    /**
     * @description Bulk renewal processes multiple policies in one call with no per-record DML.
     */
    @isTest
    static void renewBulkMultiplePolicies() {
        Id provider = providerAccountId();
        List<InsuranceRenewalService.RenewalRequest> requests =
            new List<InsuranceRenewalService.RenewalRequest>();
        List<Id> oldIds = new List<Id>();
        for (Integer i = 0; i < 25; i++) {
            Insurance__c p = buildPolicy('Other', 12, provider);
            oldIds.add(p.Id);
            requests.add(request(p.Id, Date.today(), 12));
        }

        Test.startTest();
        List<InsuranceRenewalService.RenewalResult> results = new InsuranceRenewalService().renew(requests);
        Test.stopTest();

        Assert.areEqual(25, results.size(), 'One result per policy');
        Assert.areEqual(25,
            [SELECT COUNT() FROM Insurance__c WHERE Parent_Insurance__c IN :oldIds AND Status__c = 'Active'],
            'A new active policy per source policy');
        Assert.areEqual(25,
            [SELECT COUNT() FROM Insurance__c WHERE Id IN :oldIds AND Status__c = 'Inactive'],
            'Every source policy inactivated');
    }
}
