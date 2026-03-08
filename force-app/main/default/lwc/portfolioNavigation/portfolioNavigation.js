import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import PORTFOLIO_LOGOS from '@salesforce/resourceUrl/portfolioLogos';

// Static resource contains a subfolder named "portfolio logos" with the image files.
const LOGO_BASE = `${PORTFOLIO_LOGOS}/portfolio logos`;
const logoPath = (fileName) => `${LOGO_BASE}/${fileName}`;

/**
 * Portfolio Navigation Component
 * A WCAG 2.1 AA compliant navigation component for Experience Cloud sites.
 * 
 * Features:
 * - Semantic HTML structure with proper ARIA attributes
 * - Full keyboard navigation support (Arrow keys, Home, End, Escape)
 * - Responsive design with mobile hamburger menu
 * - Skip link for keyboard users
 * - Focus trap in mobile menu
 * - Proper focus management and visual indicators
 * - Screen reader announcements for state changes
 *
 * @author Liam Jeong
 * @date 2025-03-07
 */
export default class PortfolioNavigation extends NavigationMixin(LightningElement) {
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
                console.error('Portfolio Navigation: Invalid JSON for navigationItems', e);
                // Keep default items
            }
        } else if (Array.isArray(value)) {
            this._navigationItems = value;
        }
    }

    /**
     * Site/Brand name displayed in the navigation
     * @type {string}
     */
    @api brandName = 'Liam Jeong';

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

    @track isMobileMenuOpen = false;
    @track currentPath = '';
    @track focusedItemIndex = -1;

    // Screen reader live region announcement
    @track srAnnouncement = '';

    /**
     * Wire adapter to detect page navigation changes
     * This automatically updates when the page changes via NavigationMixin
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (pageRef) {
            // Update current path when page reference changes
            this.currentPath = this.getCurrentPath();
        }
    }

    /**
     * Lifecycle hook - Component connected to DOM
     */
    connectedCallback() {
        this.currentPath = this.getCurrentPath();
        this.handleResize = this.handleResize.bind(this);
        this.handlePopState = this.handlePopState.bind(this);
        window.addEventListener('resize', this.handleResize);
        window.addEventListener('popstate', this.handlePopState);
    }

    /**
     * Lifecycle hook - Component disconnected from DOM
     */
    disconnectedCallback() {
        window.removeEventListener('resize', this.handleResize);
        window.removeEventListener('popstate', this.handlePopState);
    }

    /**
     * Handle browser back/forward navigation
     */
    handlePopState() {
        this.currentPath = this.getCurrentPath();
    }

    /**
     * Get the current page path for active state
     * @returns {string} Current URL path
     */
    getCurrentPath() {
        const fullPath = window.location.pathname;
        // Remove base path to get relative path
        const relativePath = fullPath.replace(basePath, '');
        return relativePath || '/';
    }

    /**
     * Process navigation items with active state
     * @returns {Array} Navigation items with computed properties
     */
    get processedNavigationItems() {
        return this.navigationItems.map((item, index) => {
            const isActive = this.isActiveRoute(item.url);
            return {
                ...item,
                index,
                isActive,
                ariaCurrent: isActive ? 'page' : null,
                tabIndex: index === 0 ? '0' : '-1',
                itemClass: `nav-item${isActive ? ' nav-item--active' : ''}`
            };
        });
    }

    /**
     * Check if a route is currently active
     * @param {string} url - The URL to check
     * @returns {boolean} True if route is active
     */
    isActiveRoute(url) {
        if (url === '/') {
            return this.currentPath === '/' || this.currentPath === '';
        }
        return this.currentPath.startsWith(url);
    }

    /**
     * Get CSS class for mobile menu state
     * @returns {string} CSS classes for nav container
     */
    get navContainerClass() {
        return `nav-container${this.isMobileMenuOpen ? ' nav-container--open' : ''}`;
    }

    /**
     * Get CSS class for mobile menu button
     * @returns {string} CSS classes for hamburger button
     */
    get hamburgerClass() {
        return `hamburger${this.isMobileMenuOpen ? ' hamburger--active' : ''}`;
    }

    /**
     * Get aria-expanded value for mobile menu
     * @returns {string} 'true' or 'false'
     */
    get mobileMenuExpanded() {
        return this.isMobileMenuOpen ? 'true' : 'false';
    }

    /**
     * Get aria-hidden value for mobile menu
     * @returns {string} 'true' or 'false'
     */
    get mobileMenuHidden() {
        return this.isMobileMenuOpen ? 'false' : 'true';
    }

    /**
     * Handle window resize - close mobile menu on tablet/desktop
     * Uses matchMedia for consistency with CSS media queries
     */
    handleResize() {
        // Use matchMedia to match CSS breakpoint (48em)
        // This respects user font size preferences
        const isTabletOrLarger = window.matchMedia('(min-width: 48em)').matches;
        if (isTabletOrLarger && this.isMobileMenuOpen) {
            this.closeMobileMenu();
        }
    }

    /**
     * Toggle mobile menu open/closed
     * @param {Event} event - Click event
     */
    handleMobileMenuToggle(event) {
        event.preventDefault();
        this.isMobileMenuOpen = !this.isMobileMenuOpen;
        
        if (this.isMobileMenuOpen) {
            this.announceToScreenReader('Navigation menu opened');
            // Focus first menu item when opened
            requestAnimationFrame(() => {
                const firstItem = this.template.querySelector('.nav-list .nav-link');
                if (firstItem) {
                    firstItem.focus();
                }
            });
        } else {
            this.announceToScreenReader('Navigation menu closed');
            // Return focus to hamburger button
            const hamburger = this.template.querySelector('.hamburger');
            if (hamburger) {
                hamburger.focus();
            }
        }
    }

    /**
     * Close mobile menu
     */
    closeMobileMenu() {
        if (this.isMobileMenuOpen) {
            this.isMobileMenuOpen = false;
            this.announceToScreenReader('Navigation menu closed');
        }
    }

    /**
     * Handle navigation item click
     * @param {Event} event - Click event
     */
    handleNavClick(event) {
        event.preventDefault();
        const url = event.currentTarget.dataset.url;
        
        // Close mobile menu
        this.closeMobileMenu();
        
        // Navigate using NavigationMixin
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: basePath + url
            }
        });

        // Update current path for active state
        this.currentPath = url;
    }

    /**
     * Handle keyboard navigation within menu
     * Implements WCAG 2.1 keyboard patterns for navigation
     * @param {KeyboardEvent} event - Keyboard event
     */
    handleKeyDown(event) {
        const navLinks = this.template.querySelectorAll('.nav-link');
        const currentIndex = Array.from(navLinks).indexOf(event.target);

        switch (event.key) {
            case 'ArrowRight':
            case 'ArrowDown':
                event.preventDefault();
                this.focusNavItem(navLinks, currentIndex + 1);
                break;
            case 'ArrowLeft':
            case 'ArrowUp':
                event.preventDefault();
                this.focusNavItem(navLinks, currentIndex - 1);
                break;
            case 'Home':
                event.preventDefault();
                this.focusNavItem(navLinks, 0);
                break;
            case 'End':
                event.preventDefault();
                this.focusNavItem(navLinks, navLinks.length - 1);
                break;
            case 'Escape':
                if (this.isMobileMenuOpen) {
                    event.preventDefault();
                    this.closeMobileMenu();
                    const hamburger = this.template.querySelector('.hamburger');
                    if (hamburger) {
                        hamburger.focus();
                    }
                }
                break;
            case 'Tab':
                // Trap focus within mobile menu
                if (this.isMobileMenuOpen) {
                    this.handleTabTrap(event, navLinks);
                }
                break;
            default:
                break;
        }
    }

    /**
     * Focus a navigation item by index
     * @param {NodeList} navLinks - List of navigation links
     * @param {number} index - Index to focus
     */
    focusNavItem(navLinks, index) {
        const length = navLinks.length;
        // Wrap around
        const newIndex = ((index % length) + length) % length;
        navLinks[newIndex].focus();
    }

    /**
     * Handle tab key focus trapping in mobile menu
     * @param {KeyboardEvent} event - Keyboard event
     * @param {NodeList} navLinks - Navigation links
     */
    handleTabTrap(event, navLinks) {
        const hamburger = this.template.querySelector('.hamburger');
        const firstFocusable = navLinks[0];
        const lastFocusable = navLinks[navLinks.length - 1];

        if (event.shiftKey) {
            // Shift + Tab
            if (document.activeElement === firstFocusable || 
                event.target === firstFocusable) {
                event.preventDefault();
                hamburger.focus();
            }
        } else {
            // Tab
            if (document.activeElement === lastFocusable ||
                event.target === lastFocusable) {
                event.preventDefault();
                hamburger.focus();
            }
        }
    }

    /**
     * Handle skip link click - skip to main content
     * @param {Event} event - Click event
     */
    handleSkipToMain(event) {
        event.preventDefault();
        const mainContent = document.querySelector('main, [role="main"], .main-content');
        if (mainContent) {
            mainContent.setAttribute('tabindex', '-1');
            mainContent.focus();
            mainContent.removeAttribute('tabindex');
        }
    }

    /**
     * Handle brand/logo click - navigate to home
     * @param {Event} event - Click event
     */
    handleBrandClick(event) {
        event.preventDefault();
        this.closeMobileMenu();
        
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: basePath + '/'
            }
        });
        
        this.currentPath = '/';
    }

    /**
     * Announce message to screen readers via live region
     * @param {string} message - Message to announce
     */
    announceToScreenReader(message) {
        this.srAnnouncement = '';
        // Small delay to ensure the change is detected
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.srAnnouncement = message;
        }, 100);
    }

    /**
     * Check if logo URL is provided
     * @returns {boolean} True if logo URL exists
     */
    get hasLogo() {
        return !!this.logoUrl;
    }
}