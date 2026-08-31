/**
 * @description Shared test-data factory for the agent payout tests: builds agent accounts, policies
 * with and without a commission rate, commission statements for a payment period, and the
 * commission lines hanging off them.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
@isTest
public with sharing class AgentPayoutTestData {

    public static final String PERIOD_ONE = '2026-01';
    public static final String PERIOD_TWO = '2026-02';
    public static final String PERIOD_THREE = '2026-03';

    private static Boolean accessGranted = false;
    private static Map<String, Id> recordTypeCache = new Map<String, Id>();
    private static Integer sequence = 0;

    /**
     * @description Everything one payout scenario needs: the agent, the carrier, the policy holder,
     * a policy that carries a commission rate, and the statements and lines created so far.
     */
    public class Scenario {
        public Account agent;
        public Account carrier;
        public Contact holder;
        public Insurance__c policy;
        public Map<String, Commission_Statement__c> statementsByPeriod =
            new Map<String, Commission_Statement__c>();
        public List<Commission_Line__c> lines = new List<Commission_Line__c>();
    }

    /**
     * @description Assigns the Agent Management permission set to the running user. A field
     * deployed by the Metadata API carries no field-level security of its own, so without this the
     * user-mode queries and DML the service issues cannot see the new fields at all.
     */
    public static void grantAccess() {
        if (accessGranted) {
            return;
        }
        accessGranted = true;
        List<PermissionSet> permissionSets = [
            SELECT Id FROM PermissionSet WHERE Name = 'Agent_Management' LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }
        Id userId = UserInfo.getUserId();
        List<PermissionSetAssignment> existing = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :permissionSets[0].Id
        ];
        if (!existing.isEmpty()) {
            return;
        }
        // runAs keeps this setup-object DML out of the same transaction slot as the record data.
        System.runAs(new User(Id = userId)) {
            insert new PermissionSetAssignment(
                AssigneeId = userId, PermissionSetId = permissionSets[0].Id
            );
        }
    }

    /**
     * @description Inserts accounts in one DML, so a scenario that needs several of them costs one
     * statement rather than one per record.
     * @param accounts The accounts to insert.
     * @return The inserted accounts.
     */
    public static List<Account> createAccounts(List<Account> accounts) {
        grantAccess();
        insert accounts;
        return accounts;
    }

    /**
     * @description Inserts contacts in one DML.
     * @param contacts The contacts to insert.
     * @return The inserted contacts.
     */
    public static List<Contact> createContacts(List<Contact> contacts) {
        grantAccess();
        insert contacts;
        return contacts;
    }

    /**
     * @description Inserts policies in one DML.
     * @param policies The policies to insert.
     * @return The inserted policies.
     */
    public static List<Insurance__c> createPolicies(List<Insurance__c> policies) {
        grantAccess();
        insert policies;
        return policies;
    }

    /**
     * @description Inserts commission statements in one DML.
     * @param statements The statements to insert.
     * @return The inserted statements.
     */
    public static List<Commission_Statement__c> createStatements(
        List<Commission_Statement__c> statements
    ) {
        grantAccess();
        insert statements;
        return statements;
    }

    /**
     * @description Shapes an agent account (a person account on the Agent record type) without
     * saving it, so several can be inserted together.
     * @param firstName The agent's first name.
     * @param lastName The agent's last name.
     * @param accountRate The agent's own default commission rate, which must never drive payment.
     * @return The unsaved agent account.
     */
    public static Account buildAgent(String firstName, String lastName, Decimal accountRate) {
        return new Account(
            FirstName = firstName,
            LastName = lastName,
            RecordTypeId = recordTypeId('Account', 'Agent'),
            Commission_Rate__c = accountRate
        );
    }

    /**
     * @description Shapes a carrier account without saving it.
     * @param name The carrier name.
     * @return The unsaved carrier account.
     */
    public static Account buildCarrier(String name) {
        return new Account(
            Name = name,
            RecordTypeId = recordTypeId('Account', 'Insurance_Provider')
        );
    }

    /**
     * @description Creates an agent account (a person account on the Agent record type).
     * @param firstName The agent's first name.
     * @param lastName The agent's last name.
     * @param accountRate The agent's own default commission rate, which must never drive payment.
     * @return The inserted agent account.
     */
    public static Account createAgent(String firstName, String lastName, Decimal accountRate) {
        return createAccounts(
            new List<Account>{ buildAgent(firstName, lastName, accountRate) }
        )[0];
    }

    /**
     * @description Creates a carrier account.
     * @param name The carrier name.
     * @return The inserted carrier account.
     */
    public static Account createCarrier(String name) {
        return createAccounts(new List<Account>{ buildCarrier(name) })[0];
    }

    /**
     * @description Creates a policy holder contact.
     * @param lastName The holder's last name.
     * @return The inserted contact.
     */
    public static Contact createHolder(String lastName) {
        return createContacts(
            new List<Contact>{ new Contact(LastName = lastName, Status__c = 'Active') }
        )[0];
    }

    /**
     * @description Creates a health policy owned by the given holder and attributed to the given
     * subagent, carrying the given commission rate. A null rate is the unrated case that cannot be
     * valued.
     * @param policyName The policy number.
     * @param carrierId The carrier account.
     * @param holderId The policy holder contact.
     * @param subagentId The subagent account, or null for a policy K2 keeps.
     * @param rate The policy commission rate as a percent, or null when it is not set.
     * @return The inserted policy.
     */
    public static Insurance__c createPolicy(
        String policyName, Id carrierId, Id holderId, Id subagentId, Decimal rate
    ) {
        return createPolicies(new List<Insurance__c>{
            new Insurance__c(
                Name = policyName,
                RecordTypeId = recordTypeId('Insurance__c', 'Health_Insurance'),
                Insurance_Provider__c = carrierId,
                Policy_Holder__c = holderId,
                Subagent__c = subagentId,
                Commission_Rate__c = rate,
                Status__c = 'Active',
                Insurance_Start_Date__c = Date.today().addMonths(-6),
                Insurance_Term_months__c = 12
            )
        })[0];
    }

    /**
     * @description Creates a commission statement for one payment period.
     * @param period The payment period in "YYYY-MM" form.
     * @param carrierId The carrier that issued the statement.
     * @return The inserted statement.
     */
    public static Commission_Statement__c createStatement(String period, Id carrierId) {
        return createStatements(new List<Commission_Statement__c>{
            new Commission_Statement__c(
                Payment_Period__c = period,
                Insurance_Provider__c = carrierId,
                Source_Format__c = 'CSV',
                Status__c = 'Done',
                Type__c = 'Individual'
            )
        })[0];
    }

    /**
     * @description Creates commission lines of equal amount under one statement, all pointing at
     * one policy.
     * @param statementId The parent statement.
     * @param policyId The policy the lines belong to.
     * @param lineCount How many lines to create.
     * @param amount The commission amount on each line.
     * @return The inserted lines.
     */
    public static List<Commission_Line__c> createLines(
        Id statementId, Id policyId, Integer lineCount, Decimal amount
    ) {
        return createLines(buildLines(statementId, policyId, lineCount, amount));
    }

    /**
     * @description Inserts commission lines in one DML.
     * @param lines The lines to insert.
     * @return The inserted lines.
     */
    public static List<Commission_Line__c> createLines(List<Commission_Line__c> lines) {
        grantAccess();
        insert lines;
        return lines;
    }

    /**
     * @description Shapes commission lines of equal amount under one statement without saving them.
     * @param statementId The parent statement.
     * @param policyId The policy the lines belong to.
     * @param lineCount How many lines to shape.
     * @param amount The commission amount on each line.
     * @return The unsaved lines.
     */
    public static List<Commission_Line__c> buildLines(
        Id statementId, Id policyId, Integer lineCount, Decimal amount
    ) {
        List<Commission_Line__c> lines = new List<Commission_Line__c>();
        for (Integer i = 0; i < lineCount; i++) {
            lines.add(new Commission_Line__c(
                Commission_Statement__c = statementId,
                Policy_Number__c = policyId,
                Commission_Amount__c = amount,
                Commission_Date__c = Date.today(),
                Policy_Number_Imported__c = 'IMP-' + String.valueOf(nextSequence())
            ));
        }
        return lines;
    }

    /**
     * @description Builds a complete single-agent scenario: one agent, one carrier, one holder, one
     * rated policy, and the requested lines in one payment period.
     * @param period The payment period the lines fall in.
     * @param lineCount How many lines to create.
     * @param amount The commission amount on each line.
     * @param rate The policy commission rate as a percent, or null for the unrated case.
     * @return The scenario.
     */
    public static Scenario build(String period, Integer lineCount, Decimal amount, Decimal rate) {
        grantAccess();
        Integer suffix = nextSequence();
        Scenario scenario = new Scenario();
        scenario.agent = createAgent('Agent Payout' + suffix, 'Tester' + suffix, 90);
        scenario.carrier = createCarrier('Payout Carrier ' + suffix);
        scenario.holder = createHolder('Payout Holder ' + suffix);
        scenario.policy = createPolicy(
            'AP-POL-' + suffix, scenario.carrier.Id, scenario.holder.Id, scenario.agent.Id, rate
        );
        addLines(scenario, period, scenario.policy.Id, lineCount, amount);
        return scenario;
    }

    /**
     * @description Adds lines to a scenario in the given period, reusing the period's statement
     * when one already exists.
     * @param scenario The scenario to extend.
     * @param period The payment period.
     * @param policyId The policy the lines belong to.
     * @param lineCount How many lines to create.
     * @param amount The commission amount on each line.
     * @return The lines that were created.
     */
    public static List<Commission_Line__c> addLines(
        Scenario scenario, String period, Id policyId, Integer lineCount, Decimal amount
    ) {
        Commission_Statement__c statement = scenario.statementsByPeriod.get(period);
        if (statement == null) {
            statement = createStatement(period, scenario.carrier.Id);
            scenario.statementsByPeriod.put(period, statement);
        }
        List<Commission_Line__c> created = createLines(statement.Id, policyId, lineCount, amount);
        scenario.lines.addAll(created);
        return created;
    }

    /**
     * @description Creates a user who has not been granted the feature, for exercising the
     * permission-dependent paths as someone other than an administrator. A minimum-access profile
     * is used so the ungranted path is exercised as a non-administrator.
     * @param alias The user alias, which also seeds the unique username.
     * @return The inserted user.
     */
    public static User createRestrictedUser(String alias) {
        Profile restrictedProfile = [SELECT Id FROM Profile WHERE Name = 'Identity User' LIMIT 1];
        return createUsers(new List<User>{
            new User(
                Alias = alias,
                Email = alias + '@k2insurance.invalid',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Restricted',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = restrictedProfile.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = alias + String.valueOf(DateTime.now().getTime()) + '@k2insurance.invalid'
            )
        })[0];
    }

    /**
     * @description Inserts users in one DML.
     * @param users The users to insert.
     * @return The inserted users.
     */
    public static List<User> createUsers(List<User> users) {
        insert users;
        return users;
    }

    /**
     * @description Resolves a record type id by object and developer name, caching each lookup.
     * @param sobjectType The object api name.
     * @param developerName The record type developer name.
     * @return The record type id.
     */
    private static Id recordTypeId(String sobjectType, String developerName) {
        String key = sobjectType + '.' + developerName;
        if (!recordTypeCache.containsKey(key)) {
            recordTypeCache.put(key, [
                SELECT Id FROM RecordType
                WHERE SobjectType = :sobjectType AND DeveloperName = :developerName
                LIMIT 1
            ].Id);
        }
        return recordTypeCache.get(key);
    }

    /**
     * @description Returns the next value of the factory's uniqueness counter.
     * @return The next sequence number.
     */
    private static Integer nextSequence() {
        sequence++;
        return sequence;
    }
}
