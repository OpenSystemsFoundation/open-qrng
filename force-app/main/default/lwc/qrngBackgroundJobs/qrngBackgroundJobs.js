import { LightningElement, api, track } from 'lwc';
import getSettings from '@salesforce/apex/SetupController.getSettings';
import startSweeper from '@salesforce/apex/SetupController.startSweeper';
import stopSweeper from '@salesforce/apex/SetupController.stopSweeper';
import startIntegrityCheck from '@salesforce/apex/SetupController.startIntegrityCheck';
import stopIntegrityCheck from '@salesforce/apex/SetupController.stopIntegrityCheck';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/qrngUtils';

export default class QrngBackgroundJobs extends LightningElement {
    @track sweeperActive = false;
    @track pollIntervalMinutes = 5;
    @track integrityCheckActive = false;
    @track integrityCheckHour = 2;
    @track loadError;

    _statusLoaded = false;

    connectedCallback() {
        // Load our own state so the component is correct even when it is
        // rendered lazily (e.g. inside a lightning-tab that activates late).
        this._loadStatus();
    }

    async _loadStatus() {
        try {
            const data = await getSettings();
            if (data) {
                this._statusLoaded = true;
                this.loadError = undefined;
                this._applySettings(data);
            }
        } catch (error) {
            this.loadError = reduceErrors(error);
        }
    }

    /**
     * Backward-compatible push API. Internal loading is authoritative:
     * once the component has loaded its own status, pushed settings are
     * ignored so a stale parent snapshot cannot overwrite fresh state.
     */
    @api
    initSettings(data) {
        if (this._statusLoaded) return;
        this._applySettings(data);
    }

    _applySettings(data) {
        this.sweeperActive = data.sweeperActive || false;
        this.pollIntervalMinutes = data.pollIntervalMinutes || 5;
        this.integrityCheckActive = data.integrityCheckActive || false;
        this.integrityCheckHour =
            data.integrityCheckHour != null ? data.integrityCheckHour : 2;
    }

    // ── Sweeper ──────────────────────────────────────

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

    handlePollIntervalChange(event) {
        const value = parseInt(event.target.value, 10);
        if (!isNaN(value)) {
            this.pollIntervalMinutes = value;
        }
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
                    message: reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }

    // ── Integrity Verification ──────────────────────────────────

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

    handleIntegrityHourChange(event) {
        const value = parseInt(event.detail.value, 10);
        if (!isNaN(value)) {
            this.integrityCheckHour = value;
        }
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
                    message: reduceErrors(error),
                    variant: 'error'
                })
            );
        }
    }
}
