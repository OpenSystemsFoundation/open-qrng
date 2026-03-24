import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { NavigationMixin } from 'lightning/navigation';
import getJobStatusDTO from '@salesforce/apex/SetupController.getJobStatusDTO';
import getCertificateByJobId from '@salesforce/apex/SetupController.getCertificateByJobId';
import { refreshApex } from '@salesforce/apex';

const COMPLETE_CHANNEL = '/event/OpenSF__Quantum_Job_Complete__e';
const FAILED_CHANNEL = '/event/OpenSF__Quantum_Job_Failed__e';
const POLL_INTERVAL_MS = 5000;

export default class QrngJobMonitor extends NavigationMixin(LightningElement) {
    @api jobId;
    @track job;
    @track certificateId;

    _completeSubscription;
    _failedSubscription;
    _wiredJobResult;
    _pollTimer;

    @wire(getJobStatusDTO, { jobId: '$jobId' })
    wiredJob(result) {
        this._wiredJobResult = result;
        if (result.data) {
            this.job = result.data;
            if (this.job.status === 'Completed') {
                this.stopPolling();
                this.loadCertificate();
            } else if (this.job.status === 'Failed') {
                this.stopPolling();
            } else {
                this.startPolling();
            }
        }
    }

    connectedCallback() {
        this.subscribeToEvents();
    }

    disconnectedCallback() {
        this.unsubscribeFromEvents();
        this.stopPolling();
    }

    startPolling() {
        if (this._polling) return;
        this._polling = true;
        this.schedulePoll();
    }

    schedulePoll() {
        if (!this._polling) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setTimeout(() => {
            if (!this._polling) return;
            refreshApex(this._wiredJobResult);
            this.schedulePoll();
        }, POLL_INTERVAL_MS);
    }

    stopPolling() {
        this._polling = false;
        if (this._pollTimer) {
            clearTimeout(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async subscribeToEvents() {
        try {
            this._completeSubscription = await subscribe(
                COMPLETE_CHANNEL,
                -1,
                (message) => {
                    this.handleCompleteEvent(message);
                }
            );
            this._failedSubscription = await subscribe(
                FAILED_CHANNEL,
                -1,
                (message) => {
                    this.handleFailedEvent(message);
                }
            );
        } catch (error) {
            console.error('Error subscribing to events:', error);
        }

        onError((error) => {
            console.error('EMP API error:', error);
        });
    }

    unsubscribeFromEvents() {
        if (this._completeSubscription) {
            unsubscribe(this._completeSubscription);
        }
        if (this._failedSubscription) {
            unsubscribe(this._failedSubscription);
        }
    }

    handleCompleteEvent(message) {
        const payload = message.data.payload;
        const eventJobId = payload.OpenSF__Job_Id__c;

        if (eventJobId === this.jobId) {
            this.certificateId = payload.OpenSF__Certificate_Id__c;
            this.stopPolling();
            refreshApex(this._wiredJobResult);

            this.dispatchEvent(
                new CustomEvent('jobcomplete', {
                    detail: {
                        jobId: this.jobId,
                        certificateId: this.certificateId,
                        status: payload.OpenSF__Status__c
                    }
                })
            );
        }
    }

    handleFailedEvent(message) {
        const payload = message.data.payload;
        const eventJobId = payload.OpenSF__Job_Id__c;

        if (eventJobId === this.jobId) {
            this.stopPolling();
            refreshApex(this._wiredJobResult);
        }
    }

    async loadCertificate() {
        try {
            const cert = await getCertificateByJobId({ jobId: this.jobId });
            if (cert) {
                this.certificateId = cert.Id;
            }
        } catch (error) {
            console.error('Error loading certificate:', error);
        }
    }

    get currentStep() {
        if (!this.job) return 'Submitted';
        return this.job.status === 'Failed' ? 'Submitted' : this.job.status;
    }

    get isInProgress() {
        if (!this.job) return false;
        return ['Submitted', 'Queued', 'Running', 'Pending'].includes(
            this.job.status
        );
    }

    get isCompleted() {
        return this.job && this.job.status === 'Completed';
    }

    handleNavigateToJob() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.jobId,
                objectApiName: 'OpenSF__Quantum_Job__c',
                actionName: 'view'
            }
        });
    }

    get statusClass() {
        if (!this.job) return 'status-badge';
        const statusMap = {
            Pending: 'status-badge status-pending',
            Submitted: 'status-badge status-submitted',
            Queued: 'status-badge status-queued',
            Running: 'status-badge status-running',
            Completed: 'status-badge status-completed',
            Failed: 'status-badge status-failed'
        };
        return statusMap[this.job.status] || 'status-badge';
    }
}
