import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import CERTIFICATION_LOGOS from '@salesforce/resourceUrl/SalesforceCertificationLogos';

/**
 * Portfolio Home Component
 * A WCAG 2.1 AA compliant home page component for Experience Cloud portfolio sites.
 * 
 * Features:
 * - Hero section with key stats
 * - Certifications showcase
 * - Differentiators highlighting unique strengths
 * - Testimonial carousel with keyboard navigation
 * - Quick navigation links
 *
 * @author Liam Jeong
 * @date 2025-03-07
 */
export default class PortfolioHome extends NavigationMixin(LightningElement) {
    // ========================================
    // API Properties (Configurable via Builder)
    // ========================================
    
    /**
     * Name displayed in hero section
     * @type {string}
     */
    @api name = 'Liam Jeong';

    /**
     * Professional title
     * @type {string}
     */
    @api title = 'Senior Salesforce Developer & Engineer';

    /**
     * Brief tagline/objective
     * @type {string}
     */
    @api tagline = 'Salesforce professional with 8 years in development and consulting, experienced in building scalable architectures, modernizing legacy systems, and leading cross-functional delivery.';

    /**
     * Years of Salesforce experience
     * @type {number}
     */
    @api yearsExperience = 8;

    /**
     * Number of active certifications
     * @type {number}
     */
    @api certificationCount = 7;

    /**
     * Trailhead profile URL for certifications link
     * @type {string}
     */
    @api trailheadUrl = '';

    // ========================================
    // Tracked Properties
    // ========================================
    
    /**
     * Current testimonial index for carousel
     * @type {number}
     */
    @track currentTestimonialIndex = 0;

    // ========================================
    // Certifications Data
    // ========================================
    
    /**
     * Salesforce certifications list with logo URLs
     * @returns {Array} Certification objects
     */
    get certifications() {
        const logoFolder = `${CERTIFICATION_LOGOS}/Salesforce Certification Logos`;
        const certs = [
            {
                id: 'cert-1',
                name: 'Agentforce Specialist',
                date: 'October 2025',
                isNew: true,
                logo: `${logoFolder}/Agentforce-Specialist_High-Res.png`
            },
            {
                id: 'cert-2',
                name: 'OmniStudio Consultant',
                date: 'September 2024',
                isNew: false,
                logo: `${logoFolder}/Omnistudio-Consultant_High-Res.png`
            },
            {
                id: 'cert-3',
                name: 'OmniStudio Developer',
                date: 'March 2021',
                isNew: false,
                logo: `${logoFolder}/Omnistudio-Developer_High-Res.png`
            },
            {
                id: 'cert-4',
                name: 'JavaScript Developer 1',
                date: 'July 2020',
                isNew: false,
                logo: `${logoFolder}/JavaScript-Developer_High-Res.png`
            },
            {
                id: 'cert-5',
                name: 'Administrator',
                date: 'May 2020',
                isNew: false,
                logo: `${logoFolder}/Platform-Administrator_High-Res.png`
            },
            {
                id: 'cert-6',
                name: 'Platform App Builder',
                date: 'May 2020',
                isNew: false,
                logo: `${logoFolder}/Platform-App-Builder_High-Res.png`
            },
            {
                id: 'cert-7',
                name: 'Platform Developer 1',
                date: 'February 2020',
                isNew: false,
                logo: `${logoFolder}/Platform_Developer1_High-Res.png`
            }
        ];
        
        // Add aria labels for accessibility
        return certs.map(cert => ({
            ...cert,
            ariaLabel: this.hasTrailheadUrl 
                ? `${cert.name}, earned ${cert.date}. Click to view on Trailhead.`
                : `${cert.name}, earned ${cert.date}`
        }));
    }

    /**
     * CSS class for cert grid (adds clickable modifier when trailhead URL exists)
     */
    get certGridClass() {
        return `cert-grid${this.hasTrailheadUrl ? ' cert-grid--clickable' : ''}`;
    }

    /**
     * CSS class for cert cards (adds clickable modifier when trailhead URL exists)
     */
    get certCardClass() {
        return `cert-card${this.hasTrailheadUrl ? ' cert-card--clickable' : ''}`;
    }

    /**
     * Role attribute for cert cards (button when clickable)
     */
    get certCardRole() {
        return this.hasTrailheadUrl ? 'button' : null;
    }

    /**
     * Tabindex for cert cards (focusable when clickable)
     */
    get certCardTabIndex() {
        return this.hasTrailheadUrl ? '0' : null;
    }

    /**
     * Handle certification card click - opens Trailhead
     */
    handleCertClick() {
        if (this.trailheadUrl) {
            window.open(this.trailheadUrl, '_blank', 'noopener,noreferrer');
        }
    }

    // ========================================
    // Differentiators Data
    // ========================================
    
    /**
     * Key differentiators/strengths
     * @returns {Array} Differentiator objects
     */
    get differentiators() {
        return [
            {
                id: 'diff-1',
                icon: 'utility:display_rich_text',
                title: 'Front-End Excellence',
                description: 'Recognized as "one of the best front-end developers" with exceptional expertise in Lightning Web Components, CSS, and responsive design implementation.'
            },
            {
                id: 'diff-2',
                icon: 'utility:touch_action',
                title: 'Accessibility Champion',
                description: 'Sincere commitment to WCAG standards, ensuring websites are usable by all populations. Dedication to web accessibility that is both inspiring and impactful.'
            },
            {
                id: 'diff-3',
                icon: 'utility:strategy',
                title: 'Architectural Thinking',
                description: 'Deep Salesforce development and architectural expertise. Design solutions that are scalable, testable, and maintainable with clean, well-documented code.'
            },
            {
                id: 'diff-4',
                icon: 'utility:groups',
                title: 'Technical Leadership',
                description: 'Development Lead experience with ability to grasp business requirements and translate them into scalable, efficient solutions. Calm and solutions-oriented in high-pressure situations.'
            }
        ];
    }

