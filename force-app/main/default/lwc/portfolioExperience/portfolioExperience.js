import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import basePath from "@salesforce/community/basePath";
import PORTFOLIO_LOGOS from "@salesforce/resourceUrl/portfolioLogos";

// Static resource contains a subfolder named "portfolio logos" with the image files.
const LOGO_BASE = `${PORTFOLIO_LOGOS}/portfolio logos`;
const logoPath = (fileName) => `${LOGO_BASE}/${fileName}`;

/**
 * Portfolio Experience Component
 * A WCAG 2.1 AA compliant professional experience page component for Experience Cloud portfolio sites.
 *
 * Features:
 * - Professional experience timeline
 * - Role and responsibility showcase
 * - Skills and achievements display
 * - Responsive card layouts
 *
 * @author Liam Jeong
 * @date 2025-03-07
 */
export default class PortfolioExperience extends NavigationMixin(
	LightningElement
) {
	// ========================================
	// API Properties (Configurable via Builder)
	// ========================================

	/**
	 * LinkedIn profile URL
	 * @type {string}
	 */
	@api linkedInProfileUrl =
		"https://www.linkedin.com/in/liam-jeong-b009b2189/";

	// ========================================
	// Logo URLs from Static Resource
	// ========================================

	get logoAAA() {
		return logoPath("Logo AAA.png");
	}

	get logoDeloitte() {
		return logoPath("Logo Deloitte.png");
	}

	get logoRevolent() {
		return logoPath("Logo Revolent.png");
	}

	get logoDirectTrucking() {
		return logoPath("Logo Direct Trucking.jpeg");
	}

	get logoRoKArmy() {
		return logoPath("Logo RoK Army.png");
	}

	// ========================================
	// Professional Experience Data
	// ========================================

	/**
	 * Professional experience history
	 * @returns {Array} Experience objects
	 */
	get professionalExperience() {
		return [
			{
				id: "exp-1",
				company: "AAA Auto Club Enterprises",
				companyUrl: "https://www.ace.aaa.com",
				companyLinkLabel:
					"Visit AAA Auto Club Enterprises website (opens in new tab)",
				role: "Senior DevOps Engineer",
				employmentType: "Full-time",
				location: "Coppell, Texas, United States · Remote",
				startDate: "Jun 2025",
				endDate: "Nov 2025",
				isCurrent: false,
				logoUrl: this.logoAAA,
				logoInitials: "AAA",
				description:
					"Led end-to-end Salesforce engineering and DevOps initiatives across mission-critical platforms supporting roadside service, agent operations, and enterprise applications.",
				responsibilities: [
					"Designed and developed scalable Apex and Lightning Web Components for ERS (Emergency Road Service) applications",
					"Built exception handling patterns and centralized error management framework",
					"Optimized CI/CD pipelines with Gearset and GitHub, managing multi-sandbox environment strategies",
					"Implemented and reviewed custom Agentforce prompts, topics, and actions to streamline field service operations",
				],
				achievements: [
					"Architected a redesigned Mapping API platform using Apex, LWC, Visualforce (CSP), and dynamic configuration, improving reliability and reducing API failure rates",
					"Rebuilt the CI/CD pipeline using Gearset and GitHub, establishing a structured branching model that increased deployment success",
					"Implemented a centralized exception framework (Platform Event & Queueable Apex + LWC async), enabling automated case creation and improving root-cause traceability",
					"Built tailored Lightning components for Service Appointment lists, enabling agents to pick up incoming calls and assign jobs directly to drivers in real time",
				],
				skills: [
					"Lightning Web Components",
					"Visualforce",
					"Agentforce",
					"Apex",
					"CI/CD",
					"Gearset",
					"Exception handling Framework",
					"Platform Events",
				],
			},
			{
				id: "exp-2",
				company: "Deloitte",
				companyUrl: "https://www.deloitte.com",
				companyLinkLabel: "Visit Deloitte website (opens in new tab)",
				role: "Solutions Specialist | Senior Salesforce Developer",
				employmentType: "Full-time",
				location: "United States · Remote",
				startDate: "Jul 2022",
				endDate: "Jun 2025",
				isCurrent: false,
				logoUrl: this.logoDeloitte,
				logoInitials: "D",
				description:
					"Delivered Salesforce solutions for enterprise and public-sector clients, specializing in LWC, OmniStudio, and large-scale complex automation.",
				responsibilities: [
					"Developed responsive, accessible Lightning Web Components using SLDS for modernization projects",
					"Built OmniStudio POC components and authored Technical Design Documents (TDDs)",
					"Led onshore development teams and mentored junior developers",
					"Conducted in-depth code reviews for offshore teams, ensuring adherence to Salesforce security and best practices",
				],
				achievements: [
					"WI AMP: Designed and built modern LWC using SLDS to improve UI responsiveness, accessibility, and usability across high-traffic internal applications and Experience Cloud pages",
					"CA DMV: Authored technical design documents and delivered proof-of-concept OmniStudio and LWC components to validate feasibility and drive architectural decisions",
					"OH MMCP: Led the onshore development team and owned end-to-end solution delivery across Apex, Flows, and Lightning components for Medicaid modernization",
					"BCBST: Supported go-live and hypercare for a major Salesforce deployment using OmniScript and Platform Events for event-driven processing",
					"USDA: Designed and implemented automated permission-provisioning flows enforcing Salesforce security best practices",
					"MD CCS: Developed and optimized OmniScripts, FlexCards, and Integration Procedures to automate child care scholarship workflows",
				],
				skills: [
					"Lightning Web Components",
					"OmniStudio",
					"Flow Orchestration",
					"Apex",
					"Experience Cloud",
					"Integration Procedures",
				],
			},
			{
				id: "exp-3",
				company: "Revolent Group",
				companyUrl: "https://www.revolent.com",
				companyLinkLabel:
					"Visit Revolent Group website (opens in new tab)",
				role: "Salesforce Developer | contractor @ Publicis Sapient",
				employmentType: "Full-time",
				location: "North Carolina, United States · Remote",
				startDate: "Jul 2020",
				endDate: "Jun 2022",
				isCurrent: false,
				logoUrl: this.logoRevolent,
				logoInitials: "R",
				description:
					"Delivered core Salesforce solutions for the NC ReBUILD public sector modernization initiative, focusing on system scalability, automation reliability, and compliance.",
				responsibilities: [
					"Led the conversion of legacy Process Builder automations into Record-Triggered Flows",
					"Built complex programmatic components including Apex, Batch Apex, Future methods, and Triggers",
					"Supported high-volume document and ContentVersion processing across state agency workflows",
					"Collaborated with BAs, QAs, and program stakeholders to reduce technical debt and ensure compliant delivery",
				],
				achievements: [
					"Transformed legacy Process Builder and Workflow automations into scalable, maintainable Flows",
					"Designed a high-throughput Batch Apex framework that significantly improved document ingestion speed and data integrity",
					"Built Batch Apex for high-volume approval operations in a public-sector environment",
				],
				skills: [
					"Apex",
					"Schedulable Apex",
					"Batch Apex",
					"Flows",
					"Process Builder",
					"Process Automation",
					"SOQL",
				],
			},
			{
				id: "exp-4",
				company: "Direct Trucking Corp",
				companyUrl: null,
				companyLinkLabel: null,
				role: "Software Engineer",
				employmentType: "Full-time",
				location: "Greater Chicago Area · On-site",
				startDate: "Dec 2016",
				endDate: "Jun 2019",
				isCurrent: false,
				logoUrl: this.logoDirectTrucking,
				logoInitials: "DT",
				description:
					"Served as the primary Salesforce Administrator while supporting internal software development needs. Built internal applications to automate billing and reporting, reducing manual workload and strengthening operational efficiency.",
				responsibilities: [
					"Developed core operational applications using VB.NET with MSSQL and MongoDB for dispatching, billing, and logistics workflows",
					"Built single-page web tools with HTML5, JavaScript, jQuery, AJAX, and PHP to automate billing and reporting",
					"Implemented AWS S3 storage solutions for customer signatures, time logs, and operational documents",
					"Managed Salesforce administration including user setup, configuration updates, reporting, and day-to-day system support",
				],
				achievements: [
					"Automated billing and reporting processes, significantly reducing manual workload",
					"Improved data accessibility through AWS S3 storage implementation",
					"Configured profiles, roles, permission sets, and validation rules to improve data accuracy and streamline daily operations",
				],
				skills: [
					"Salesforce Administration",
					"VB.NET",
					"MSSQL",
					"MongoDB",
					"HTML5",
					"Bootstrap",
					"jQuery",
					"JavaScript",
					"AWS S3",
				],
			},
			{
				id: "exp-5",
				company: "Codingpia",
				companyUrl: null,
				companyLinkLabel: null,
				role: "Software Programming Instructor",
				employmentType: "Part-time",
				location: "Seoul, South Korea · On-site",
				startDate: "Mar 2014",
				endDate: "Nov 2016",
				isCurrent: false,
				logoUrl: null,
				logoInitials: "CP",
				description:
					"Taught C++, object-oriented programming principles, and core software development lifecycle concepts to high school and college students.",
				responsibilities: [
					"Designed and delivered curriculum covering software design patterns, data structures, and clean coding practices",
					"Reinforced concepts through hands-on projects and algorithmic exercises",
					"Mentored students through code reviews, debugging sessions, and project development",
					"Helped students build strong foundational skills for advanced computer science coursework",
				],
				achievements: [
					"Successfully trained multiple cohorts of students in programming fundamentals",
					"Developed comprehensive curriculum materials for C++ and OOP courses",
					"Prepared students for real-world engineering environments and advanced coursework",
				],
				skills: [
					"C++",
					"Object-Oriented Programming",
					"Data Structures",
					"Algorithms",
					"Curriculum Design",
					"Mentoring",
				],
			},
			{
				id: "exp-6",
				company: "Republic of Korea Army",
				companyUrl: null,
				companyLinkLabel: null,
				role: "Sergeant",
				employmentType: "Full-time",
				location: "Chuncheon, Gangwon, South Korea · On-site",
				startDate: "Aug 2009",
				endDate: "Jul 2011",
				isCurrent: false,
				logoUrl: this.logoRoKArmy,
				logoInitials: "ROK",
				description:
					"Led and supervised a team of soldiers, providing training and guidance to ensure operational readiness and strict adherence to military standards and protocols.",
				responsibilities: [
					"Oversaw logistics management, including allocation, maintenance, and distribution of critical equipment and resources",
					"Worked closely with senior leadership to uphold discipline and maintain high morale",
					"Ensured seamless execution of drills, exercises, and strategic operations",
					"Provided training and guidance to team members for operational readiness",
				],
				achievements: [
					"Successfully led and supervised a team of soldiers",
					"Contributed to the overall efficiency of unit operations through effective logistics management",
					"Maintained high team morale and discipline throughout service",
				],
				skills: ["Leadership", "Team Management"],
			},
		];
	}

	/**
	 * Calculate total years of experience
	 * @returns {number} Years of experience
	 */
	get yearsOfExperience() {
		const startYear = 2014;
		const currentYear = new Date().getFullYear();
		return currentYear - startYear;
	}

	/**
	 * Get experience statistics
	 * @returns {Array} Statistics objects
	 */
	get experienceStats() {
		return [
			{
				id: "stat-1",
				value: `${this.yearsOfExperience}+`,
				label: "Years Experience",
				icon: "calendar",
			},
			{
				id: "stat-2",
				value: "6",
				label: "Companies",
				icon: "building",
			},
			{
				id: "stat-3",
				value: "20+",
				label: "Projects Delivered",
				icon: "project",
			},
			{
				id: "stat-4",
				value: "8",
				label: "Certifications",
				icon: "badge",
			},
		];
	}

	// ========================================
	// Navigation
	// ========================================

	/**
	 * Handle navigation link clicks
	 * @param {Event} event - Click event
	 */
	handleNavigation(event) {
		event.preventDefault();
		const url = event.currentTarget.dataset.url;

		this[NavigationMixin.Navigate]({
			type: "standard__webPage",
			attributes: {
				url: basePath + url,
			},
		});
	}
}