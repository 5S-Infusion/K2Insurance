/**
 * @description Lead Form Capture LWC Component
 * Captures lead information and submits to Salesforce
 * Follows LWC best practices: reactive properties, wire service, error handling
 * @author Liam Jeong (liam.jeong@5sinfusion.com)
 * @date 2025-11-29
 */
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

// Apex methods
import createLead from '@salesforce/apex/LeadFormController.createLead';
import getGenderIdentityOptions from '@salesforce/apex/LeadFormController.getGenderIdentityOptions';
import getInterestedInsuranceOptions from '@salesforce/apex/LeadFormController.getInterestedInsuranceOptions';

// Static resource for logo (optional)
import K2_LOGO from '@salesforce/resourceUrl/K2Logo';

// Custom Labels
import LABEL_TITLE from '@salesforce/label/c.LeadFormCapture_Title';
import LABEL_FIRST_NAME from '@salesforce/label/c.LeadFormCapture_FirstName';
import LABEL_MIDDLE_NAME from '@salesforce/label/c.LeadFormCapture_MiddleName';
import LABEL_LAST_NAME from '@salesforce/label/c.LeadFormCapture_LastName';
import LABEL_FIRST_NAME_REQUIRED from '@salesforce/label/c.LeadFormCapture_FirstNameRequired';
import LABEL_LAST_NAME_REQUIRED from '@salesforce/label/c.LeadFormCapture_LastNameRequired';
import LABEL_COMPLETE_THIS_FIELD from '@salesforce/label/c.LeadFormCapture_CompleteThisField';
import LABEL_DOB from '@salesforce/label/c.LeadFormCapture_DOB';
import LABEL_GENDER_IDENTITY from '@salesforce/label/c.LeadFormCapture_GenderIdentity';
import LABEL_SELECT_GENDER_IDENTITY from '@salesforce/label/c.LeadFormCapture_SelectGenderIdentity';
import LABEL_GENDER_IDENTITY_REQUIRED from '@salesforce/label/c.LeadFormCapture_GenderIdentityRequired';
import LABEL_ADDRESS from '@salesforce/label/c.LeadFormCapture_Address';
import LABEL_STREET from '@salesforce/label/c.LeadFormCapture_Street';
import LABEL_CITY from '@salesforce/label/c.LeadFormCapture_City';
import LABEL_COUNTRY from '@salesforce/label/c.LeadFormCapture_Country';
import LABEL_STATE_PROVINCE from '@salesforce/label/c.LeadFormCapture_StateProvince';
import LABEL_POSTAL_CODE from '@salesforce/label/c.LeadFormCapture_PostalCode';
import LABEL_ADDRESS_REQUIRED from '@salesforce/label/c.LeadFormCapture_AddressRequired';
import LABEL_EMAIL from '@salesforce/label/c.LeadFormCapture_Email';
import LABEL_EMAIL_REQUIRED from '@salesforce/label/c.LeadFormCapture_EmailRequired';
import LABEL_EMAIL_INVALID from '@salesforce/label/c.LeadFormCapture_EmailInvalid';
import LABEL_PHONE from '@salesforce/label/c.LeadFormCapture_Phone';
import LABEL_PHONE_REQUIRED from '@salesforce/label/c.LeadFormCapture_PhoneRequired';
import LABEL_PHONE_INVALID from '@salesforce/label/c.LeadFormCapture_PhoneInvalid';
import LABEL_INSURANCE_QUESTION from '@salesforce/label/c.LeadFormCapture_InsuranceQuestion';
import LABEL_INSURANCE_HELP_TEXT from '@salesforce/label/c.LeadFormCapture_InsuranceHelpText';
import LABEL_AVAILABLE from '@salesforce/label/c.LeadFormCapture_Available';
import LABEL_SELECTED from '@salesforce/label/c.LeadFormCapture_Selected';
import LABEL_SUBMIT from '@salesforce/label/c.LeadFormCapture_Submit';
import LABEL_SUBMIT_TITLE from '@salesforce/label/c.LeadFormCapture_SubmitTitle';
import LABEL_SUBMITTING from '@salesforce/label/c.LeadFormCapture_Submitting';
import LABEL_SUCCESS from '@salesforce/label/c.LeadFormCapture_Success';
import LABEL_SUCCESS_MESSAGE from '@salesforce/label/c.LeadFormCapture_SuccessMessage';
import LABEL_VALIDATION_ERROR from '@salesforce/label/c.LeadFormCapture_ValidationError';
import LABEL_ERROR from '@salesforce/label/c.LeadFormCapture_Error';
import LABEL_LANGUAGE from '@salesforce/label/c.LeadFormCapture_Language';
import LABEL_THANK_YOU_TITLE from '@salesforce/label/c.LeadFormCapture_ThankYouTitle';
import LABEL_THANK_YOU_MESSAGE from '@salesforce/label/c.LeadFormCapture_ThankYouMessage';
import LABEL_SUBMIT_ANOTHER from '@salesforce/label/c.LeadFormCapture_SubmitAnother';
import LABEL_DUPLICATE_EMAIL from '@salesforce/label/c.LeadFormCapture_DuplicateEmail';
import LABEL_DOB_REQUIRED from '@salesforce/label/c.LeadFormCapture_DOBRequired';
import LABEL_INSURANCE_REQUIRED from '@salesforce/label/c.LeadFormCapture_InsuranceRequired';

