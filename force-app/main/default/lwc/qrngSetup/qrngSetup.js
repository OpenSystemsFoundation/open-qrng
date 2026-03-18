import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';
import testConnection from '@salesforce/apex/QRNGSetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/QRNGSetupController.getAvailableBackends';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';
import discoverInstances from '@salesforce/apex/QRNGSetupController.discoverInstances';
import getAllBackendHealth from '@salesforce/apex/QRNGSetupController.getAllBackendHealth';
import refreshAllBackendHealth from '@salesforce/apex/QRNGSetupController.refreshAllBackendHealth';
import verifyBackendQuantum from '@salesforce/apex/QRNGSetupController.verifyBackendQuantum';
import startSweeper from '@salesforce/apex/QRNGSetupController.startSweeper';
import stopSweeper from '@salesforce/apex/QRNGSetupController.stopSweeper';
import startIntegrityCheck from '@salesforce/apex/QRNGSetupController.startIntegrityCheck';
import stopIntegrityCheck from '@salesforce/apex/QRNGSetupController.stopIntegrityCheck';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COMPLETE_CHANNEL = '/event/OpenSF__QRNG_Complete__e';

export default class QrngSetup extends LightningElement {
    @track apiKey = '';
    @track hasApiKey = false;
    @track instanceCRN = '';
    @track defaultBackend = '';
    @track defaultShots = 1024;
    @track isConnected = false;
    @track isTestingConnection = false;
    @track connectionMessage = '';
    @track backendOptions = [];
    @track totalJobs = 0;
    @track completedJobs = 0;
    @track totalCertificates = 0;
    @track useLeastBusy = false;
    @track pollIntervalMinutes = 5;
    @track sweeperActive = false;
    @track isDiscoveringCRN = false;
    @track backendHealthList = [];
    @track isLoadingHealth = false;
    @track verifyingBackend = null;
    @track verificationJobId = null;
    @track integrityCheckActive = false;
    @track integrityCheckHour = 2;

    _completeSubscription;

    connectedCallback() {
        subscribe(COMPLETE_CHANNEL, -1, () => {
            this.loadBackendHealth();
        }).then((sub) => {
            this._completeSubscription = sub;
        });
        onError((error) => {
            console.error('empApi error in qrngSetup:', error);
        });
    }

