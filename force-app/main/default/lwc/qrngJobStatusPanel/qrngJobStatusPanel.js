import { LightningElement, api, track, wire } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import refreshJobStatus from '@salesforce/apex/QRNGSetupController.refreshJobStatus';
import retrieveJobResults from '@salesforce/apex/QRNGSetupController.retrieveJobResults';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import STATUS_FIELD from '@salesforce/schema/Quantum_Job__c.Status__c';
import EXTERNAL_JOB_ID_FIELD from '@salesforce/schema/Quantum_Job__c.External_Job_ID__c';
import BACKEND_FIELD from '@salesforce/schema/Quantum_Job__c.Backend__c';
import PROVIDER_FIELD from '@salesforce/schema/Quantum_Job__c.Provider__c';
import SHOTS_FIELD from '@salesforce/schema/Quantum_Job__c.Shots__c';
import QUBITS_FIELD from '@salesforce/schema/Quantum_Job__c.Num_Qubits__c';
import PURPOSE_FIELD from '@salesforce/schema/Quantum_Job__c.Purpose__c';
import BELL_TEST_FIELD from '@salesforce/schema/Quantum_Job__c.Use_Bell_Test__c';
import SUBMITTED_FIELD from '@salesforce/schema/Quantum_Job__c.Submitted_At__c';
import COMPLETED_FIELD from '@salesforce/schema/Quantum_Job__c.Completed_At__c';
import ERROR_FIELD from '@salesforce/schema/Quantum_Job__c.Error_Message__c';
import POLL_COUNT_FIELD from '@salesforce/schema/Quantum_Job__c.Poll_Count__c';
import EXEC_TIME_FIELD from '@salesforce/schema/Quantum_Job__c.Execution_Time_ms__c';

const FIELDS = [
    STATUS_FIELD,
    EXTERNAL_JOB_ID_FIELD,
    BACKEND_FIELD,
    PROVIDER_FIELD,
    SHOTS_FIELD,
    QUBITS_FIELD,
    PURPOSE_FIELD,
    BELL_TEST_FIELD,
    SUBMITTED_FIELD,
    COMPLETED_FIELD,
    ERROR_FIELD,
    POLL_COUNT_FIELD,
    EXEC_TIME_FIELD
];

const COMPLETE_CHANNEL = '/event/OpenSF__QRNG_Complete__e';
const FAILED_CHANNEL = '/event/OpenSF__QRNG_Failed__e';

export default class QrngJobStatusPanel extends LightningElement {
    @api recordId;
    @track isRefreshing = false;
    @track isRetrieving = false;

    _wiredRecord;
    _completeSubscription;
    _failedSubscription;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this._wiredRecord = result;
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
                        refreshApex(this._wiredRecord);
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
                        refreshApex(this._wiredRecord);
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

    // Field accessors
    get status() {
        return getFieldValue(this._wiredRecord?.data, STATUS_FIELD) || '—';
    }
    get externalJobId() {
        return (
            getFieldValue(this._wiredRecord?.data, EXTERNAL_JOB_ID_FIELD) || '—'
        );
    }
    get backend() {
        return getFieldValue(this._wiredRecord?.data, BACKEND_FIELD) || '—';
    }
    get provider() {
        return getFieldValue(this._wiredRecord?.data, PROVIDER_FIELD) || '—';
    }
    get shots() {
        return getFieldValue(this._wiredRecord?.data, SHOTS_FIELD) || 0;
    }
    get numQubits() {
        return getFieldValue(this._wiredRecord?.data, QUBITS_FIELD) || 0;
    }
    get purpose() {
        return getFieldValue(this._wiredRecord?.data, PURPOSE_FIELD) || '';
    }
    get useBellTest() {
        return getFieldValue(this._wiredRecord?.data, BELL_TEST_FIELD) || false;
    }
    get submittedAt() {
        return getFieldValue(this._wiredRecord?.data, SUBMITTED_FIELD);
    }
    get completedAt() {
        return getFieldValue(this._wiredRecord?.data, COMPLETED_FIELD);
    }
    get errorMessage() {
        return getFieldValue(this._wiredRecord?.data, ERROR_FIELD);
    }
    get pollCount() {
        return getFieldValue(this._wiredRecord?.data, POLL_COUNT_FIELD) || 0;
    }
    get executionTime() {
        const ms = getFieldValue(this._wiredRecord?.data, EXEC_TIME_FIELD);
        if (!ms) return '—';
        if (ms < 1000) return ms + ' ms';
        return (ms / 1000).toFixed(1) + ' s';
    }

    get hasRecord() {
        return this._wiredRecord?.data != null;
    }

    get hasExternalJobId() {
        return (
            this.externalJobId != null &&
            this.externalJobId !== '—' &&
            this.externalJobId !== ''
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
            await refreshApex(this._wiredRecord);
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
            await refreshApex(this._wiredRecord);
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
