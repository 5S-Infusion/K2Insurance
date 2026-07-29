import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/ldsUtils';
import getEmployees from '@salesforce/apex/EmployeeRosterController.getEmployees';
import getFieldOptions from '@salesforce/apex/EmployeeRosterController.getFieldOptions';
import offboardEmployee from '@salesforce/apex/EmployeeRosterController.offboardEmployee';
import saveRelationships from '@salesforce/apex/EmployeeRosterController.saveRelationshipsJson';

import LBL_TITLE from '@salesforce/label/c.EmployeeRoster_Title';
import LBL_COL_NAME from '@salesforce/label/c.EmployeeRoster_ColName';
import LBL_COL_COMPANY from '@salesforce/label/c.EmployeeRoster_ColCompany';
import LBL_COL_EMP_STATUS from '@salesforce/label/c.EmployeeRoster_ColEmpStatus';
import LBL_COL_ROLES from '@salesforce/label/c.EmployeeRoster_ColRoles';
import LBL_COL_PLANS from '@salesforce/label/c.EmployeeRoster_ColPlans';
import LBL_COL_FAMILY from '@salesforce/label/c.EmployeeRoster_ColFamily';
import LBL_COL_ACTIVE_INS from '@salesforce/label/c.EmployeeRoster_ColActiveIns';
import LBL_OFFBOARD from '@salesforce/label/c.EmployeeRoster_Offboard';
import LBL_NO_EMPLOYEES from '@salesforce/label/c.EmployeeRoster_NoEmployees';
import LBL_LOAD_ERROR from '@salesforce/label/c.EmployeeRoster_LoadError';
import LBL_OFFBOARD_BODY from '@salesforce/label/c.EmployeeRoster_OffboardBody';
import LBL_END_DATE from '@salesforce/label/c.EmployeeRoster_EndDateLabel';
import LBL_CANCEL from '@salesforce/label/c.EmployeeRoster_Cancel';
import LBL_SAVE from '@salesforce/label/c.EmployeeRoster_Save';
import LBL_SAVE_SUCCESS from '@salesforce/label/c.EmployeeRoster_SaveSuccess';
import LBL_ROLES_PLACEHOLDER from '@salesforce/label/c.EmployeeRoster_RolesPlaceholder';
import LBL_FAMILY_PLACEHOLDER from '@salesforce/label/c.EmployeeRoster_FamilyPlaceholder';
import LBL_OPEN_RELATIONSHIP from '@salesforce/label/c.EmployeeRoster_OpenRelationship';
import LBL_ACTIVE from '@salesforce/label/c.EmployeeRoster_Active';
import LBL_INACTIVE from '@salesforce/label/c.EmployeeRoster_Inactive';
import LBL_PLAN_MEDICAL from '@salesforce/label/c.EmployeeRoster_PlanMedical';
import LBL_PLAN_DENTAL from '@salesforce/label/c.EmployeeRoster_PlanDental';
import LBL_PLAN_VISION from '@salesforce/label/c.EmployeeRoster_PlanVision';

/** @description Coverage-tier code → badge tooltip and color class, for the Plans column. */
const PLAN_META = {
    M: { title: LBL_PLAN_MEDICAL, cssClass: 'plan-badge plan-m' },
    D: { title: LBL_PLAN_DENTAL, cssClass: 'plan-badge plan-d' },
    V: { title: LBL_PLAN_VISION, cssClass: 'plan-badge plan-v' }
};

/** @description Minimum column width (px) enforced while dragging a resize handle. */
const MIN_COLUMN_WIDTH = 60;

/**
 * @description The reorderable columns, in their default left-to-right order. `labelKey` points at
 * an entry of the component's `label` map and `colClass` carries the column's default width. The
 * trailing actions column (open-relationship + Offboard) is not listed here — it is rendered
 * separately and stays pinned to the right edge.
 */
const COLUMN_DEFS = [
    { field: 'name', labelKey: 'colName', colClass: '' },
    { field: 'company', labelKey: 'colCompany', colClass: '' },
    { field: 'empStatus', labelKey: 'colEmpStatus', colClass: 'col-status' },
    { field: 'roles', labelKey: 'colRoles', colClass: '' },
    { field: 'plans', labelKey: 'colPlans', colClass: 'col-plans' },
    { field: 'family', labelKey: 'colFamily', colClass: '' },
    { field: 'activeIns', labelKey: 'colActiveIns', colClass: 'col-activeins' }
];

