/**
 * @description LWC adapter for the Agent Management page; delegates to AgentPayoutService and
 * surfaces controlled errors to the UI.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
public with sharing class AgentPayoutController {

    @TestVisible
    private static AgentPayoutService service = new AgentPayoutService();

    /**
     * @description Loads the agent board: one row per subagent with commission lines, laid out
     * across the payment-period axis.
     * @return The board.
     */
    @AuraEnabled(cacheable=true)
    public static AgentPayoutService.BoardDto getBoard() {
        try {
            return service.getBoard();
        } catch (AgentPayoutService.AgentPayoutException ex) {
            throw uiError(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.getBoard', null, ex);
            throw uiError(Label.AgentManagement_LoadError);
        }
    }

    /**
     * @description Reports what the running user may see and do on the Agent Management page.
     * @return The running user's access.
     */
    @AuraEnabled(cacheable=true)
    public static AgentPayoutService.AccessDto getAccess() {
        try {
            return service.getAccess();
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.getAccess', null, ex);
            throw uiError(Label.AgentManagement_LoadError);
        }
    }

    /**
     * @description Returns the payment-method options for the payout form.
     * @return One {label, value} map per active option.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getMethodOptions() {
        try {
            return service.getMethodOptions();
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.getMethodOptions', null, ex);
            throw uiError(Label.AgentManagement_LoadError);
        }
    }

    /**
     * @description Lists the agent's commission lines for the given periods, for the drill-down
     * table.
     * @param agentId The agent whose lines to list.
     * @param periods The payment periods to list.
     * @return The lines.
     */
    @AuraEnabled(cacheable=true)
    public static List<AgentPayoutService.LineDto> getLines(Id agentId, List<String> periods) {
        try {
            return service.getLines(agentId, periods);
        } catch (AgentPayoutService.AgentPayoutException ex) {
            throw uiError(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.getLines', agentId, ex);
            throw uiError(Label.AgentManagement_LoadError);
        }
    }

    /**
     * @description Prices a proposed payout on demand. The request arrives as a JSON string because
     * an object handed straight from reactive component state serializes to an empty object at
     * Apex; the client's own JSON.stringify preserves the fields. The answer goes back as JSON too,
     * so the client parses one known shape rather than an Apex-serialized object graph.
     * @param requestJson JSON object matching AgentPayoutService.PayoutRequest.
     * @return The server's valuation of the proposed payout, as JSON.
     */
    @AuraEnabled
    public static String getPreflightJson(String requestJson) {
        try {
            return JSON.serialize(service.getPreflight(parseRequest(requestJson)));
        } catch (AgentPayoutService.AgentPayoutException ex) {
            throw uiError(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.getPreflightJson', null, ex);
            throw uiError(Label.AgentManagement_LoadError);
        }
    }

    /**
     * @description Records one payout and stamps the commission lines it settles. The request
     * arrives as a JSON string for the same reason as getPreflightJson.
     * @param requestJson JSON object matching AgentPayoutService.PayoutRequest.
     * @return The id of the payout that was created.
     */
    @AuraEnabled
    public static Id createPayoutJson(String requestJson) {
        try {
            return service.createPayout(parseRequest(requestJson));
        } catch (AgentPayoutService.AgentPayoutException ex) {
            throw uiError(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.createPayoutJson', null, ex);
            throw uiError(Label.AgentManagement_SaveError);
        }
    }

    /**
     * @description Voids a payout and releases the lines it stamped.
     * @param payoutId The payout to void.
     * @param reason Why the payout is being voided.
     */
    @AuraEnabled
    public static void voidPayout(Id payoutId, String reason) {
        try {
            service.voidPayout(payoutId, reason);
        } catch (AgentPayoutService.AgentPayoutException ex) {
            throw uiError(ex.getMessage());
        } catch (Exception ex) {
            ExceptionLogger.log('AgentPayoutController.voidPayout', payoutId, ex);
            throw uiError(Label.AgentManagement_SaveError);
        }
    }

    /**
     * @description Builds the one error shape this page ever surfaces: a controlled, user-facing
     * message and nothing of the system exception behind it. The message is set on the exception as
     * well as handed to its constructor, so the text the client is shown is also the text the
     * exception reports, and neither the UI nor a test has to read a system-generated substitute.
     * @param message The user-facing message, which is always a Custom Label.
     * @return The exception to throw.
     */
    private static AuraHandledException uiError(String message) {
        AuraHandledException surfaced = new AuraHandledException(message);
        surfaced.setMessage(message);
        return surfaced;
    }

    /**
     * @description Deserializes an inbound payout request and refuses one that carries no agent.
     * An empty or blank payload is exactly what a reactive-state object collapses to on its way to
     * Apex, so it is rejected here rather than being saved as a payout against nobody.
     * @param requestJson The JSON payload.
     * @return The parsed request.
     */
    private static AgentPayoutService.PayoutRequest parseRequest(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new AgentPayoutService.AgentPayoutException(Label.AgentManagement_AgentRequired);
        }
        AgentPayoutService.PayoutRequest request =
            (AgentPayoutService.PayoutRequest) JSON.deserialize(
                requestJson, AgentPayoutService.PayoutRequest.class);
        if (request == null || request.agentId == null) {
            throw new AgentPayoutService.AgentPayoutException(Label.AgentManagement_AgentRequired);
        }
        return request;
    }
}