// Country code options for phone input
const COUNTRY_CODE_OPTIONS = [
    { label: '🇺🇸 (+1)', value: '+1' },
    { label: '🇰🇷 (+82)', value: '+82' }
];

// Fallback Gender Identity options (for guest users without field access)
const GENDER_IDENTITY_OPTIONS_EN = [
    { label: 'Male', value: 'Male' },
    { label: 'Female', value: 'Female' }
];

const GENDER_IDENTITY_OPTIONS_KO = [
    { label: '남', value: 'Male' },
    { label: '여', value: 'Female' }
];

// Fallback Insurance options (for guest users without field access)
const INSURANCE_OPTIONS = [
    { label: 'Group Health', value: 'Group Health' },
    { label: 'Health', value: 'Health' },
    { label: 'Life', value: 'Life' },
    { label: 'Medicare', value: 'Medicare' },
    { label: 'Other', value: 'Other' }
];

// Language options
const LANGUAGE_OPTIONS_BASE = [
    { label: 'English', value: 'en' },
    { label: '한국어', value: 'ko' }
];

// Korean translations (for runtime language switching)
const KOREAN_LABELS = {
    title: '리드',
    firstName: '이름',
    middleName: '중간 이름',
    lastName: '성',
    firstNameRequired: '이름은 필수입니다',
    lastNameRequired: '성은 필수입니다',
    completeThisField: '이 필드를 작성하세요.',
    dob: '생년월일',
    dobRequired: '생년월일은 필수입니다',
    genderIdentity: '성별',
    selectGenderIdentity: '성별을 선택하세요',
    genderIdentityRequired: '성별은 필수입니다',
    address: '주소',
    street: '도로명',
    city: '도시',
    country: '국가',
    stateProvince: '시/도',
    postalCode: '우편번호',
    addressRequired: '주소는 필수입니다',
    email: '이메일',
    emailRequired: '이메일은 필수입니다',
    emailInvalid: '올바른 이메일 주소를 입력하세요',
    phone: '전화번호',
    phoneRequired: '전화번호는 필수입니다',
    phoneInvalid: '올바른 전화번호를 입력하세요',
    insuranceQuestion: '어떤 보험이 필요하신가요?',
    insuranceRequired: '하나 이상의 보험 상품을 선택해 주세요',
    insuranceHelpText: '왼쪽 목록(선택 가능)에서 원하는 보험 상품을 선택한 후, 화살표 버튼을 눌러 \'선택됨\' 박스로 이동시키고 제출을 클릭하여 선택을 저장하세요.',
    available: '선택 가능',
    selected: '선택됨',
    submit: '제출',
    submitTitle: '리드 양식 제출',
    submitting: '제출 중...',
    success: '성공',
    successMessage: '리드가 성공적으로 생성되었습니다!',
    validationError: '유효성 검사 오류',
    error: '오류',
    language: '언어',
    thankYouTitle: '감사합니다!',
    thankYouMessage: '정보가 성공적으로 제출되었습니다. 곧 연락드리겠습니다.',
    submitAnother: '다른 양식 제출',
    duplicateEmail: '이 이메일 주소는 이미 등록되어 있습니다. 다른 이메일을 사용하시거나 연락을 기다려 주세요.'
};