    // ========================================
    // Testimonials Data
    // ========================================
    
    /**
     * Testimonials from colleagues
     * @returns {Array} Testimonial objects with computed initials
     */
    get testimonials() {
        const testimonialsData = [
            {
                id: 'test-1',
                name: 'Natalie Moey',
                title: 'Senior Product Design Lead (UX/UI)',
                company: 'Deloitte',
                quote: 'His technical expertise was exceptional - he was easily one of the best front-end developers I\'ve worked with, combining strong implementation skills with a deep understanding of how to bring designs to life accurately and efficiently.'
            },
            {
                id: 'test-2',
                name: 'John Gruenbacher',
                title: 'Senior Manager',
                company: 'Deloitte Consulting',
                quote: 'Liam\'s expertise in developing responsive Lightning Web Components (LWC) was exceptional. He demonstrated a sincere commitment to web accessibility, prioritizing WCAG standards to ensure our websites were usable by all populations.'
            },
            {
                id: 'test-3',
                name: 'Nicholas Melcher',
                title: 'Senior Consultant | Salesforce Certified Admin/BA',
                company: 'Deloitte',
                quote: 'He is one of the most skilled and reliable Salesforce developers I\'ve encountered. What sets Liam apart is his ability to not only understand the technical side of development, but also to grasp business requirements and translate them into scalable, efficient solutions.'
            },
            {
                id: 'test-4',
                name: 'Amechi McZeal',
                title: 'Dev Ops Engineer',
                company: 'AAA',
                quote: 'From day one, it was clear he brought deep Salesforce development and architectural expertise, along with a strong sense of integrity and genuine care for the quality of the product. In high-pressure situations, he stayed calm, solutions-oriented, and always willing to jump in to debug issues.'
            },
            {
                id: 'test-5',
                name: 'Akosa Okwudiafor',
                title: 'Salesforce Application Architect / Consultant',
                company: 'Deloitte',
                quote: 'I worked with Liam as his development lead over the last 6 months, and I cannot recommend him enough for the work done. He demonstrated several moments of selflessness and thinking outside the box by ensuring the components and utilities he built could be used by other people on the team.'
            },
            {
                id: 'test-6',
                name: 'Nauman Husnani',
                title: 'Salesforce Application Management',
                company: 'Voya Financial',
                quote: 'Liam is one of those rare individuals who you\'re glad you know. He\'s an excellent resource on a whole range of topics and is always more than willing to help. What\'s also great about Liam is that although his technical proficiency is higher than most, he\'s able to take a step back and see the gaps in his understanding. This humility is great to see.'
            }
        ];

        return testimonialsData.map(t => ({
            ...t,
            initials: this.getInitials(t.name)
        }));
    }

    /**
     * Get initials from a name
     * @param {string} name - Full name
     * @returns {string} Initials (first two letters of first and last name)
     */
    getInitials(name) {
        const parts = name.split(' ');
        if (parts.length >= 2) {
            return parts[0][0] + parts[parts.length - 1][0];
        }
        return name.substring(0, 2).toUpperCase();
    }

    // ========================================
    // Carousel Logic
    // ========================================
    
    /**
     * Calculate testimonial track transform style
     * @returns {string} CSS transform value
     */
    get testimonialTrackStyle() {
        return `transform: translateX(-${this.currentTestimonialIndex * 100}%)`;
    }

    /**
     * Generate dot indicators for carousel
     * @returns {Array} Dot objects with state
     */
    get testimonialDots() {
        return this.testimonials.map((_, index) => ({
            index,
            isActive: index === this.currentTestimonialIndex,
            class: `carousel-dot ${index === this.currentTestimonialIndex ? 'carousel-dot--active' : ''}`,
            label: `Go to testimonial ${index + 1} of ${this.testimonials.length}`
        }));
    }

    /**
     * Check if previous button should be disabled
     * @returns {boolean} True if at first testimonial
     */
    get isPrevDisabled() {
        return this.currentTestimonialIndex === 0;
    }

    /**
     * Check if next button should be disabled
     * @returns {boolean} True if at last testimonial
     */
    get isNextDisabled() {
        return this.currentTestimonialIndex === this.testimonials.length - 1;
    }

    /**
     * Navigate to previous testimonial
     */
    handlePrevTestimonial() {
        if (this.currentTestimonialIndex > 0) {
            this.currentTestimonialIndex--;
        }
    }

    /**
     * Navigate to next testimonial
     */
    handleNextTestimonial() {
        if (this.currentTestimonialIndex < this.testimonials.length - 1) {
            this.currentTestimonialIndex++;
        }
    }

    /**
     * Handle dot click navigation
     * @param {Event} event - Click event
     */
    handleDotClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (!isNaN(index)) {
            this.currentTestimonialIndex = index;
        }
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
            type: 'standard__webPage',
            attributes: {
                url: basePath + url
            }
        });
    }

    // ========================================
    // Trailhead Link
    // ========================================

    /**
     * Check if Trailhead URL is provided
     * @returns {boolean} True if trailheadUrl exists
     */
    get hasTrailheadUrl() {
        return !!this.trailheadUrl;
    }
}