const COLUMN_BY_FIELD = COLUMN_DEFS.reduce((map, def) => Object.assign(map, { [def.field]: def }), {});

/** @description Header classes marking the column a drop would land before/after. */
const DROP_MARKERS = ['roster-drop-before', 'roster-drop-after'];
import LBL_NEW_CONTACT from '@salesforce/label/c.EmployeeRoster_NewContact';
import LBL_ADD_RELATIONSHIP from '@salesforce/label/c.EmployeeRoster_AddRelationship';
import LBL_SUCCESS_TITLE from '@salesforce/label/c.EmployeeRoster_SuccessTitle';
import LBL_SUCCESS_MSG from '@salesforce/label/c.EmployeeRoster_SuccessMessage';
import LBL_ERROR_TITLE from '@salesforce/label/c.EmployeeRoster_ErrorTitle';

/**
 * @description Lists a company's employees (active and inactive) with inline editing of Roles and
 * coverage tier (Family), a read-only Emp.Status indicator (changed only through Offboard), a
 * per-row Offboard action on active employees, and quick navigation to the relationship record.
 * @author Liam Jeong <liam.jeong@5sinfusion.com>
 */
export default class EmployeeRoster extends NavigationMixin(LightningElement) {
    /** @description The company (Account) record id this roster belongs to. */
    @api recordId;

    label = {
        title: LBL_TITLE,
        colName: LBL_COL_NAME,
        colCompany: LBL_COL_COMPANY,
        colEmpStatus: LBL_COL_EMP_STATUS,
        colRoles: LBL_COL_ROLES,
        colPlans: LBL_COL_PLANS,
        colFamily: LBL_COL_FAMILY,
        colActiveIns: LBL_COL_ACTIVE_INS,
        offboard: LBL_OFFBOARD,
        noEmployees: LBL_NO_EMPLOYEES,
        loadError: LBL_LOAD_ERROR,
        offboardBody: LBL_OFFBOARD_BODY,
        endDate: LBL_END_DATE,
        cancel: LBL_CANCEL,
        save: LBL_SAVE,
        rolesPlaceholder: LBL_ROLES_PLACEHOLDER,
        familyPlaceholder: LBL_FAMILY_PLACEHOLDER,
        openRelationship: LBL_OPEN_RELATIONSHIP,
        active: LBL_ACTIVE,
        inactive: LBL_INACTIVE,
        newContact: LBL_NEW_CONTACT,
        addRelationship: LBL_ADD_RELATIONSHIP
    };

    rows = [];
    hasError = false;
    wiredEmployees;

    rolesOptions = [];
    familyOptions = [];

    sortedBy = 'name';
    sortedDirection = 'asc';
    drafts = {};

    /** @description Current left-to-right column order; reassigned when a header is dropped. */
    columnOrder = COLUMN_DEFS.map((def) => def.field);
    /** @description Committed column widths (px) keyed by field, so a resize survives re-renders. */
    widths = {};

    resizeState;
    dragField;
    dropTarget;
    dropAfter;
    justDragged = false;

    showModal = false;
    selectedAcrId;
    selectedName;
    endDate;
    isSaving = false;

    @wire(getFieldOptions)
    handleFieldOptions({ data }) {
        if (data) {
            this.rolesOptions = data.roles;
            this.familyOptions = data.family;
        }
    }

    @wire(getEmployees, { accountId: '$recordId' })
    handleWire(result) {
        this.wiredEmployees = result;
        if (result.data) {
            this.rows = this.applySort(result.data.map((row) => this.decorateRow({ ...row })));
            this.drafts = {};
            this.hasError = false;
        } else if (result.error) {
            this.rows = [];
            this.hasError = true;
            this.notifyError(result.error);
        }
    }

    /**
     * @description Adds display-only decorations to a roster row (the Plans coverage badges).
     * @param row The raw row to decorate.
     * @return The same row with `planBadges` populated.
     */
    decorateRow(row) {
        row.planBadges = this.toPlanBadges(row.plans);
        return row;
    }