// English labels from Custom Labels
const ENGLISH_LABELS = {
    title: LABEL_TITLE,
    firstName: LABEL_FIRST_NAME,
    middleName: LABEL_MIDDLE_NAME,
    lastName: LABEL_LAST_NAME,
    firstNameRequired: LABEL_FIRST_NAME_REQUIRED,
    lastNameRequired: LABEL_LAST_NAME_REQUIRED,
    completeThisField: LABEL_COMPLETE_THIS_FIELD,
    dob: LABEL_DOB,
    dobRequired: LABEL_DOB_REQUIRED,
    genderIdentity: LABEL_GENDER_IDENTITY,
    selectGenderIdentity: LABEL_SELECT_GENDER_IDENTITY,
    genderIdentityRequired: LABEL_GENDER_IDENTITY_REQUIRED,
    address: LABEL_ADDRESS,
    street: LABEL_STREET,
    city: LABEL_CITY,
    country: LABEL_COUNTRY,
    stateProvince: LABEL_STATE_PROVINCE,
    postalCode: LABEL_POSTAL_CODE,
    addressRequired: LABEL_ADDRESS_REQUIRED,
    email: LABEL_EMAIL,
    emailRequired: LABEL_EMAIL_REQUIRED,
    emailInvalid: LABEL_EMAIL_INVALID,
    phone: LABEL_PHONE,
    phoneRequired: LABEL_PHONE_REQUIRED,
    phoneInvalid: LABEL_PHONE_INVALID,
    insuranceQuestion: LABEL_INSURANCE_QUESTION,
    insuranceRequired: LABEL_INSURANCE_REQUIRED,
    insuranceHelpText: LABEL_INSURANCE_HELP_TEXT,
    available: LABEL_AVAILABLE,
    selected: LABEL_SELECTED,
    submit: LABEL_SUBMIT,
    submitTitle: LABEL_SUBMIT_TITLE,
    submitting: LABEL_SUBMITTING,
    success: LABEL_SUCCESS,
    successMessage: LABEL_SUCCESS_MESSAGE,
    validationError: LABEL_VALIDATION_ERROR,
    error: LABEL_ERROR,
    language: LABEL_LANGUAGE,
    thankYouTitle: LABEL_THANK_YOU_TITLE,
    thankYouMessage: LABEL_THANK_YOU_MESSAGE,
    submitAnother: LABEL_SUBMIT_ANOTHER,
    duplicateEmail: LABEL_DUPLICATE_EMAIL
};

export default class LeadFormCapture extends NavigationMixin(LightningElement) {
    // Language state
    @track selectedLanguage = 'en';

    // Submission state
    @track showThankYou = false;

    // Get language options with computed variant
    get languageOptions() {
        return LANGUAGE_OPTIONS_BASE.map(lang => ({
            ...lang,
            variant: lang.value === this.selectedLanguage ? 'brand' : 'neutral'
        }));
    }

    // Get current labels based on selected language
    get labels() {
        return this.selectedLanguage === 'ko' ? KOREAN_LABELS : ENGLISH_LABELS;
    }

    // Get gender options based on selected language
    get genderOptions() {
        // If wire service returned options, translate labels based on language
        if (this._wireGenderOptions && this._wireGenderOptions.length > 0) {
            if (this.selectedLanguage === 'ko') {
                return this._wireGenderOptions.map(opt => ({
                    label: opt.value === 'Male' ? '남' : opt.value === 'Female' ? '여' : opt.label,
                    value: opt.value
                }));
            }
            return this._wireGenderOptions;
        }
        // Use fallback options based on language
        return this.selectedLanguage === 'ko' ? GENDER_IDENTITY_OPTIONS_KO : GENDER_IDENTITY_OPTIONS_EN;
    }

    // Computed property to show/hide form
    get showForm() {
        return !this.showThankYou;
    }

