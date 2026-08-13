import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';

const COMPLETE_CHANNEL = '/event/Quantum_Job_Complete__e';

export default class QuantumFairApp extends LightningElement {
    @track activeJobs = [];

    _completeSubscription;
    _disconnected = false;

    get hasActiveJobs() {
        return this.activeJobs.length > 0;
    }

    connectedCallback() {
        this._disconnected = false;
        subscribe(COMPLETE_CHANNEL, -1, () => {
            this._refreshHealthMonitor();
        }).then((sub) => {
            if (this._disconnected) {
                // Component detached before subscribe resolved —
                // release the subscription instead of leaking it.
                if (sub) {
                    unsubscribe(sub);
                }
                return;
            }
            this._completeSubscription = sub;
        });
        onError((error) => {
            console.error('empApi error in quantumFairApp:', error);
        });
    }

    disconnectedCallback() {
        this._disconnected = true;
        if (this._completeSubscription) {
            unsubscribe(this._completeSubscription);
            this._completeSubscription = null;
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
