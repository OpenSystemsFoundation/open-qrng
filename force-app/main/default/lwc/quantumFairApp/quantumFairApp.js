import { LightningElement, track, wire } from 'lwc';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

const COMPLETE_CHANNEL = '/event/OpenSF__QRNG_Complete__e';

export default class QuantumFairApp extends LightningElement {
    @track activeJobs = [];

    _completeSubscription;
    _settingsInitialized = false;

    get hasActiveJobs() {
        return this.activeJobs.length > 0;
    }

    connectedCallback() {
        subscribe(COMPLETE_CHANNEL, -1, () => {
            this._refreshHealthMonitor();
        }).then((sub) => {
            this._completeSubscription = sub;
        });
        onError((error) => {
            console.error('empApi error in quantumFairApp:', error);
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
        if (data && !this._settingsInitialized) {
            this._settingsInitialized = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this._initOperationsTab(data);
            }, 0);
        }
    }

    _initOperationsTab(data) {
        const bgJobs = this.template.querySelector('c-qrng-background-jobs');
        if (bgJobs) {
            bgJobs.initSettings(data);
        }
        const healthMon = this.template.querySelector('c-qrng-health-monitor');
        if (healthMon) {
            healthMon.loadBackendHealth();
        }
    }

    _refreshHealthMonitor() {
        const healthMon = this.template.querySelector('c-qrng-health-monitor');
        if (healthMon) {
            healthMon.loadBackendHealth();
        }
    }

    handleJobSubmitted(event) {
        const jobId = event.detail.jobId;
        // Avoid duplicates
        if (this.activeJobs.some((j) => j.id === jobId)) return;
        this.activeJobs = [
            ...this.activeJobs,
            { id: jobId, key: jobId, completed: false }
        ];
        // Notify job dashboard to refresh
        const dashboard = this.template.querySelector('c-qrng-job-dashboard');
        if (dashboard) {
            dashboard.refreshJobs();
        }
    }

    handleJobComplete(event) {
        const jobId = event.detail.jobId;
        this.activeJobs = this.activeJobs.map((j) => {
            return j.id === jobId ? { ...j, completed: true } : j;
        });
    }

    handleDismissJob(event) {
        const jobId = event.currentTarget.dataset.jobid;
        this.activeJobs = this.activeJobs.filter((j) => j.id !== jobId);
    }
}
