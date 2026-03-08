import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import PORTFOLIO_LOGOS from '@salesforce/resourceUrl/portfolioLogos';

// Static resource contains a subfolder named "portfolio logos" with the image files.
const LOGO_BASE = `${PORTFOLIO_LOGOS}/portfolio logos`;
const logoPath = (fileName) => `${LOGO_BASE}/${fileName}`;

/**
 * Portfolio Footer Component
 * A WCAG 2.1 AA compliant footer component for Experience Cloud sites.
 * 
 * Features:
 * - Semantic HTML structure with proper ARIA attributes
 * - Configurable brand, contact, and social information
 * - Quick navigation links matching header
 * - Accessible focus indicators and touch targets
 * - Responsive grid layout
 * - Keyboard accessible
 *
 * @author Liam Jeong
 * @date 2025-03-07
 */
export default class PortfolioFooter extends NavigationMixin(LightningElement) {
    /**
     * Navigation items to display (can be JSON string or Array)
     * @type {string|Array<{id: string, label: string, url: string}>}
     */
    _navigationItems = [
        { id: 'home', label: 'Home', url: '/' },
        { id: 'experience', label: 'Experience', url: '/experience' },
        { id: 'projects', label: 'Projects', url: '/projects' },
        { id: 'education', label: 'Education', url: '/education' },
        { id: 'contact', label: 'Contact', url: '/contact' }
    ];

    @api
    get navigationItems() {
        return this._navigationItems;
    }

    set navigationItems(value) {
        if (typeof value === 'string') {
            try {
                this._navigationItems = JSON.parse(value);
            } catch (e) {
                console.error('Portfolio Footer: Invalid JSON for navigationItems', e);
            }
        } else if (Array.isArray(value)) {
            this._navigationItems = value;
        }
    }

    /**
     * Site/Brand name displayed in the footer
     * @type {string}
     */
    @api brandName = 'Liam Jeong';

    /**
     * Tagline or description below the brand
     * @type {string}
     */
    @api tagline = 'Salesforce Developer & Architect building innovative solutions on the Salesforce platform.';

    /**
     * Logo URL from static resource
     * @type {string}
     */
    logoUrl = logoPath('LJ Logo(Blue).png');

    /**
     * Logo alt text for accessibility
     * @type {string}
     */
    logoAltText = 'Liam Jeong - Home';

    /**
     * Email address for contact
     * @type {string}
     */
    @api email = '';

    /**
     * Location text to display
     * @type {string}
     */
    @api location = '';

    /**
     * LinkedIn profile URL
     * @type {string}
     */
    @api linkedInUrl = '';

    /**
     * GitHub profile URL
     * @type {string}
     */
    @api githubUrl = '';

    /**
     * Trailhead profile URL
     * @type {string}
     */
    @api trailheadUrl = '';

    /**
     * Current path for navigation state
     */
    @track currentPath = '';

    /**
     * Lifecycle hook - Component connected to DOM
     */
    connectedCallback() {
        this.currentPath = this.getCurrentPath();
    }

    /**
     * Get the current page path
     * @returns {string} Current URL path
     */
    getCurrentPath() {
        const fullPath = window.location.pathname;
        const relativePath = fullPath.replace(basePath, '');
        return relativePath || '/';
    }

    /**
     * Process navigation items for display
     * @returns {Array} Navigation items with computed properties
     */
    get processedNavigationItems() {
        return this.navigationItems.map((item, index) => ({
            ...item,
            index
        }));
    }

    /**
     * Get current year for copyright
     * @returns {number} Current year
     */
    get currentYear() {
        return new Date().getFullYear();
    }

    /**
     * Check if logo URL is provided
     * @returns {boolean} True if logo URL exists
     */
    get hasLogo() {
        return !!this.logoUrl;
    }

    /**
     * Generate mailto link for email
     * @returns {string} mailto: link
     */
    get emailLink() {
        return this.email ? `mailto:${this.email}` : '';
    }

    /**
     * Handle navigation item click
     * @param {Event} event - Click event
     */
    handleNavClick(event) {
        event.preventDefault();
        const url = event.currentTarget.dataset.url;
        
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: basePath + url
            }
        });

        this.currentPath = url;
    }

    /**
     * Handle brand/logo click - navigate to home
     * @param {Event} event - Click event
     */
    handleBrandClick(event) {
        event.preventDefault();
        
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: basePath + '/'
            }
        });
        
        this.currentPath = '/';
    }
}