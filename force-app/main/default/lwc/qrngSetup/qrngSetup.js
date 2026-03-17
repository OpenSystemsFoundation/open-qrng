import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';
import testConnection from '@salesforce/apex/QRNGSetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/QRNGSetupController.getAvailableBackends';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngSetup extends LightningElement {
    @track apiKey = '';
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

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) {
            this.defaultBackend = data.defaultBackend || 'ibm_kingston';
            this.defaultShots = data.defaultShots || 1024;
            this.useBellTest = data.useBellTest || false;
            if (data.hasApiKey) {
                this.apiKey = '********'; // Mask existing key
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
                        this.backendOptions = backends.map((b) => ({
                            label: `${b.name} (${b.qubits} qubits, ${b.status})`,
                            value: b.name
                        }));
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
            await saveSettings({
                apiKey: keyToSave,
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

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