    // Form field values
    @track firstName = '';
    @track middleName = '';
    @track lastName = '';
    @track birthdate = '';
    @track genderIdentity = '';
    @track street = '';
    @track city = '';
    @track state = '';
    @track postalCode = '';
    @track country = 'United States';
    @track email = '';
    @track phone = '';
    @track countryCode = '+1';
    @track selectedInsurance = [];

    // UI state
    @track isSubmitting = false;
    @track _wireGenderOptions = [];  // Stores wire service gender options
    @track insuranceOptions = [];
    @track errorMessage = '';    // Inline error message
    @track successMessage = '';  // Inline success message

    // Static options
    countryCodeOptions = COUNTRY_CODE_OPTIONS;

    // Logo URL (will be undefined if resource doesn't exist)
    logoUrl = null;

    /**
     * Lifecycle hook - component initialization
     */
    connectedCallback() {
        try {
            this.logoUrl = K2_LOGO;
        } catch (e) {
            // Logo resource not found, continue without logo
            this.logoUrl = null;
        }

        // Detect browser language and set default
        this.detectBrowserLanguage();

        // Initialize with fallback options
        this.insuranceOptions = INSURANCE_OPTIONS;
        
        // Load insurance options from server (imperative call to avoid caching)
        this.loadInsuranceOptions();
    }

    /**
     * Detects browser language and sets default language
     */
    detectBrowserLanguage() {
        const browserLang = navigator.language || navigator.userLanguage;
        if (browserLang && browserLang.startsWith('ko')) {
            this.selectedLanguage = 'ko';
        }
    }

    /**
     * Language change handler
     * @param {Event} event - Click event from language button
     */
    handleLanguageChange(event) {
        const selectedLang = event.target.dataset.value;
        if (selectedLang) {
            this.selectedLanguage = selectedLang;
        }
    }

    /**
     * Wire service to get gender identity picklist options
     */
    @wire(getGenderIdentityOptions)
    wiredGenderOptions({ error, data }) {
        if (data && data.length > 0) {
            this._wireGenderOptions = data.map(option => ({
                label: option.label,
                value: option.value
            }));
        } else {
            // Clear wire options, getter will use fallback
            this._wireGenderOptions = [];
            if (error) {
                console.warn('Using fallback gender options:', error);
            }
        }
    }

    /**
     * Load interested insurance picklist options (imperative call to avoid caching)
     */
    loadInsuranceOptions() {
        getInterestedInsuranceOptions()
            .then(data => {
                if (data && data.length > 0) {
                    this.insuranceOptions = data.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                } else {
                    // Use fallback options for guest users
                    this.insuranceOptions = INSURANCE_OPTIONS;
                }
            })
            .catch(error => {
                // Use fallback options for guest users
                this.insuranceOptions = INSURANCE_OPTIONS;
                console.warn('Using fallback insurance options:', error);
            });
    }

    /**
     * Computed property for max date (today) for DOB field
     */
    get maxDate() {
        return new Date().toISOString().split('T')[0];
    }

    /**
     * Generic input change handler
     * @param {Event} event - Change event from input field
     */
    handleInputChange(event) {
        const { name, value } = event.target;
        
        switch (name) {
            case 'firstName':
                this.firstName = value;
                break;
            case 'middleName':
                this.middleName = value;
                break;
            case 'lastName':
                this.lastName = value;
                break;
            case 'birthdate':
                this.birthdate = value;
                break;
            case 'genderIdentity':
                this.genderIdentity = value;
                break;
            case 'email':
                this.email = value;
                break;
            case 'phone':
                this.phone = value;
                break;
            case 'countryCode':
                this.countryCode = value;
                break;
            default:
                break;
        }
    }

    /**
     * Address change handler
     * @param {Event} event - Change event from address input
     */
    handleAddressChange(event) {
        const { street, city, province, country, postalCode } = event.target;
        this.street = street || '';
        this.city = city || '';
        this.state = province || '';
        this.country = country || '';
        this.postalCode = postalCode || '';
    }

    /**
     * Insurance selection change handler
     * @param {Event} event - Change event from dual listbox
     */
    handleInsuranceChange(event) {
        this.selectedInsurance = event.detail.value;
    }

