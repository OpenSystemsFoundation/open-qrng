import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { refreshApex } from '@salesforce/apex';
import getJobStatusDTO from '@salesforce/apex/SetupController.getJobStatusDTO';
import getCertificateByJobId from '@salesforce/apex/SetupController.getCertificateByJobId';
import refreshJobStatus from '@salesforce/apex/SetupController.refreshJobStatus';
import retrieveJobResults from '@salesforce/apex/SetupController.retrieveJobResults';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COMPLETE_CHANNEL = '/event/OpenSF__Quantum_Job_Complete__e';
const FAILED_CHANNEL = '/event/OpenSF__Quantum_Job_Failed__e';

export default class QrngJobStatusPanel extends LightningElement {
    @api recordId;
    @track isRefreshing = false;
    @track isRetrieving = false;
    @track certificateId;

    _wiredResult;
    _dto;
    _completeSubscription;
    _failedSubscription;

    @wire(getJobStatusDTO, { jobId: '$recordId' })
    wiredJobStatus(result) {
        this._wiredResult = result;
        if (result.data) {
            this._dto = result.data;
            if (this._dto.status === 'Completed' && !this.certificateId) {
                this.loadCertificate();
            }
        }
    }

    async loadCertificate() {
        try {
            const cert = await getCertificateByJobId({
                jobId: this.recordId
            });
            if (cert) {
                this.certificateId = cert.Id;
            }
        } catch {
            // Certificate may not exist yet
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
                    const eventJobId = message.data.payload.OpenSF__Job_Id__c;
                    if (eventJobId === this.recordId) {
                        this.certificateId =
                            message.data.payload.OpenSF__Certificate_Id__c;
                        refreshApex(this._wiredResult);
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Job Completed',
                                message:
                                    'Quantum job finished. Results are ready.',
                                variant: 'success'
                            })
                        );
                    }
                }
            );
            this._failedSubscription = await subscribe(
                FAILED_CHANNEL,
                -1,
                (message) => {
                    const eventJobId = message.data.payload.OpenSF__Job_Id__c;
                    if (eventJobId === this.recordId) {
                        refreshApex(this._wiredResult);
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Job Failed',
                                message:
                                    message.data.payload
                                        .OpenSF__Error_Message__c ||
                                    'Unknown error',
                                variant: 'error'
                            })
                        );
                    }
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

    // DTO field accessors
    get status() {
        return this._dto?.status || '—';
    }
    get externalJobId() {
        return this._dto?.externalJobId || '—';
    }
    get backend() {
        return this._dto?.backend || '—';
    }
    get provider() {
        return this._dto?.provider || '—';
    }
    get shots() {
        return this._dto?.shots || 0;
    }
    get numQubits() {
        return this._dto?.numQubits || 0;
    }
    get purpose() {
        return this._dto?.purpose || '';
    }
    get useBellTest() {
        return this._dto?.useBellTest || false;
    }
    get jobType() {
        return this._dto?.jobType || 'QRNG';
    }
    get isVerifyJob() {
        return this.jobType === 'CHSH Verification' || this.useBellTest;
    }
    get jobTypeLabel() {
        return this.isVerifyJob ? 'Quantum Verification' : 'QRNG';
    }
    get assignmentType() {
        return this._dto?.assignmentType || '—';
    }
    get submittedAt() {
        return this._dto?.submittedAt;
    }
    get completedAt() {
        return this._dto?.completedAt;
    }
    get errorMessage() {
        return this._dto?.errorMessage;
    }
    get pollCount() {
        return this._dto?.pollCount || 0;
    }
    get executionTime() {
        const ms = this._dto?.executionTimeMs;
        if (ms == null) return '—';
        if (ms < 1000) return ms + ' ms';
        return (ms / 1000).toFixed(1) + ' s';
    }
    get queueTime() {
        const ms = this._dto?.queueTimeMs;
        if (ms == null) return '—';
        if (ms < 1000) return ms + ' ms';
        return (ms / 1000).toFixed(1) + ' s';
    }

    get rawResults() {
        return this._dto?.rawResults;
    }

    get debiasedResults() {
        return this._dto?.debiasedResults;
    }

    get hasResults() {
        return this.isCompleted && this._dto?.rawResults && !this.isVerifyJob;
    }

    get hasCertificate() {
        return this.isCompleted && this.certificateId;
    }

    get hasRecord() {
        return this._dto != null;
    }

    get hasExternalJobId() {
        return (
            this._dto?.externalJobId != null && this._dto.externalJobId !== ''
        );
    }

    get missingExternalIdMessage() {
        return !this.hasExternalJobId
            ? 'No External Job ID on this record. Cannot refresh status or retrieve results from the provider.'
            : null;
    }

    get isInProgress() {
        return ['Submitted', 'Queued', 'Running', 'Pending'].includes(
            this.status
        );
    }

    get isCompleted() {
        return this.status === 'Completed';
    }

    get isFailed() {
        return this.status === 'Failed';
    }

    get disableRefresh() {
        return (
            !this.hasRecord ||
            !this.hasExternalJobId ||
            this.isRefreshing ||
            this.isRetrieving
        );
    }

    get disableRetrieve() {
        return (
            !this.hasRecord ||
            !this.hasExternalJobId ||
            this.isRetrieving ||
            this.isRefreshing ||
            this.isInProgress
        );
    }

    get currentStep() {
        if (this.isFailed) return 'Submitted';
        return this.status;
    }

    get statusBadgeClass() {
        const base = 'slds-badge';
        const map = {
            Pending: base,
            Submitted: base + ' slds-theme_success',
            Queued: base + ' slds-theme_warning',
            Running: base + ' slds-badge_inverse',
            Completed: base + ' slds-theme_success',
            Failed: base + ' slds-theme_error'
        };
        return map[this.status] || base;
    }

    async handleRefreshStatus() {
        this.isRefreshing = true;
        try {
            const result = await refreshJobStatus({
                jobId: this.recordId
            });
            await refreshApex(this._wiredResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Status Refreshed',
                    message: `IBM status: ${result.ibmStatus} → ${result.status}`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Refresh Failed',
                    message:
                        error?.body?.message ||
                        error?.message ||
                        'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isRefreshing = false;
        }
    }

    async handleRetrieveResults() {
        this.isRetrieving = true;
        try {
            const result = await retrieveJobResults({
                jobId: this.recordId
            });
            await refreshApex(this._wiredResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Results Retrieved',
                    message: `Got ${result.rawBitsLength} raw bits, ${result.debiasedBitsLength} debiased bits. Certificate created.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Retrieve Failed',
                    message:
                        error?.body?.message ||
                        error?.message ||
                        'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isRetrieving = false;
        }
    }
}
