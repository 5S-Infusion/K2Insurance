/**
 * @description Portfolio Project card LWC. Renders a single project as featured or summary; can emit projectselect when selectable.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
import { LightningElement, api } from "lwc";
import templateFeatured from "./portfolioProject.html";
import templateSummary from "./portfolioProjectSummary.html";

const DEFAULT_PROJECT = {
	title: "Project Title",
	role: "Role / Capacity",
	meta: "Client • Year • Location",
	description: "Short description of the project and your impact.",
	highlights: [],
	tags: [],
	ctaLabel: null,
	ctaUrl: null,
};

export default class PortfolioProject extends LightningElement {
	/**
	 * Render variant. Accepts "featured" (default) or "summary".
	 * @type {"featured" | "summary"}
	 */
	@api status = "featured";

	/**
	 * Project content. Provide a shape similar to DEFAULT_PROJECT.
	 * @type {Object}
	 */
	@api project = DEFAULT_PROJECT;

	/**
	 * When true, the card is clickable and emits projectselect.
	 * @type {boolean}
	 */
	@api selectable = false;

	/** CSS class for the project card (includes variant and clickable modifier). */
	get projectClass() {
		return `project project--${this.status} ${
			this.selectable ? "project--clickable" : ""
		}`;
	}

	/** Tabindex for keyboard focus when selectable. */
	get computedTabIndex() {
		return this.selectable ? "0" : null;
	}

	/** Role when selectable (button for accessibility). */
	get computedRole() {
		return this.selectable ? "button" : null;
	}

	/** Aria-label for the card when selectable. */
	get ariaLabel() {
		return this.selectable
			? `${this.project?.title || "Project"} – open details`
			: null;
	}

	/** Whether the project has highlights to show. */
	get hasHighlights() {
		return Array.isArray(this.project?.highlights) && this.project.highlights.length > 0;
	}

	/** Whether the project has tags to show. */
	get hasTags() {
		return Array.isArray(this.project?.tags) && this.project.tags.length > 0;
	}

	/** Whether the project has a CTA (ctaUrl and ctaLabel). */
	get hasCta() {
		return Boolean(this.project?.ctaUrl && this.project?.ctaLabel);
	}

	/** Alt text for screenshot/placeholder image. */
	get screenshotLabel() {
		return `${this.project?.title || "Project"} screenshot placeholder`;
	}

	/**
	 * Handles card click when selectable; dispatches projectselect with project in detail.
	 * @param {Event} event - click event
	 */
	handleSelect(event) {
		if (!this.selectable) return;
		event.preventDefault();
		this.dispatchEvent(
			new CustomEvent("projectselect", {
				detail: { project: this.project },
				bubbles: true,
				composed: true,
			})
		);
	}

	/**
	 * Handles keydown when selectable; Enter/Space triggers handleSelect.
	 * @param {KeyboardEvent} event - keydown event
	 */
	handleKeydown(event) {
		if (!this.selectable) return;
		const { key } = event;
		if (key === "Enter" || key === " ") {
			event.preventDefault();
			this.handleSelect(event);
		}
	}

	/**
	 * Chooses template by status: summary uses portfolioProjectSummary, else portfolioProject (featured).
	 * @returns {Template} LWC template
	 */
	render() {
		return this.status === "summary" ? templateSummary : templateFeatured;
	}
}