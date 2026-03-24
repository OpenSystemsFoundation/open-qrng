import { LightningElement, api, track } from 'lwc';
import saveSettings from '@salesforce/apex/SetupController.saveSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngSettingsPanel extends LightningElement {
    @api backendOptions = [];
    @api hasApiKey = false;

    @track defaultBackend = '__least_busy__';
    @track defaultShots = 1024;
    @track useLeastBusy = true;
    @track pollIntervalMinutes = 5;
    @track complianceEmail = '';

    // Called by parent to initialize settings from wired data
    @api
    initSettings(data) {
        this.defaultShots = data.defaultShots || 1024;
        this.useLeastBusy =
            data.useLeastBusy !== false ? data.useLeastBusy || true : false;
        if (this.useLeastBusy || !data.defaultBackend) {
            this.defaultBackend = '__least_busy__';
            this.useLeastBusy = true;
        } else {
            this.defaultBackend = data.defaultBackend;
        }
        this.pollIntervalMinutes = data.pollIntervalMinutes || 5;
        this.complianceEmail = data.complianceEmail || '';
    }

    handleBackendChange(event) {
        const val = event.detail.value;
        if (val === '__least_busy__') {
            this.useLeastBusy = true;
            this.defaultBackend = '__least_busy__';
        } else {
            this.useLeastBusy = false;
            this.defaultBackend = val;
        }
    }

    handleShotsChange(event) {
        this.defaultShots = parseInt(event.target.value, 10);
    }

    handleComplianceEmailChange(event) {
        this.complianceEmail = event.target.value;
    }

    async handleSaveSettings() {
        try {
            // Request API key from parent via event
            this.dispatchEvent(
                new CustomEvent('requestapikey', {
                    bubbles: true,
                    composed: true
                })
            );

            await saveSettings({
                apiKey: null,
                instanceCRN: null,
                defaultBackend: this.useLeastBusy ? '' : this.defaultBackend,
                defaultShots: this.defaultShots,
                useBellTest: false,
                useLeastBusy: this.useLeastBusy,
                pollIntervalMinutes: this.pollIntervalMinutes,
                complianceEmail: this.complianceEmail
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Settings saved successfully',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('settingssaved'));
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
