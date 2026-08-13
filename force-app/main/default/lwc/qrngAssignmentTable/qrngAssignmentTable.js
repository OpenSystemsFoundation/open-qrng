import { LightningElement, api, wire, track } from 'lwc';
import getAssignmentsDTO from '@salesforce/apex/SetupController.getAssignmentsDTO';
import { reduceErrors } from 'c/qrngUtils';

// Columns keyed to the namespace-safe DTO returned by getAssignmentsDTO:
// { name, index, recordId, assigneeId, randomValue }
const COLUMNS = [
    {
        label: '#',
        fieldName: 'index',
        type: 'number',
        fixedWidth: 60
    },
    { label: 'Assignment', fieldName: 'name', type: 'text' },
    { label: 'Record ID', fieldName: 'recordId', type: 'text' },
    { label: 'Assigned To', fieldName: 'assigneeId', type: 'text' },
    { label: 'Random Value', fieldName: 'randomValue', type: 'text' }
];

export default class QrngAssignmentTable extends LightningElement {
    @track assignments = [];
    @track error;
    @track _resolved = false;
    columns = COLUMNS;

    // Effective job id — explicit jobId binding wins over the
    // record-page recordId.
    @track _effectiveJobId;
    _jobId;
    _recordId;

    /** Explicit job id (parent components / app builder property). */
    @api
    get jobId() {
        return this._jobId;
    }
    set jobId(value) {
        this._jobId = value;
        this._updateEffectiveJobId();
    }

    /** Record-page support: flexipages inject the record id here. */
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this._updateEffectiveJobId();
    }

    _updateEffectiveJobId() {
        const next = this._jobId || this._recordId;
        if (next !== this._effectiveJobId) {
            this._effectiveJobId = next;
            // New id → wire re-fires; show the spinner again
            this._resolved = false;
            this.error = undefined;
        }
    }

    @wire(getAssignmentsDTO, { jobId: '$_effectiveJobId' })
    wiredAssignments({ data, error }) {
        if (data) {
            this.assignments = data;
            this.error = undefined;
            this._resolved = true;
        } else if (error) {
            this.assignments = [];
            this.error = reduceErrors(error);
            this._resolved = true;
        }
        // Neither data nor error → wire still in flight; keep waiting
    }

    /** Spinner shows only while a wire request is actually in flight. */
    get isLoading() {
        return !!this._effectiveJobId && !this._resolved && !this.error;
    }

    get hasAssignments() {
        return this.assignments && this.assignments.length > 0;
    }

    get showEmptyState() {
        return !this.hasAssignments && !this.isLoading && !this.error;
    }
}
