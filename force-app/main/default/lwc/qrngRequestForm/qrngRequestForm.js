import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import submitQRNGJob from '@salesforce/apex/QRNGSetupController.submitQRNGJob';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const DEFAULT_MAX_QUBITS = 127;
const DEFAULT_MAX_SHOTS = 8192;
// Raw results stored as hex with '0x' prefix in a 131,072-char LongTextArea
const MAX_STORABLE_BITS = (131072 - 2) * 4;

export default class QrngRequestForm extends LightningElement {
    @track backend = '';
    @track numQubits = 8;
    @track shots = 1024;
    @track purpose = '';
    @track useBellTest = false;
    @track isSubmitting = false;
    @track showPreview = true;

    backendOptions = [];
    _backendsMap = {};

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
                this._backendsMap = {};
                this.backendOptions = data.cachedBackends.map((b) => {
                    const statusStr =
                        typeof b.status === 'object'
                            ? b.status.name || 'unknown'
                            : b.status || 'unknown';
                    this._backendsMap[b.name] = {
                        name: b.name,
                        status: statusStr,
                        qubits: b.qubits || DEFAULT_MAX_QUBITS,
                        maxShots: b.maxShots || DEFAULT_MAX_SHOTS,
                        queueLength: b.queueLength,
                        isSimulator: b.isSimulator || false,
                        processorFamily: b.processorFamily || '',
                        provider: b.provider || ''
                    };
                    return {
                        label: `${b.name} (${b.qubits || '?'} qubits, ${statusStr})`,
                        value: b.name
                    };
                });
                this.backendOptions.unshift({
                    label: 'Least Busy (auto-select)',
                    value: '__least_busy__'
                });

                // Clamp initial values to selected backend limits
                this._clampToBackendLimits();
            }
        }
    }

    // ── Computed: selected backend info ────────────────────────
    get selectedBackendInfo() {
        if (
            this.backend &&
            this.backend !== '__least_busy__' &&
            this._backendsMap[this.backend]
        ) {
            return this._backendsMap[this.backend];
        }
        return null;
    }

    get selectedBackendStatusClass() {
        const info = this.selectedBackendInfo;
        if (!info) return 'status-chip';
        const s = (info.status || '').toLowerCase();
        if (s === 'online') return 'status-chip online';
        if (s === 'offline') return 'status-chip offline';
        return 'status-chip';
    }

    get hasQueueLength() {
        const info = this.selectedBackendInfo;
        return info && info.queueLength != null && info.queueLength >= 0;
    }

    // ── Computed: qubit constraints ───────────────────────────
    get maxQubits() {
        const info = this.selectedBackendInfo;
        return info ? info.qubits : DEFAULT_MAX_QUBITS;
    }

    get minQubits() {
        return this.useBellTest ? 2 : 1;
    }

    get qubitStep() {
        return this.useBellTest ? 2 : 1;
    }

    get qubitsHelpText() {
        if (this.useBellTest) {
            return `Bell test requires even numbers of qubits (pairs). Each pair is entangled. Max ${this.maxQubits} for selected backend.`;
        }
        return `How many quantum bits to measure. More qubits = more random bits per shot. Max ${this.maxQubits} for selected backend.`;
    }

    get qubitsDescription() {
        const bits = this.effectiveQubits * this.shots;
        const bellNote = this.useBellTest
            ? ` (${this.effectiveQubits / 2} entangled pairs)`
            : '';
        return `${this.effectiveQubits} qubits${bellNote} × ${this.shots} shots = ${bits.toLocaleString()} random bits`;
    }

    get qubitsUnderflowMessage() {
        return `Minimum ${this.minQubits} qubit${this.minQubits > 1 ? 's' : ''} required`;
    }

    get qubitsOverflowMessage() {
        return `Selected backend supports up to ${this.maxQubits} qubits`;
    }

    get qubitsStepMessage() {
        return 'Bell test mode requires an even number of qubits (pairs)';
    }

    // ── Computed: shot constraints ────────────────────────────
    get maxShots() {
        const info = this.selectedBackendInfo;
        return info && info.maxShots ? info.maxShots : DEFAULT_MAX_SHOTS;
    }

    get shotsOverflowMessage() {
        return `Selected backend supports up to ${this.maxShots} shots`;
    }

    get shotsDescription() {
        if (this.shots <= 500) {
            return 'Low shot count — faster but less statistically reliable.';
        }
        if (this.shots <= 2000) {
            return 'Good balance of speed and statistical quality.';
        }
        if (this.shots <= 4096) {
            return 'High shot count — excellent statistical reliability.';
        }
        return 'Maximum precision — best for high-stakes fairness certification.';
    }

    get effectiveQubits() {
        return this.useBellTest
            ? Math.max(2, Math.floor(this.numQubits / 2) * 2)
            : this.numQubits;
    }

    get totalRawBits() {
        return this.effectiveQubits * this.shots;
    }

    get storagePercent() {
        return Math.min(
            100,
            Math.round((MAX_STORABLE_BITS / this.totalRawBits) * 100)
        );
    }

    get storageWarning() {
        if (this.totalRawBits <= MAX_STORABLE_BITS) {
            return null;
        }
        const stored = MAX_STORABLE_BITS.toLocaleString();
        const total = this.totalRawBits.toLocaleString();
        const maxShots = Math.floor(MAX_STORABLE_BITS / this.effectiveQubits);
        return `Storage limit: ${stored} of ${total} bits stored (${this.storagePercent}%). Use \u2264${maxShots.toLocaleString()} shots for full storage at ${this.effectiveQubits} qubits.`;
    }

    get storageBarStyle() {
        const pct = this.storagePercent;
        const color =
            pct >= 100 ? '#2e844a' : pct >= 75 ? '#fe9339' : '#ea001e';
        return `width:${pct}%;background:${color};height:4px;border-radius:2px;transition:width 0.2s`;
    }

    get storageBarTrackStyle() {
        return 'width:100%;background:#d8d8d8;height:4px;border-radius:2px;margin-top:4px';
    }

    // ── Handlers ──────────────────────────────────────────────
    handleBackendChange(event) {
        this.backend = event.detail.value;
        this._clampToBackendLimits();
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
        // When switching to Bell test, snap qubits to nearest even number >= 2
        if (this.useBellTest && this.numQubits % 2 !== 0) {
            this.numQubits = Math.max(2, this.numQubits + 1);
        }
        if (this.useBellTest && this.numQubits < 2) {
            this.numQubits = 2;
        }
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

    // ── Private helpers ───────────────────────────────────────
    _clampToBackendLimits() {
        const info = this.selectedBackendInfo;
        if (!info) return;
        if (this.numQubits > info.qubits) {
            this.numQubits = this.useBellTest
                ? Math.floor(info.qubits / 2) * 2
                : info.qubits;
        }
        if (info.maxShots && this.shots > info.maxShots) {
            this.shots = info.maxShots;
        }
    }
}