    /**
     * Form submission handler
     */
    async handleSubmit() {
        // Validate form
        if (!this.validateForm()) {
            console.log('Form validation failed');
            return;
        }

        this.isSubmitting = true;

        try {
            // Build form data object
            const formData = {
                firstName: this.firstName,
                middleName: this.middleName,
                lastName: this.lastName,
                birthdate: this.birthdate || null,
                genderIdentity: this.genderIdentity,
                street: this.street,
                city: this.city,
                state: this.state,
                postalCode: this.postalCode,
                country: this.country,
                email: this.email,
                phone: this.formatPhoneNumber(),
                interestedInsurance: this.selectedInsurance
            };

            console.log('Submitting form data:', JSON.stringify(formData));

            // Call Apex to create Lead
            const leadId = await createLead({ formDataJson: JSON.stringify(formData) });

            console.log('Lead created successfully:', leadId);

            // Show success message
            this.showToast(this.labels.success, this.labels.successMessage, 'success');

            // Reset form
            this.resetForm();

            // Show submission complete state
            this.showThankYou = true;

        } catch (error) {
            console.error('Error creating lead:', error);
            this.handleError(this.labels.error, error);
        } finally {
            this.isSubmitting = false;
        }
    }

    /**
     * Validates all form fields
     * @returns {Boolean} True if form is valid
     */
    validateForm() {
        // Get all input components
        const inputFields = this.template.querySelectorAll(
            'lightning-input, lightning-combobox, lightning-input-address'
        );

        let isValid = true;

        // Trigger validation on each field
        inputFields.forEach(field => {
            if (!field.reportValidity()) {
                isValid = false;
            }
        });

        // Additional custom validations
        if (!this.firstName?.trim()) {
            this.showToast(this.labels.validationError, this.labels.firstNameRequired, 'error');
            isValid = false;
        }

        if (!this.lastName?.trim()) {
            this.showToast(this.labels.validationError, this.labels.lastNameRequired, 'error');
            isValid = false;
        }

        if (!this.genderIdentity) {
            this.showToast(this.labels.validationError, this.labels.genderIdentityRequired, 'error');
            isValid = false;
        }

        if (!this.street?.trim() && !this.city?.trim()) {
            this.showToast(this.labels.validationError, this.labels.addressRequired, 'error');
            isValid = false;
        }

        return isValid;
    }

    /**
     * Formats phone number with country code
     * @returns {String} Formatted phone number
     */
    formatPhoneNumber() {
        if (!this.phone) {
            return '';
        }
        
        // Remove any existing country code prefix and format
        const cleanPhone = this.phone.replace(/[^\d]/g, '');
        
        return `${this.countryCode}${cleanPhone}`;
    }

    /**
     * Resets form to initial state
     */
    resetForm() {
        this.firstName = '';
        this.middleName = '';
        this.lastName = '';
        this.birthdate = '';
        this.genderIdentity = '';
        this.street = '';
        this.city = '';
        this.state = '';
        this.postalCode = '';
        this.country = 'United States';
        this.email = '';
        this.phone = '';
        this.countryCode = '+1';
        this.selectedInsurance = [];

        // Clear validation errors
        const inputFields = this.template.querySelectorAll(
            'lightning-input, lightning-combobox, lightning-input-address'
        );
        inputFields.forEach(field => {
            if (field.setCustomValidity) {
                field.setCustomValidity('');
            }
        });
    }

    /**
     * Handles click on "Submit Another Form" button
     */
    handleNewForm() {
        this.showThankYou = false;
        this.resetForm();
    }