    /**
     * @description Splits a "M / D / V" plans string into color-coded badge descriptors.
     * @param plans The slash-separated coverage-tier string.
     * @return One badge descriptor per coverage tier.
     */
    toPlanBadges(plans) {
        if (!plans) {
            return [];
        }
        return plans
            .split('/')
            .map((token) => token.trim())
            .filter((token) => token)
            .map((token, index) => {
                const code = token.toUpperCase();
                const meta = PLAN_META[code];
                return {
                    key: `${code}-${index}`,
                    label: code,
                    title: meta ? meta.title : code,
                    cssClass: meta ? meta.cssClass : 'plan-badge plan-other'
                };
            });
    }

    get hasEmployees() {
        return this.rows && this.rows.length > 0;
    }

    get hasChanges() {
        return Object.keys(this.drafts).length > 0;
    }

    get modalHeading() {
        return `${this.label.offboard} ${this.selectedName || ''}`.trim();
    }

    get sortIconName() {
        return this.sortedDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }

    /**
     * @description The header descriptors in the user's current column order.
     * @return One descriptor per reorderable column.
     */
    get columns() {
        return this.columnOrder.map((field) => {
            const def = COLUMN_BY_FIELD[field];
            const width = this.widths[field];
            return {
                field,
                label: this.label[def.labelKey],
                headerClass: `roster-sortable roster-draggable ${def.colClass}`.trim(),
                style: width ? `width: ${width}px;` : '',
                showSortIcon: this.sortedBy === field
            };
        });
    }

    /**
     * @description The roster rows with their cells laid out in the current column order, so a
     * reorder of `columnOrder` moves the header and its data together.
     * @return The rows, each carrying a `cells` array parallel to `columns`.
     */
    get displayRows() {
        return this.rows.map((row) => ({ ...row, cells: this.buildCells(row) }));
    }

    /**
     * @description Builds one display descriptor per column for a single roster row.
     * @param row The roster row to render.
     * @return The row's cells, ordered to match `columnOrder`.
     */
    buildCells(row) {
        return this.columnOrder.map((field) => {
            const cell = {
                key: `${row.acrId}-${field}`,
                field,
                acrId: row.acrId,
                label: this.label[COLUMN_BY_FIELD[field].labelKey]
            };
            switch (field) {
                case 'name':
                    return { ...cell, isLink: true, url: row.contactUrl, text: row.name };
                case 'company':
                    return { ...cell, isLink: true, url: row.companyUrl, text: row.company };
                case 'empStatus':
                    return { ...cell, isEmpStatus: true, isActiveEmp: !!row.empStatus };
                case 'roles':
                    return {
                        ...cell,
                        isCombo: true,
                        value: row.roles,
                        options: this.rolesOptions,
                        placeholder: this.label.rolesPlaceholder
                    };
                case 'plans':
                    return { ...cell, isPlans: true, badges: row.planBadges };
                case 'family':
                    return {
                        ...cell,
                        isCombo: true,
                        value: row.family,
                        options: this.familyOptions,
                        placeholder: this.label.familyPlaceholder
                    };
                case 'activeIns':
                    return { ...cell, isChecked: !!row.activeIns };
                default:
                    return cell;
            }
        });
    }

