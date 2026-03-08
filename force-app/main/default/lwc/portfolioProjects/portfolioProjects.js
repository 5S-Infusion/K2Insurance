/**
 * @description Portfolio Projects list LWC. Displays project cards and opens a modal for project details.
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-03-07
 */
import { LightningElement, api } from "lwc";

const WI_PROJECT = {
	title: "Wisconsin Access Modernization Project",
	role: "Lead LWC Developer • Mentor",
	meta: "State of Wisconsin (Public Sector) • 2024–2025 • Deloitte",
	description:
		"Modernized Experience Cloud pages and internal Lightning applications with SLDS-based components that prioritized responsiveness, accessibility, and consistency.",
	highlights: [
		"Led LWC development and mentored intermediate developers; set code review standards and SLDS patterns for performance and consistency",
		"Built a centralized CSS design system with rem-based typography and spacing tokens so all LWCs share responsive, scalable sizing across devices and browser zoom levels",
		"Delivered SLDS Lightning Web Components for high-traffic internal apps and Experience Cloud portals to improve UI responsiveness and reliability under load",
		"Enforced WCAG 2.1 AA using accessibility tooling such as axe and Lightning Accessibility Scanner; validated keyboard navigation, contrast, and landmark semantics to satisfy state requirements",
		"Developed Apex controllers and REST API integrations to streamline cross-system data exchange, improving data consistency and operational performance",
	],
	tags: [
		"Lightning Web Components",
		"SLDS",
		"Experience Cloud",
		"Apex REST",
		"WCAG 2.1",
		"Accessibility",
		"LWC Render Techniques",
		"rem-based spacing",
		"Mentorship",
	],
	ctaLabel: "Discuss similar builds",
	ctaUrl: "/contact",
	status: "featured",
};

const MAPPING_API_REFACTORING = {
	title: "Mapping API Refactoring Project",
	role: "Senior DevOps Engineer",
	meta: "Mapping API Refactoring • 2025 • AAA ACE | ERS Team",
	description:
		"Refactored and optimized mapping APIs to enhance performance, scalability, and maintainability for geospatial data services.",
	highlights: [
		"Led the refactoring of mapping APIs to improve response times and reduce latency for geospatial data retrieval",
		"Implemented scalable architecture solutions to handle increased data loads and user requests efficiently",
		"Enhanced code maintainability by adopting best practices and design patterns in API development",
	],
	tags: [
		"Lightning Web Components",
		"Visualforce",
		"CSP",
		"Apex REST",
		"Defined Architecture",
		"Software Design Patterns",
	],
	ctaLabel: "Discuss similar builds",
	ctaUrl: "/contact",
	status: "featured",
};

export default class PortfolioProjects extends LightningElement {
	/**
	 * Override projects list if provided externally (e.g., via CMS or page builder JSON).
	 * Each entry should include project fields and optional status ("featured" | "summary").
	 * @type {Array}
	 */
	@api projects = [WI_PROJECT, MAPPING_API_REFACTORING];

	showModal = false;
	selectedProject = null;

	/** Projects list with normalized id and status. */
	get normalizedProjects() {
		return (this.projects || []).map((project, index) => ({
			id: project.id || `proj-${index}`,
			status: project.status || "featured",
			...project,
		}));
	}

	/** Project to show in the modal (selected or default). */
	get modalProject() {
		return this.selectedProject || WI_PROJECT;
	}

	/**
	 * Handles project card select; opens modal with selected project.
	 * @param {Event} event - custom event with event.detail.project
	 */
	handleProjectSelect(event) {
		this.selectedProject = event.detail.project;
		this.showModal = true;
	}

	/** Closes the project detail modal and clears selection. */
	closeModal() {
		this.showModal = false;
		this.selectedProject = null;
	}

	/** Stops click propagation (e.g. to prevent closing modal when clicking inside). */
	stopClick(event) {
		event.stopPropagation();
	}

	/** Handles Escape key in modal to close it. */
	handleModalKeydown(event) {
		if (event.key === "Escape") {
			event.preventDefault();
			this.closeModal();
		}
	}
}