    /**
     * Navigates to the created Lead record
     * @param {String} recordId - Lead record Id
     */
    navigateToRecord(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        });
    }

    /**
     * Shows notification (inline banner + toast fallback)
     * @param {String} title - Toast title
     * @param {String} message - Toast message
     * @param {String} variant - Toast variant (success, error, warning, info)
     */
    showToast(title, message, variant) {
        // Clear previous messages
        this.errorMessage = '';
        this.successMessage = '';

        // Set inline message based on variant
        if (variant === 'error') {
            this.errorMessage = message;
            // Auto-scroll to top to show error
            this.scrollToTop();
        } else if (variant === 'success') {
            this.successMessage = message;
            // Auto-clear success message after 5 seconds
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.successMessage = '';
            }, 5000);
        }

        // Also try toast (works in Lightning App, may not work in Experience Cloud)
        try {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: title,
                    message: message,
                    variant: variant,
                    mode: 'dismissable'
                })
            );
        } catch (e) {
            // Toast not supported in this context, inline message already shown
            console.log('Toast not supported, using inline message');
        }
    }

    /**
     * Clears the error message banner
     */
    clearError() {
        this.errorMessage = '';
    }

    /**
     * Scrolls to the top of the form to show error message
     */
    scrollToTop() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.template.querySelector('.form-container');
            if (container) {
                container.scrollIntoView({ behavior: 'smooth', block: 'start' });
            }
        }, 100);
    }

    /**
     * Handles and displays errors
     * @param {String} context - Error context description
     * @param {Object} error - Error object
     */
    handleError(context, error) {
        let message = this.labels.error;
        
        // Extract error message from various error formats
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.body?.pageErrors && error.body.pageErrors.length > 0) {
            message = error.body.pageErrors[0].message;
        } else if (error?.body?.fieldErrors) {
            const fieldErrors = Object.values(error.body.fieldErrors).flat();
            message = fieldErrors.map(e => e.message).join(', ');
        } else if (error?.message) {
            message = error.message;
        } else if (typeof error === 'string') {
            message = error;
        }
        
        console.error(`${context}:`, JSON.stringify(error));
        console.error('Error message:', message);
        
        // Map server error messages to user-friendly localized messages
        message = this.mapErrorToUserFriendlyMessage(message);
        
        this.showToast(this.labels.error, message, 'error');
    }

    /**
     * Maps server error messages to user-friendly localized messages
     * @param {String} serverMessage - Original error message from server
     * @returns {String} User-friendly localized message
     */
    mapErrorToUserFriendlyMessage(serverMessage) {
        const lowerMessage = serverMessage.toLowerCase();
        
        // Duplicate email check
        if (lowerMessage.includes('duplicate') || 
            lowerMessage.includes('already exists') ||
            lowerMessage.includes('existing record')) {
            return this.labels.duplicateEmail;
        }
        
        // Email validation errors
        if (lowerMessage.includes('valid email') || 
            lowerMessage.includes('email address') ||
            lowerMessage.includes('email is invalid') ||
            lowerMessage.includes('invalid email')) {
            return this.labels.emailInvalid;
        }
        
        // Email required
        if (lowerMessage.includes('email') && lowerMessage.includes('required')) {
            return this.labels.emailRequired;
        }
        
        // Phone validation errors
        if (lowerMessage.includes('valid phone') || 
            lowerMessage.includes('phone number') ||
            lowerMessage.includes('invalid phone')) {
            return this.labels.phoneInvalid;
        }
        
        // Phone required
        if (lowerMessage.includes('phone') && lowerMessage.includes('required')) {
            return this.labels.phoneRequired;
        }
        
        // First name required
        if (lowerMessage.includes('first name') && lowerMessage.includes('required')) {
            return this.labels.firstNameRequired;
        }
        
        // Last name required
        if (lowerMessage.includes('last name') && lowerMessage.includes('required')) {
            return this.labels.lastNameRequired;
        }
        
        // Gender identity required
        if (lowerMessage.includes('gender') && lowerMessage.includes('required')) {
            return this.labels.genderIdentityRequired;
        }
        
        // Address required
        if (lowerMessage.includes('address') && lowerMessage.includes('required')) {
            return this.labels.addressRequired;
        }
        
        // Form data errors
        if (lowerMessage.includes('form data') || lowerMessage.includes('invalid data')) {
            return this.selectedLanguage === 'ko' 
                ? '제출된 데이터가 올바르지 않습니다. 다시 시도해 주세요.'
                : 'Invalid form data. Please try again.';
        }
        
        // Generic server error
        if (lowerMessage.includes('server error') || lowerMessage.includes('unexpected')) {
            return this.selectedLanguage === 'ko'
                ? '일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.'
                : 'A temporary error occurred. Please try again shortly.';
        }
        
        // Return original message if no mapping found
        return serverMessage;
    }
}