    handleSort(event) {
        // A native drag ends with a click on the header it started from in some browsers; ignore
        // it so repositioning a column does not also flip its sort direction.
        if (this.justDragged) {
            return;
        }
        const field = event.currentTarget.dataset.field;
        if (this.sortedBy === field) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = field;
            this.sortedDirection = 'asc';
        }
        this.rows = this.applySort([...this.rows]);
    }

    applySort(list) {
        const direction = this.sortedDirection === 'asc' ? 1 : -1;
        const field = this.sortedBy;
        return list.sort((a, b) => {
            let first = a[field] === null || a[field] === undefined ? '' : a[field];
            let second = b[field] === null || b[field] === undefined ? '' : b[field];
            if (typeof first === 'string') {
                first = first.toLowerCase();
            }
            if (typeof second === 'string') {
                second = second.toLowerCase();
            }
            if (first > second) {
                return direction;
            }
            if (first < second) {
                return -direction;
            }
            return 0;
        });
    }

    /**
     * @description Begins a column resize when a header resize handle is pressed. Uses pointer
     * capture so the drag keeps tracking even when the cursor leaves the handle.
     * @param event The pointerdown event on the resize handle.
     */
    handleResizeStart(event) {
        event.preventDefault();
        event.stopPropagation();
        const field = event.currentTarget.dataset.field;
        const header = this.getHeader(field);
        if (!header) {
            return;
        }
        event.currentTarget.setPointerCapture(event.pointerId);
        const startWidth = this.widths[field] || header.getBoundingClientRect().width;
        this.resizeState = { field, startX: event.clientX, startWidth, width: startWidth };
    }

    /**
     * @description Widens or narrows the active column as the resize handle is dragged. The width
     * is written straight to the header element so the drag stays smooth; it is only committed to
     * reactive state (and so re-rendered) on pointerup.
     * @param event The pointermove event on the resize handle.
     */
    handleResizeMove(event) {
        if (!this.resizeState) {
            return;
        }
        const delta = event.clientX - this.resizeState.startX;
        const width = Math.max(MIN_COLUMN_WIDTH, this.resizeState.startWidth + delta);
        const header = this.getHeader(this.resizeState.field);
        if (header) {
            header.style.width = `${width}px`;
            this.resizeState.width = width;
        }
    }

    /**
     * @description Ends the active column resize and remembers the new width, so it survives the
     * re-render that a sort, an inline edit or a column reorder triggers.
     */
    handleResizeEnd() {
        if (this.resizeState) {
            this.widths = { ...this.widths, [this.resizeState.field]: this.resizeState.width };
        }
        this.resizeState = undefined;
    }

    /**
     * @description Starts dragging a column header to a new position. Suppressed while a resize is
     * in flight so grabbing the resize handle never turns into a column move.
     * @param event The dragstart event on the header.
     */
    handleDragStart(event) {
        if (this.resizeState) {
            event.preventDefault();
            return;
        }
        const header = event.currentTarget;
        this.dragField = header.dataset.field;
        event.dataTransfer.effectAllowed = 'move';
        // Firefox refuses to start a drag unless some data is attached.
        event.dataTransfer.setData('text/plain', this.dragField);
        // Deferred so the browser snapshots the drag image before the header dims.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => header.classList.add('roster-dragging'), 0);
    }

    /**
     * @description Marks the edge the dragged column would land on and allows the drop. Which side
     * of the hovered header the pointer is on decides whether the column lands before or after it.
     * @param event The dragover event on a header.
     */
    handleDragOver(event) {
        if (!this.dragField) {
            return;
        }
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        const header = event.currentTarget;
        const field = header.dataset.field;
        if (field === this.dragField) {
            this.clearDropMarkers();
            this.dropTarget = undefined;
            return;
        }
        const rect = header.getBoundingClientRect();
        const after = event.clientX > rect.left + rect.width / 2;
        if (this.dropTarget === field && this.dropAfter === after) {
            return;
        }
        this.dropTarget = field;
        this.dropAfter = after;
        this.clearDropMarkers();
        header.classList.add(after ? 'roster-drop-after' : 'roster-drop-before');
    }

    /**
     * @description Drops the dragged column at the marked position.
     * @param event The drop event on a header.
     */
    handleDrop(event) {
        if (!this.dragField) {
            return;
        }
        event.preventDefault();
        event.stopPropagation();
        const field = event.currentTarget.dataset.field;
        const rect = event.currentTarget.getBoundingClientRect();
        this.moveColumn(this.dragField, field, event.clientX > rect.left + rect.width / 2);
    }

    /**
     * @description Clears the drag decorations once the pointer is released, wherever it landed.
     */
    handleDragEnd() {
        this.clearDropMarkers();
        const dragging = this.template.querySelector('th.roster-dragging');
        if (dragging) {
            dragging.classList.remove('roster-dragging');
        }
        this.dragField = undefined;
        this.dropTarget = undefined;
        this.justDragged = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.justDragged = false;
        }, 0);
    }

    /**
     * @description Repositions a column relative to another one.
     * @param field The column being moved.
     * @param targetField The column it was dropped on.
     * @param after Whether it lands to the right of the target.
     */
    moveColumn(field, targetField, after) {
        if (!field || !targetField || field === targetField) {
            return;
        }
        const order = this.columnOrder.filter((item) => item !== field);
        const index = order.indexOf(targetField);
        if (index < 0) {
            return;
        }
        order.splice(after ? index + 1 : index, 0, field);
        this.columnOrder = order;
    }

    clearDropMarkers() {
        this.template.querySelectorAll('th.roster-draggable').forEach((header) => {
            header.classList.remove(...DROP_MARKERS);
        });
    }

    /**
     * @description Swallows a click on the resize handle so it does not trigger column sort.
     * @param event The click event on the resize handle.
     */
    stopEvent(event) {
        event.stopPropagation();
    }

    getHeader(field) {
        return this.template.querySelector(`th[data-field="${field}"]`);
    }

    handleComboChange(event) {
        this.applyEdit(event.target.dataset.acr, event.target.dataset.field, event.detail.value);
    }

    applyEdit(acrId, field, value) {
        this.rows = this.rows.map((row) => (row.acrId === acrId ? { ...row, [field]: value } : row));
        const edited = this.rows.find((row) => row.acrId === acrId);
        this.drafts = {
            ...this.drafts,
            [acrId]: { acrId, roles: edited.roles, family: edited.family }
        };
    }

    handleCancel() {
        this.drafts = {};
        return refreshApex(this.wiredEmployees);
    }

    async handleSave() {
        this.isSaving = true;
        try {
            // Rebuild the payload as plain object literals. Draft values live on the reactive
            // `drafts` field, so they are wrapped in LWC's reactive membrane; passing those
            // proxies straight to Apex serializes each one to an empty object ({}), which the
            // controller then skips (null acrId) — a silent, toast-says-success no-op save.
            // Mapping to fresh literals detaches them so acrId/roles/family actually survive.
            const edits = Object.values(this.drafts).map((draft) => ({
                acrId: draft.acrId,
                roles: draft.roles,
                family: draft.family
            }));
            await saveRelationships({ editsJson: JSON.stringify(edits) });
            this.dispatchEvent(new ShowToastEvent({ title: LBL_SAVE_SUCCESS, variant: 'success' }));
            this.drafts = {};
            await refreshApex(this.wiredEmployees);
        } catch (error) {
            this.notifyError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenAcr(event) {
        this.navigateToRecord(event.currentTarget.dataset.acr, 'AccountContactRelation');
    }

    handleOffboardClick(event) {
        this.selectedAcrId = event.currentTarget.dataset.acr;
        this.selectedName = event.currentTarget.dataset.name;
        this.endDate = new Date().toISOString().slice(0, 10);
        this.showModal = true;
    }

    handleNewContact() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Contact', actionName: 'new' },
            state: { defaultFieldValues: encodeDefaultFieldValues({ AccountId: this.recordId }) }
        });
    }

    handleAddRelationship() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'AccountContactRelation', actionName: 'new' },
            state: { defaultFieldValues: encodeDefaultFieldValues({ AccountId: this.recordId }) }
        });
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    handleDateChange(event) {
        this.endDate = event.target.value;
    }

    closeModal() {
        this.showModal = false;
        this.selectedAcrId = undefined;
        this.selectedName = undefined;
    }

    async confirmOffboard() {
        this.isSaving = true;
        try {
            await offboardEmployee({ acrId: this.selectedAcrId, endDate: this.endDate });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: LBL_SUCCESS_TITLE,
                    message: `${this.selectedName} — ${LBL_SUCCESS_MSG}`,
                    variant: 'success'
                })
            );
            this.showModal = false;
            await refreshApex(this.wiredEmployees);
        } catch (error) {
            this.notifyError(error);
        } finally {
            this.isSaving = false;
        }
    }

    notifyError(error) {
        const message = reduceErrors(error).join(', ') || this.label.loadError;
        this.dispatchEvent(new ShowToastEvent({ title: LBL_ERROR_TITLE, message, variant: 'error' }));
    }
}