    disconnectedCallback() {
        if (this._completeSubscription) {
            unsubscribe(this._completeSubscription);
            this._completeSubscription = null;
        }
    }

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) {
            this.defaultBackend = data.defaultBackend || '';
            this.defaultShots = data.defaultShots || 1024;
            this.hasApiKey = data.hasApiKey || false;
            if (data.hasCRN) {
                this.instanceCRN = data.crnValue || '';
            }
            this.useLeastBusy = data.useLeastBusy || false;
            if (this.useLeastBusy) {
                this.defaultBackend = '__least_busy__';
            }
            this.pollIntervalMinutes = data.pollIntervalMinutes || 5;
            this.sweeperActive = data.sweeperActive || false;
            this.integrityCheckActive = data.integrityCheckActive || false;
            this.integrityCheckHour =
                data.integrityCheckHour != null ? data.integrityCheckHour : 2;

            // Load cached backends into dropdown
            if (data.cachedBackends && data.cachedBackends.length > 0) {
                this.backendOptions = this.buildBackendOptions(
                    data.cachedBackends
                );
            }

            // Auto-connect if API key is configured
            if (data.hasApiKey && !this.isConnected) {
                this.handleTestConnection();
            }

            // Load stored backend health
            this.loadBackendHealth();
        }
    }

    @wire(getUsageStats)
    wiredStats({ data }) {
        if (data) {
            this.totalJobs = data.totalJobs || 0;
            this.completedJobs = data.completedJobs || 0;
            this.totalCertificates = data.totalCertificates || 0;
        }
    }

    get connectionStatusLabel() {
        return this.isConnected ? 'Connected' : 'Not Connected';
    }

    get connectionBadgeClass() {
        return this.isConnected
            ? 'slds-badge slds-theme_success'
            : 'slds-badge';
    }

    handleApiKeyChange(event) {
        this.apiKey = event.target.value;
    }

    handleChangeApiKey() {
        this.hasApiKey = false;
        this.apiKey = '';
    }

    handleCRNChange(event) {
        this.instanceCRN = event.target.value;
    }

    handleBackendChange(event) {
        const val = event.detail.value;
        if (val === '__least_busy__') {
            this.useLeastBusy = true;
            this.defaultBackend = '';
        } else {
            this.useLeastBusy = false;
            this.defaultBackend = val;
        }
    }

    handleShotsChange(event) {
        this.defaultShots = parseInt(event.target.value, 10);
    }

    handleLeastBusyChange(event) {
        this.useLeastBusy = event.target.checked;
    }

    handlePollIntervalChange(event) {
        this.pollIntervalMinutes = parseInt(event.target.value, 10);
    }

    async handleTestConnection() {
        this.isTestingConnection = true;
        try {
            const result = await testConnection();
            this.isConnected = result.connected;
            this.connectionMessage = result.message;

            if (result.connected) {
                // Fetch available backends
                try {
                    const backends = await getAvailableBackends();
                    if (backends && backends.length > 0) {
                        this.backendOptions =
                            this.buildBackendOptions(backends);
                    }
                } catch (backendErr) {
                    // Non-critical
                    console.warn('Could not fetch backends:', backendErr);
                }
            }
        } catch (error) {
            this.isConnected = false;
            this.connectionMessage = 'Error: ' + this.reduceErrors(error);
        } finally {
            this.isTestingConnection = false;
        }
    }

    async handleSaveSettings() {
        try {
            // null means "keep existing" — only send if user entered a new value
            const keyToSave = this.hasApiKey ? null : this.apiKey || null;
            const crnToSave = this.instanceCRN || null;
            await saveSettings({
                apiKey: keyToSave,
                instanceCRN: crnToSave,
                defaultBackend: this.defaultBackend,
                defaultShots: this.defaultShots,
                useBellTest: false,
                useLeastBusy: this.useLeastBusy,
                pollIntervalMinutes: this.pollIntervalMinutes
            });
            // If a new key was saved, mark as configured
            if (keyToSave) {
                this.hasApiKey = true;
                this.apiKey = '';
            }
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Settings saved successfully',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    async handleDiscoverCRN() {
        this.isDiscoveringCRN = true;
        try {
            const instances = await discoverInstances();
            if (instances && instances.length === 1) {
                this.instanceCRN = instances[0].crn;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'CRN Found',
                        message: `Auto-detected instance: ${instances[0].name}`,
                        variant: 'success'
                    })
                );
            } else if (instances && instances.length > 1) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Multiple Instances',
                        message: `Found ${instances.length} instances. Please select one manually.`,
                        variant: 'info'
                    })
                );
            } else {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'No Instances',
                        message:
                            'No IBM Quantum instances found for this account.',
                        variant: 'warning'
                    })
                );
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Discovery Failed',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isDiscoveringCRN = false;
        }
    }

    async loadBackendHealth() {
        try {
            const backends = await getAllBackendHealth();
            this.backendHealthList = this.mapBackendHealth(backends);
        } catch (error) {
            // Silently fail — table just stays empty
            console.warn('Could not load backend health:', error);
        }
    }

    async handleRefreshHealth() {
        this.isLoadingHealth = true;
        try {
            const backends = await refreshAllBackendHealth();
            this.backendHealthList = this.mapBackendHealth(backends);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Health Refreshed',
                    message: `Updated ${this.backendHealthList.length} backends from IBM.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Health Check Failed',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoadingHealth = false;
        }
    }

    mapBackendHealth(backends) {
        return backends.map((b) => {
            const fidelity = this.computeFidelityScore(b);
            return {
                id: b.id,
                name: b.name,
                status: b.status || '\u2014',
                qubits: b.qubits || 0,
                queueLength: b.queueLength != null ? b.queueLength : '\u2014',
                processor: b.processorFamily
                    ? `${b.processorFamily} ${b.processorRevision || ''}`
                    : '\u2014',
                avgT1: this.formatTime(b.avgT1),
                avgT2: this.formatTime(b.avgT2),
                gateError: this.formatPercent(b.gateError),
                readoutError: this.formatPercent(b.readoutError),
                lastSynced: b.lastSynced,
                statusClass:
                    b.status === 'online'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error',
                fidelityScore: fidelity.label,
                fidelityClass: `fidelity-badge fidelity-${fidelity.tier}`,
                fidelityTitle: fidelity.breakdown,
                chshSValue: b.chshSValue ? Number(b.chshSValue).toFixed(3) : '\u2014',
                chshVerifiedAt: b.chshVerifiedAt,
                quantumVerified: b.quantumVerified,
                verificationBadge: b.quantumVerified
                    ? 'Verified'
                    : b.chshSValue
                      ? 'Failed'
                      : 'Unverified',
                verificationClass: b.quantumVerified
                    ? 'slds-badge slds-theme_success'
                    : b.chshSValue
                      ? 'slds-badge slds-theme_error'
                      : 'slds-badge'
            };
        });
    }

    /**
     * Composite fidelity score from gate error, readout error, T1, and T2.
     * Weights: gate 40%, readout 25%, T1 20%, T2 15%.
     * T1 reference: 300µs = 100, <20µs = 0.  T2 reference: 200µs = 100, <10µs = 0.
     */
    computeFidelityScore(backend) {
        const ge = backend.gateError;
        const re = backend.readoutError;
        const t1 = backend.avgT1;
        const t2 = backend.avgT2;

        // If no calibration data at all, return N/A
        if (ge == null && re == null && t1 == null && t2 == null) {
            return {
                label: '\u2014',
                tier: 'none',
                breakdown: 'No calibration data'
            };
        }

        let score = 0;
        let totalWeight = 0;
        const parts = [];

        // Gate fidelity: (1 - error) * 100, weight 40%
        if (ge != null && !isNaN(Number(ge))) {
            const gateScore = Math.max(0, (1 - Number(ge)) * 100);
            score += gateScore * 0.4;
            totalWeight += 0.4;
            parts.push(`Gate: ${gateScore.toFixed(1)}`);
        }

        // Readout fidelity: (1 - error) * 100, weight 25%
        if (re != null && !isNaN(Number(re))) {
            const readoutScore = Math.max(0, (1 - Number(re)) * 100);
            score += readoutScore * 0.25;
            totalWeight += 0.25;
            parts.push(`Readout: ${readoutScore.toFixed(1)}`);
        }

        // T1 coherence: linear scale 20µs→0, 300µs→100, weight 20%
        if (t1 != null && !isNaN(Number(t1))) {
            const t1Score = Math.min(
                100,
                Math.max(0, ((Number(t1) - 20) / 280) * 100)
            );
            score += t1Score * 0.2;
            totalWeight += 0.2;
            parts.push(`T1: ${t1Score.toFixed(1)}`);
        }

        // T2 coherence: linear scale 10µs→0, 200µs→100, weight 15%
        if (t2 != null && !isNaN(Number(t2))) {
            const t2Score = Math.min(
                100,
                Math.max(0, ((Number(t2) - 10) / 190) * 100)
            );
            score += t2Score * 0.15;
            totalWeight += 0.15;
            parts.push(`T2: ${t2Score.toFixed(1)}`);
        }

        // Normalize if not all metrics available
        const normalized = totalWeight > 0 ? score / totalWeight : 0;
        const rounded = Math.round(normalized);

        let tier;
        if (rounded >= 90) tier = 'excellent';
        else if (rounded >= 75) tier = 'good';
        else if (rounded >= 50) tier = 'fair';
        else tier = 'poor';

        return {
            label: `${rounded}`,
            tier,
            breakdown: parts.join(' | ')
        };
    }

    get hasBackendHealth() {
        return this.backendHealthList.length > 0;
    }

    formatTime(val) {
        if (val == null || val === undefined) return '—';
        const n = Number(val);
        if (isNaN(n)) return '—';
        if (n > 1000) return (n / 1000).toFixed(1) + ' ms';
        return n.toFixed(1) + ' us';
    }

    formatPercent(val) {
        if (val == null || val === undefined) return '—';
        const n = Number(val);
        if (isNaN(n)) return '—';
        return (n * 100).toFixed(3) + '%';
    }

    buildBackendOptions(backends) {
        const options = backends.map((b) => {
            const statusStr =
                typeof b.status === 'object'
                    ? b.status.name || 'unknown'
                    : b.status || 'unknown';
            return {
                label: `${b.name} (${b.qubits} qubits, ${statusStr})`,
                value: b.name
            };
        });
        // Add "Least Busy (auto)" option at the top
        options.unshift({
            label: 'Least Busy (auto-select)',
            value: '__least_busy__'
        });
        return options;
    }

    async handleToggleSweeper() {
        try {
            if (this.sweeperActive) {
                await stopSweeper();
                this.sweeperActive = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Sweeper Stopped',
                        message: 'Background job sweeper has been stopped.',
                        variant: 'info'
                    })
                );
            } else {
                await startSweeper();
                this.sweeperActive = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Sweeper Started',
                        message: `Background job sweeper running every ${this.pollIntervalMinutes} minutes.`,
                        variant: 'success'
                    })
                );
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Sweeper Error',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    get sweeperButtonLabel() {
        return this.sweeperActive ? 'Stop Job Sweeper' : 'Start Job Sweeper';
    }

    get sweeperButtonVariant() {
        return this.sweeperActive ? 'destructive' : 'brand';
    }

    get sweeperStatusLabel() {
        return this.sweeperActive ? 'Active' : 'Inactive';
    }

    get sweeperBadgeClass() {
        return this.sweeperActive
            ? 'slds-badge slds-theme_success'
            : 'slds-badge';
    }

    // ── Integrity Verification ──────────────────────────────────

    handleIntegrityHourChange(event) {
        this.integrityCheckHour = parseInt(event.detail.value, 10);
    }

    async handleToggleIntegrityCheck() {
        try {
            if (this.integrityCheckActive) {
                await stopIntegrityCheck();
                this.integrityCheckActive = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Integrity Check Stopped',
                        message:
                            'Nightly integrity verification has been stopped.',
                        variant: 'info'
                    })
                );
            } else {
                await startIntegrityCheck();
                this.integrityCheckActive = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Integrity Check Started',
                        message: `Nightly integrity verification scheduled at ${this.integrityCheckHour}:00.`,
                        variant: 'success'
                    })
                );
            }
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Integrity Check Error',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    get integrityButtonLabel() {
        return this.integrityCheckActive
            ? 'Stop Integrity Check'
            : 'Start Integrity Check';
    }

    get integrityButtonVariant() {
        return this.integrityCheckActive ? 'destructive' : 'brand';
    }

    get integrityStatusLabel() {
        return this.integrityCheckActive ? 'Active' : 'Inactive';
    }

    get integrityBadgeClass() {
        return this.integrityCheckActive
            ? 'slds-badge slds-theme_success'
            : 'slds-badge';
    }

    async handleVerifyBackend(event) {
        const backendName = event.target.dataset.backend;
        this.verifyingBackend = backendName;
        try {
            const jobId = await verifyBackendQuantum({ backendName });
            this.verificationJobId = jobId;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Verification Submitted',
                    message: `CHSH verification job submitted for ${backendName}.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Verification Failed',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.verifyingBackend = null;
        }
    }

    async handleVerifyAll() {
        const backends = this.backendHealthList.filter(
            (b) => b.status === 'online'
        );
        if (backends.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Backends',
                    message: 'No online backends to verify.',
                    variant: 'warning'
                })
            );
            return;
        }
        this.verifyingBackend = 'all';
        const promises = backends.map((b) =>
            verifyBackendQuantum({ backendName: b.name }).catch((err) => {
                console.warn(`Verify failed for ${b.name}:`, err);
                return null;
            })
        );
        const results = await Promise.all(promises);
        this.verifyingBackend = null;
        const succeeded = results.filter((r) => r != null);
        if (succeeded.length > 0) {
            this.verificationJobId = succeeded[succeeded.length - 1];
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Verification Submitted',
                message: `Submitted ${succeeded.length} of ${backends.length} backend verification jobs.`,
                variant: 'success'
            })
        );
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
