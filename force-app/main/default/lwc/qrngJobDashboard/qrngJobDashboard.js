import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getRecentJobs from '@salesforce/apex/SetupController.getRecentJobs';
import {
    subscribeToQuantumEvents,
    unsubscribeFromQuantumEvents
} from 'c/qrngEventSubscription';

const STATUS_CONFIG = {
    Completed: {
        icon: 'utility:success',
        variant: 'success',
        class: 'slds-text-color_success'
    },
    Failed: {
        icon: 'utility:error',
        variant: 'error',
        class: 'slds-text-color_error'
    },
    Running: {
        icon: 'utility:spinner',
        variant: 'warning',
        class: 'slds-text-color_default'
    },
    Queued: {
        icon: 'utility:clock',
        variant: '',
        class: 'slds-text-color_weak'
    },
    Submitted: {
        icon: 'utility:upload',
        variant: '',
        class: 'slds-text-color_weak'
    }
};

export default class QrngJobDashboard extends NavigationMixin(
    LightningElement
) {
    @track jobs = [];
    @track filter = 'ALL';

    _wiredResult;
    _eventSub;

    @api
    refreshJobs() {
        return refreshApex(this._wiredResult);
    }

    filterOptions = [
        { label: 'All Jobs', value: 'ALL' },
        { label: 'Running', value: 'ACTIVE' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Failed', value: 'Failed' },
        { label: 'Quantum', value: 'Quantum' },
        { label: 'Verification', value: 'CHSH Verification' }
    ];

    connectedCallback() {
        this._eventSub = subscribeToQuantumEvents(
            () => {
                refreshApex(this._wiredResult);
            },
            () => {
                refreshApex(this._wiredResult);
            }
        );
    }

    disconnectedCallback() {
        unsubscribeFromQuantumEvents(this._eventSub);
    }

    @wire(getRecentJobs)
    wiredJobs(result) {
        this._wiredResult = result;
        if (result.data) {
            this.jobs = result.data.map((job) => {
                const cfg =
                    STATUS_CONFIG[job.status] || STATUS_CONFIG.Submitted;
                const isVerify =
                    job.jobType === 'CHSH Verification' || job.useBellTest;
                return {
                    id: job.id,
                    name: job.name,
                    externalJobId: job.externalJobId || '\u2014',
                    backend: job.backend || '\u2014',
                    status: job.status,
                    statusIcon: cfg.icon,
                    statusVariant: cfg.variant,
                    statusClass: cfg.class,
                    jobType: isVerify ? 'Verification' : 'Quantum',
                    jobTypeRaw: job.jobType,
                    shots: job.shots,
                    qubits: job.numQubits,
                    purpose: job.purpose || '\u2014',
                    submittedAt: job.submittedAt,
                    completedAt: job.completedAt,
                    executionTime: this.formatMs(job.executionTimeMs),
                    qpuTime: this.formatQpuTime(job.qpuTimeSeconds),
                    requestedBy: job.requestedByName || '\u2014',
                    errorMessage: job.errorMessage,
                    hasError: !!job.errorMessage,
                    isActive:
                        job.status === 'Running' ||
                        job.status === 'Queued' ||
                        job.status === 'Submitted'
                };
            });
        }
    }

    get filteredJobs() {
        if (this.filter === 'ALL') return this.jobs;
        if (this.filter === 'ACTIVE') {
            return this.jobs.filter((j) => j.isActive);
        }
        if (this.filter === 'Quantum' || this.filter === 'CHSH Verification') {
            return this.jobs.filter((j) => j.jobTypeRaw === this.filter);
        }
        return this.jobs.filter((j) => j.status === this.filter);
    }

    get hasJobs() {
        return this.filteredJobs.length > 0;
    }

    get jobCount() {
        return this.filteredJobs.length;
    }

    get activeCount() {
        return this.jobs.filter((j) => j.isActive).length;
    }

    get completedCount() {
        return this.jobs.filter((j) => j.status === 'Completed').length;
    }

    get failedCount() {
        return this.jobs.filter((j) => j.status === 'Failed').length;
    }

    handleFilterChange(event) {
        this.filter = event.detail.value;
    }

    handleRefresh() {
        refreshApex(this._wiredResult);
    }

    handleNavigateToJob(event) {
        const jobId = event.currentTarget.dataset.jobid;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: jobId,
                objectApiName: 'Quantum_Job__c',
                actionName: 'view'
            }
        });
    }

    formatMs(ms) {
        if (ms == null) return '\u2014';
        if (ms < 1000) return ms + ' ms';
        return (ms / 1000).toFixed(1) + ' s';
    }

    formatQpuTime(seconds) {
        if (seconds == null) return '\u2014';
        if (seconds < 1) return (seconds * 1000).toFixed(0) + ' ms';
        return Number(seconds).toFixed(2) + ' s';
    }
}
