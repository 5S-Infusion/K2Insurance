/**
 * @description Insurance Mass Email LWC. Sends one templated email per selected Insurance record to its Policy Holder.
 * Loads recipients and templates from Apex, supports template preview and optional save-as-activity.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
import { LightningElement, api, track } from "lwc";
import getInitData from "@salesforce/apex/InsuranceMassEmailController.getInitData";
import getTemplatePreview from "@salesforce/apex/InsuranceMassEmailController.getTemplatePreview";
import enqueueSendEmails from "@salesforce/apex/InsuranceMassEmailController.enqueueSendEmails";

export default class InsuranceMassEmail extends LightningElement {
	@api selectedIds = [];

	@track recipients = [];
	@track templateOptions = [];

	selectedTemplateId;
	saveAsActivity = true;
	selectedCount = 0;
	validCount = 0;
	skippedCount = 0;
	isLoaded = false;
	errorMessage;
	successMessage;

	previewTemplateName;
	previewSubject;
	previewHtmlBody;
	previewPlainTextBody;
	previewMessage;
	isPreviewLoading = false;

	columns = [
		{ label: "Insurance", fieldName: "insuranceName" },
		{ label: "Policy Holder", fieldName: "contactName" },
		{ label: "Email", fieldName: "contactEmail" },
		{ label: "Status", fieldName: "status" },
	];

	/** Lifecycle hook: load init data when component is connected. */
	connectedCallback() {
		this.loadData();
	}

	/** Whether the Send Emails button should be disabled (no template or no valid recipients). */
	get sendDisabled() {
		return !this.selectedTemplateId || this.validCount === 0;
	}

	/** Whether to show the template preview section (a template is selected). */
	get showPreviewSection() {
		return !!this.selectedTemplateId;
	}

	/** Whether preview has subject or body content to display. */
	get showPreviewContent() {
		return !!this.previewSubject || !!this.previewBodyToDisplay;
	}

	/** Preview body: HTML if present, otherwise plain text. */
	get previewBodyToDisplay() {
		return this.previewHtmlBody || this.previewPlainTextBody || "";
	}

	/** Whether the template has HTML body for preview. */
	get hasPreviewHtml() {
		return !!this.previewHtmlBody;
	}

	/** First 20 recipients for display (all selected are still sent). */
	get displayedRecipients() {
		return (this.recipients || []).slice(0, 20);
	}

	/** Count of recipients currently displayed in the table. */
	get displayedRecipientCount() {
		return this.displayedRecipients.length;
	}

	/**
	 * Loads init data (recipients and templates) from Apex.
	 * @returns {Promise<void>}
	 */
	async loadData() {
		try {
			const response = await getInitData({
				insuranceIds: this.selectedIds,
			});
			this.selectedCount = response.selectedCount;
			this.validCount = response.validCount;
			this.skippedCount = response.skippedCount;
			this.recipients = response.recipients || [];
			this.templateOptions = (response.templates || []).map(
				(templateRecord) => ({
					label: templateRecord.label,
					value: templateRecord.templateId,
				}),
			);
			this.errorMessage = null;
		} catch (error) {
			this.errorMessage = this.normalizeError(error);
		} finally {
			this.isLoaded = true;
		}
	}

	/**
	 * Handles template combobox change; loads preview when a template is selected.
	 * @param {Event} event - change event with event.detail.value (template Id)
	 */
	async handleTemplateChange(event) {
		this.selectedTemplateId = event.detail.value;
		this.clearPreview();

		if (!this.selectedTemplateId) {
			return;
		}

		await this.loadPreview();
	}

	/** Handles Save as Activity checkbox change. */
	handleSaveAsActivityChange(event) {
		this.saveAsActivity = event.target.checked;
	}

	/**
	 * Loads template preview (subject and body) from Apex.
	 * @returns {Promise<void>}
	 */
	async loadPreview() {
		this.isPreviewLoading = true;
		this.previewMessage = null;

		try {
			const result = await getTemplatePreview({
				templateId: this.selectedTemplateId,
			});

			if (result && result.success) {
				this.previewTemplateName = result.templateName;
				this.previewSubject = result.subject;
				this.previewHtmlBody = result.htmlBody;
				this.previewPlainTextBody = result.plainTextBody;
				this.previewMessage = result.message;
			} else {
				this.previewTemplateName = null;
				this.previewSubject = null;
				this.previewHtmlBody = null;
				this.previewPlainTextBody = null;
				this.previewMessage = result ? result.message : null;
			}
		} catch (error) {
			this.previewTemplateName = null;
			this.previewSubject = null;
			this.previewHtmlBody = null;
			this.previewPlainTextBody = null;
			this.previewMessage = this.normalizeError(error);
		} finally {
			this.isPreviewLoading = false;
		}
	}

	/** Clears all preview state (template name, subject, body, message). */
	clearPreview() {
		this.previewTemplateName = null;
		this.previewSubject = null;
		this.previewHtmlBody = null;
		this.previewPlainTextBody = null;
		this.previewMessage = null;
		this.isPreviewLoading = false;
	}

	/**
	 * Submits the mass email job via Apex (enqueueSendEmails).
	 * @returns {Promise<void>}
	 */
	async handleSend() {
		this.successMessage = null;
		this.errorMessage = null;

		try {
			const message = await enqueueSendEmails({
				insuranceIds: this.selectedIds,
				templateId: this.selectedTemplateId,
				saveAsActivity: this.saveAsActivity,
			});

			this.successMessage = message;
		} catch (error) {
			this.errorMessage = this.normalizeError(error);
		}
	}

	/**
	 * Normalizes Apex/LWC error into a user-facing message string.
	 * @param {Object} error - Error object (may have body.message or message)
	 * @returns {string} User-facing error message
	 */
	normalizeError(error) {
		if (error?.body?.message) {
			return error.body.message;
		}
		if (error?.message) {
			return error.message;
		}
		return "An unexpected error occurred.";
	}
}