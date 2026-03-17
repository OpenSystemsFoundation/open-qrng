import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';
import testConnection from '@salesforce/apex/QRNGSetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/QRNGSetupController.getAvailableBackends';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';
import discoverInstances from '@salesforce/apex/QRNGSetupController.discoverInstances';
import getBackendHealth from '@salesforce/apex/QRNGSetupController.getBackendHealth';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngSetup extends LightningElement {
    @track apiKey = '';
    @track instanceCRN = '';
    @track defaultBackend = 'ibm_kingston';
    @track defaultShots = 1024;
    @track useBellTest = false;
    @track isConnected = false;
    @track isTestingConnection = false;
    @track connectionMessage = '';
    @track backendOptions = [
        { label: 'ibm_kingston (Heron r2, 156 qubits)', value: 'ibm_kingston' }
    ];
    @track totalJobs = 0;
    @track completedJobs = 0;
    @track totalCertificates = 0;
    @track isDiscoveringCRN = false;
    @track backendHealth = null;
    @track isLoadingHealth = false;

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) {
            this.defaultBackend = data.defaultBackend || 'ibm_kingston';
            this.defaultShots = data.defaultShots || 1024;
            this.useBellTest = data.useBellTest || false;
            if (data.hasApiKey) {
                this.apiKey = '********'; // Mask existing key
            }
            if (data.hasCRN) {
                this.instanceCRN = '********'; // Mask existing CRN
            }
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

    handleCRNChange(event) {
        this.instanceCRN = event.target.value;
    }

    handleBackendChange(event) {
        this.defaultBackend = event.detail.value;
    }

    handleShotsChange(event) {
        this.defaultShots = parseInt(event.target.value, 10);
    }

    handleBellTestChange(event) {
        this.useBellTest = event.target.checked;
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
                        this.backendOptions = backends.map((b) => {
                            const statusStr =
                                typeof b.status === 'object'
                                    ? b.status.name || 'unknown'
                                    : b.status || 'unknown';
                            return {
                                label: `${b.name} (${b.qubits} qubits, ${statusStr})`,
                                value: b.name
                            };
                        });
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
            const keyToSave = this.apiKey === '********' ? null : this.apiKey;
            const crnToSave =
                this.instanceCRN === '********' ? null : this.instanceCRN;
            await saveSettings({
                apiKey: keyToSave,
                instanceCRN: crnToSave,
                defaultBackend: this.defaultBackend,
                defaultShots: this.defaultShots,
                useBellTest: this.useBellTest
            });
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

    async handleRefreshHealth() {
        this.isLoadingHealth = true;
        try {
            this.backendHealth = await getBackendHealth({
                backendName: this.defaultBackend
            });
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

    get hasBackendHealth() {
        return this.backendHealth !== null;
    }

    get formattedT1() {
        if (!this.backendHealth?.avgT1) return 'N/A';
        const val = this.backendHealth.avgT1;
        // API returns in μs; display accordingly
        if (val > 1000) return (val / 1000).toFixed(1) + ' ms';
        return val.toFixed(1) + ' μs';
    }

    get formattedT2() {
        if (!this.backendHealth?.avgT2) return 'N/A';
        const val = this.backendHealth.avgT2;
        if (val > 1000) return (val / 1000).toFixed(1) + ' ms';
        return val.toFixed(1) + ' μs';
    }

    get formattedGateError() {
        return this.backendHealth?.avgGateError
            ? (this.backendHealth.avgGateError * 100).toFixed(3) + '%'
            : 'N/A';
    }

    get formattedReadoutError() {
        return this.backendHealth?.avgReadoutError
            ? (this.backendHealth.avgReadoutError * 100).toFixed(2) + '%'
            : 'N/A';
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
