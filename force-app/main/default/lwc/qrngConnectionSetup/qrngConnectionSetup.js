import { LightningElement, api, track } from 'lwc';
import testConnection from '@salesforce/apex/SetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/SetupController.getAvailableBackends';
import discoverInstances from '@salesforce/apex/SetupController.discoverInstances';
import saveSettings from '@salesforce/apex/SetupController.saveSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngConnectionSetup extends LightningElement {
    @track _hasApiKey = false;
    @track _instanceCRN = '';
    @track apiKey = '';
    @track isConnected = false;
    @track isTestingConnection = false;
    @track connectionMessage = '';
    @track isDiscoveringCRN = false;
    @track isSavingKey = false;

    @api
    get hasApiKey() {
        return this._hasApiKey;
    }
    set hasApiKey(value) {
        this._hasApiKey = value;
    }

    @api
    get instanceCRN() {
        return this._instanceCRN;
    }
    set instanceCRN(value) {
        this._instanceCRN = value;
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

    async handleSaveApiKey() {
        if (!this.apiKey) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Key',
                    message: 'Please enter your IBM Quantum API key.',
                    variant: 'warning'
                })
            );
            return;
        }
        this.isSavingKey = true;
        try {
            await saveSettings({
                apiKey: this.apiKey,
                instanceCRN: null,
                defaultBackend: null,
                defaultShots: null,
                useBellTest: null,
                useLeastBusy: null,
                pollIntervalMinutes: null,
                complianceEmail: null
            });
            this._hasApiKey = true;
            this.apiKey = '';
            this.dispatchEvent(
                new CustomEvent('apikeychange', {
                    detail: { hasApiKey: true }
                })
            );
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'API Key Saved',
                    message:
                        'Your IBM Quantum API key has been saved. You can now test the connection.',
                    variant: 'success'
                })
            );
            // Auto-test connection after saving key
            this.handleTestConnection();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save Failed',
                    message: this.reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isSavingKey = false;
        }
    }

    handleChangeApiKey() {
        this._hasApiKey = false;
        this.apiKey = '';
        this.dispatchEvent(
            new CustomEvent('apikeychange', { detail: { hasApiKey: false } })
        );
    }

    handleCRNChange(event) {
        this._instanceCRN = event.target.value;
        this.dispatchEvent(
            new CustomEvent('crnchange', {
                detail: { crn: this._instanceCRN }
            })
        );
    }

    async handleTestConnection() {
        this.isTestingConnection = true;
        try {
            const result = await testConnection();
            this.isConnected = result.connected;
            this.connectionMessage = result.message;

            if (result.connected) {
                try {
                    const backends = await getAvailableBackends();
                    if (backends && backends.length > 0) {
                        this.dispatchEvent(
                            new CustomEvent('backendsloaded', {
                                detail: { backends }
                            })
                        );
                    }
                } catch (backendErr) {
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

    async handleDiscoverCRN() {
        this.isDiscoveringCRN = true;
        try {
            const instances = await discoverInstances();
            if (instances && instances.length === 1) {
                this._instanceCRN = instances[0].crn;
                this.dispatchEvent(
                    new CustomEvent('crnchange', {
                        detail: { crn: this._instanceCRN }
                    })
                );
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

    @api
    testConnectionProgrammatic() {
        return this.handleTestConnection();
    }

    @api
    get apiKeyForSave() {
        return this._hasApiKey ? null : this.apiKey || null;
    }

    @api
    markApiKeyConfigured() {
        if (this.apiKey) {
            this._hasApiKey = true;
            this.apiKey = '';
            this.dispatchEvent(
                new CustomEvent('apikeychange', {
                    detail: { hasApiKey: true }
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
