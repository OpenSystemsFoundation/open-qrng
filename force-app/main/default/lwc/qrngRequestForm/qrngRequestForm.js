import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import submitQRNGJob from '@salesforce/apex/QRNGSetupController.submitQRNGJob';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngRequestForm extends LightningElement {
    @track backend = '';
    @track numQubits = 8;
    @track shots = 1024;
    @track purpose = '';
    @track useBellTest = false;
    @track isSubmitting = false;
    @track showPreview = true;

    backendOptions = [];

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) {
            this.shots = data.defaultShots || 1024;
            this.useBellTest = data.useBellTest || false;

            // Set backend — use __least_busy__ sentinel if enabled
            if (data.useLeastBusy) {
                this.backend = '__least_busy__';
            } else {
                this.backend = data.defaultBackend || '';
            }

            // Build backend dropdown from cached backends
            if (data.cachedBackends && data.cachedBackends.length > 0) {
                this.backendOptions = data.cachedBackends.map((b) => {
                    const statusStr =
                        typeof b.status === 'object'
                            ? b.status.name || 'unknown'
                            : b.status || 'unknown';
                    return {
                        label: `${b.name} (${b.qubits} qubits, ${statusStr})`,
                        value: b.name
                    };
                });
                this.backendOptions.unshift({
                    label: 'Least Busy (auto-select)',
                    value: '__least_busy__'
                });
            }
        }
    }

    get effectiveQubits() {
        return this.useBellTest
            ? Math.max(2, Math.floor(this.numQubits / 2) * 2)
            : this.numQubits;
    }

    handleBackendChange(event) {
        this.backend = event.detail.value;
    }
    handleQubitsChange(event) {
        this.numQubits = parseInt(event.target.value, 10);
    }
    handleShotsChange(event) {
        this.shots = parseInt(event.target.value, 10);
    }
    handlePurposeChange(event) {
        this.purpose = event.target.value;
    }
    handleBellTestChange(event) {
        this.useBellTest = event.target.checked;
    }

    async handleSubmit() {
        this.isSubmitting = true;
        try {
            const backendToSubmit =
                this.backend === '__least_busy__' ? '' : this.backend;
            const jobId = await submitQRNGJob({
                backend: backendToSubmit,
                numQubits: this.numQubits,
                shots: this.shots,
                purpose: this.purpose,
                useBellTest: this.useBellTest
            });

            this.dispatchEvent(
                new CustomEvent('jobsubmitted', {
                    detail: { jobId }
                })
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Job Submitted',
                    message:
                        'Quantum circuit submitted to IBM. Monitoring job...',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Submission Failed',
                    message:
                        error?.body?.message ||
                        error?.message ||
                        'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isSubmitting = false;
        }
    }
}
