import { LightningElement, api, track } from 'lwc';
import startSweeper from '@salesforce/apex/SetupController.startSweeper';
import stopSweeper from '@salesforce/apex/SetupController.stopSweeper';
import startIntegrityCheck from '@salesforce/apex/SetupController.startIntegrityCheck';
import stopIntegrityCheck from '@salesforce/apex/SetupController.stopIntegrityCheck';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QrngBackgroundJobs extends LightningElement {
    @track sweeperActive = false;
    @track pollIntervalMinutes = 5;
    @track integrityCheckActive = false;
    @track integrityCheckHour = 2;

    @api
    initSettings(data) {
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
        this.pollIntervalMinutes = parseInt(event.target.value, 10);
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

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
