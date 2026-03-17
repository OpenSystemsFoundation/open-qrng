import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getJobDetails from '@salesforce/apex/QRNGSetupController.getJobDetails';
import getCertificateByJobId from '@salesforce/apex/QRNGSetupController.getCertificateByJobId';
import { refreshApex } from '@salesforce/apex';

const COMPLETE_CHANNEL = '/event/OpenSF__QRNG_Complete__e';
const FAILED_CHANNEL = '/event/OpenSF__QRNG_Failed__e';

export default class QrngJobMonitor extends LightningElement {
    @api jobId;
    @track job;
    @track certificateId;

    _completeSubscription;
    _failedSubscription;
    _wiredJobResult;

    @wire(getJobDetails, { jobId: '$jobId' })
    wiredJob(result) {
        this._wiredJobResult = result;
        if (result.data) {
            this.job = result.data;
            if (this.job.Status__c === 'Completed') {
                this.loadCertificate();
            }
        }
    }

    connectedCallback() {
        this.subscribeToEvents();
    }

    disconnectedCallback() {
        this.unsubscribeFromEvents();
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
        return this.job.Status__c === 'Failed'
            ? 'Submitted'
            : this.job.Status__c;
    }

    get isInProgress() {
        if (!this.job) return false;
        return ['Submitted', 'Queued', 'Running', 'Pending'].includes(
            this.job.Status__c
        );
    }

    get isCompleted() {
        return this.job && this.job.Status__c === 'Completed';
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
        return statusMap[this.job.Status__c] || 'status-badge';
    }
}
