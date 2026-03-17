import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';
import testConnection from '@salesforce/apex/QRNGSetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/QRNGSetupController.getAvailableBackends';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';
import discoverInstances from '@salesforce/apex/QRNGSetupController.discoverInstances';
import getAllBackendHealth from '@salesforce/apex/QRNGSetupController.getAllBackendHealth';
import refreshAllBackendHealth from '@salesforce/apex/QRNGSetupController.refreshAllBackendHealth';
import startSweeper from '@salesforce/apex/QRNGSetupController.startSweeper';
import stopSweeper from '@salesforce/apex/QRNGSetupController.stopSweeper';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngSetup extends LightningElement {
    @track apiKey = '';
    @track instanceCRN = '';
    @track defaultBackend = '';
    @track defaultShots = 1024;
    @track useBellTest = false;
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

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) {
            this.defaultBackend = data.defaultBackend || '';
            this.defaultShots = data.defaultShots || 1024;
            this.useBellTest = data.useBellTest || false;
            if (data.hasApiKey) {
                this.apiKey = '********'; // Mask existing key
            }
            if (data.hasCRN) {
                this.instanceCRN = '********'; // Mask existing CRN
            }
            this.useLeastBusy = data.useLeastBusy || false;
            if (this.useLeastBusy) {
                this.defaultBackend = '__least_busy__';
            }
            this.pollIntervalMinutes = data.pollIntervalMinutes || 5;
            this.sweeperActive = data.sweeperActive || false;

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

    handleBellTestChange(event) {
        this.useBellTest = event.target.checked;
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
            const keyToSave = this.apiKey === '********' ? null : this.apiKey;
            const crnToSave =
                this.instanceCRN === '********' ? null : this.instanceCRN;
            await saveSettings({
                apiKey: keyToSave,
                instanceCRN: crnToSave,
                defaultBackend: this.defaultBackend,
                defaultShots: this.defaultShots,
                useBellTest: this.useBellTest,
                useLeastBusy: this.useLeastBusy,
                pollIntervalMinutes: this.pollIntervalMinutes
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

    async loadBackendHealth() {
        try {
            const backends = await getAllBackendHealth();
            this.backendHealthList = backends.map((b) => ({
                id: b.Id,
                name: b.Name,
                status: b.Status__c || '—',
                qubits: b.Num_Qubits__c || 0,
                queueLength:
                    b.Queue_Length__c != null ? b.Queue_Length__c : '—',
                processor: b.Processor_Family__c
                    ? `${b.Processor_Family__c} ${b.Processor_Revision__c || ''}`
                    : '—',
                avgT1: this.formatTime(b.Avg_T1_us__c),
                avgT2: this.formatTime(b.Avg_T2_us__c),
                gateError: this.formatPercent(b.Median_Gate_Error__c),
                readoutError: this.formatPercent(b.Median_Readout_Error__c),
                lastSynced: b.Last_Synced__c,
                statusClass:
                    b.Status__c === 'online'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error'
            }));
        } catch (error) {
            // Silently fail — table just stays empty
            console.warn('Could not load backend health:', error);
        }
    }

    async handleRefreshHealth() {
        this.isLoadingHealth = true;
        try {
            const backends = await refreshAllBackendHealth();
            this.backendHealthList = backends.map((b) => ({
                id: b.Id,
                name: b.Name,
                status: b.Status__c || '—',
                qubits: b.Num_Qubits__c || 0,
                queueLength:
                    b.Queue_Length__c != null ? b.Queue_Length__c : '—',
                processor: b.Processor_Family__c
                    ? `${b.Processor_Family__c} ${b.Processor_Revision__c || ''}`
                    : '—',
                avgT1: this.formatTime(b.Avg_T1_us__c),
                avgT2: this.formatTime(b.Avg_T2_us__c),
                gateError: this.formatPercent(b.Median_Gate_Error__c),
                readoutError: this.formatPercent(b.Median_Readout_Error__c),
                lastSynced: b.Last_Synced__c,
                statusClass:
                    b.Status__c === 'online'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error'
            }));
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

    get hasBackendHealth() {
        return this.backendHealthList.length > 0;
    }

    formatTime(val) {
        if (val == null) return '—';
        if (val > 1000) return (val / 1000).toFixed(1) + ' ms';
        return val.toFixed(1) + ' us';
    }

    formatPercent(val) {
        if (val == null) return '—';
        return (val * 100).toFixed(3) + '%';
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

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
