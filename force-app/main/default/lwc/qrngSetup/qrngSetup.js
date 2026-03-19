import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';

export default class QrngSetup extends LightningElement {
    @track hasApiKey = false;
    @track instanceCRN = '';
    @track backendOptions = [];
    @track totalJobs = 0;
    @track completedJobs = 0;
    @track totalCertificates = 0;

    _settingsData = null;
    _childrenInitialized = false;
    _autoConnected = false;

    @wire(getSettings)
    wiredSettings({ data }) {
        if (data) {
            this.hasApiKey = data.hasApiKey || false;
            if (data.hasCRN) {
                this.instanceCRN = data.crnValue || '';
            }

            if (data.cachedBackends && data.cachedBackends.length > 0) {
                this.backendOptions = this.buildBackendOptions(
                    data.cachedBackends
                );
            }

            this._settingsData = data;
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

    renderedCallback() {
        if (this._settingsData && !this._childrenInitialized) {
            this._childrenInitialized = true;

            const settingsPanel = this.template.querySelector(
                'c-qrng-settings-panel'
            );
            if (settingsPanel) {
                settingsPanel.initSettings(this._settingsData);
            }
        }

        // Auto-test connection once the connection component is rendered
        if (this.hasApiKey && !this._autoConnected) {
            const conn = this.template.querySelector('c-qrng-connection-setup');
            if (conn) {
                this._autoConnected = true;
                conn.testConnectionProgrammatic();
            }
        }
    }

    handleBackendsLoaded(event) {
        const backends = event.detail.backends;
        if (backends && backends.length > 0) {
            this.backendOptions = this.buildBackendOptions(backends);
        }
    }

    handleApiKeyChange(event) {
        this.hasApiKey = event.detail.hasApiKey;
        // Reset auto-connect flag so new key triggers connection test
        this._autoConnected = false;
    }

    handleCRNChange(event) {
        this.instanceCRN = event.detail.crn;
    }

    handleSettingsSaved() {
        const conn = this.template.querySelector('c-qrng-connection-setup');
        if (conn) {
            conn.markApiKeyConfigured();
        }
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
        options.unshift({
            label: 'Least Busy (auto-select)',
            value: '__least_busy__'
        });
        return options;
    }
}
