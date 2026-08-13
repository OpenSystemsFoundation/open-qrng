import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAllBackendHealth from '@salesforce/apex/SetupController.getAllBackendHealth';
import refreshAllBackendHealth from '@salesforce/apex/SetupController.refreshAllBackendHealth';
import verifyBackendQuantum from '@salesforce/apex/SetupController.verifyBackendQuantum';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/qrngUtils';

export default class QrngHealthMonitor extends NavigationMixin(
    LightningElement
) {
    @track backendHealthList = [];
    @track isLoadingHealth = false;
    @track verifyingBackend = null;
    @track verificationJobId = null;
    @track lastRefreshed = null;

    get hasBackendHealth() {
        return this.backendHealthList.length > 0;
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshed) return '';
        return `Last updated: ${this.lastRefreshed}`;
    }

    connectedCallback() {
        this.loadBackendHealth();
    }

    /** @api - Can also be called by parent to trigger reload */
    @api
    loadBackendHealth() {
        getAllBackendHealth()
            .then((backends) => {
                this.backendHealthList = this.mapBackendHealth(backends);
                this.lastRefreshed = new Date().toLocaleString();
            })
            .catch((error) => {
                console.warn('Could not load backend health:', error);
            });
    }

    async handleRefreshHealth() {
        this.isLoadingHealth = true;
        try {
            const backends = await refreshAllBackendHealth();
            this.backendHealthList = this.mapBackendHealth(backends);
            this.lastRefreshed = new Date().toLocaleString();
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
                    message: reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isLoadingHealth = false;
        }
    }

    async handleVerifyBackend(event) {
        const backendName = event.target.dataset.backend;
        this.verifyingBackend = backendName;
        try {
            const jobId = await verifyBackendQuantum({ backendName });
            this.verificationJobId = jobId;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Verification Submitted',
                    message: `CHSH verification job submitted for ${backendName}.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Verification Failed',
                    message: reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.verifyingBackend = null;
        }
    }

    async handleVerifyAll() {
        const backends = this.backendHealthList.filter(
            (b) => b.status === 'online'
        );
        if (backends.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Backends',
                    message: 'No online backends to verify.',
                    variant: 'warning'
                })
            );
            return;
        }
        this.verifyingBackend = 'all';
        const promises = backends.map((b) =>
            verifyBackendQuantum({ backendName: b.name }).catch((err) => {
                console.warn(`Verify failed for ${b.name}:`, err);
                return null;
            })
        );
        const results = await Promise.all(promises);
        this.verifyingBackend = null;
        const succeeded = results.filter((r) => r != null);
        if (succeeded.length > 0) {
            this.verificationJobId = succeeded[succeeded.length - 1];
        }
        // "Submitted 0 of N" is a failure, not a success; partial is a warning
        const variant =
            succeeded.length === 0
                ? 'error'
                : succeeded.length < backends.length
                  ? 'warning'
                  : 'success';
        this.dispatchEvent(
            new ShowToastEvent({
                title:
                    succeeded.length === 0
                        ? 'Verification Failed'
                        : 'Verification Submitted',
                message: `Submitted ${succeeded.length} of ${backends.length} backend verification jobs.`,
                variant
            })
        );
    }

    handleNavigateToJob(event) {
        const jobId = event.currentTarget.dataset.jobid;
        if (jobId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: jobId,
                    objectApiName: 'Quantum_Job__c',
                    actionName: 'view'
                }
            });
        }
    }

    mapBackendHealth(backends) {
        return backends.map((b) => {
            const fidelity = this.computeFidelityScore(b);
            return {
                id: b.id,
                name: b.name,
                status: b.status || '\u2014',
                qubits: b.qubits || 0,
                queueLength: b.queueLength != null ? b.queueLength : '\u2014',
                processor: b.processorFamily
                    ? `${b.processorFamily} ${b.processorRevision || ''}`
                    : '\u2014',
                avgT1: this.formatTime(b.avgT1),
                avgT2: this.formatTime(b.avgT2),
                gateError: this.formatPercent(b.gateError),
                readoutError: this.formatPercent(b.readoutError),
                lastSynced: b.lastSynced,
                statusClass:
                    b.status === 'online'
                        ? 'slds-text-color_success'
                        : 'slds-text-color_error',
                fidelityScore: fidelity.label,
                fidelityClass: `fidelity-badge fidelity-${fidelity.tier}`,
                fidelityTitle: fidelity.breakdown,
                chshSValue: b.chshSValue
                    ? Number(b.chshSValue).toFixed(3)
                    : '\u2014',
                chshVerifiedAt: b.chshVerifiedAt,
                quantumVerified: b.quantumVerified,
                verificationBadge: b.quantumVerified
                    ? 'Verified'
                    : b.chshSValue
                      ? 'Failed'
                      : 'Unverified',
                verificationClass: b.quantumVerified
                    ? 'slds-badge slds-theme_success'
                    : b.chshSValue
                      ? 'slds-badge slds-theme_error'
                      : 'slds-badge',
                chshJobId: b.chshJobId,
                recordId: b.recordId,
                hasVerifyJob: !!b.chshJobId,
                verifyJobUrl: b.chshJobId
                    ? `/lightning/r/Quantum_Job__c/${b.chshJobId}/view`
                    : null
            };
        });
    }

    computeFidelityScore(backend) {
        const ge = backend.gateError;
        const re = backend.readoutError;
        const t1 = backend.avgT1;
        const t2 = backend.avgT2;

        if (ge == null && re == null && t1 == null && t2 == null) {
            return {
                label: '\u2014',
                tier: 'none',
                breakdown: 'No calibration data'
            };
        }

        let score = 0;
        let totalWeight = 0;
        const parts = [];

        if (ge != null && !isNaN(Number(ge))) {
            const gateScore = Math.max(0, (1 - Number(ge)) * 100);
            score += gateScore * 0.4;
            totalWeight += 0.4;
            parts.push(`Gate: ${gateScore.toFixed(1)}`);
        }

        if (re != null && !isNaN(Number(re))) {
            const readoutScore = Math.max(0, (1 - Number(re)) * 100);
            score += readoutScore * 0.25;
            totalWeight += 0.25;
            parts.push(`Readout: ${readoutScore.toFixed(1)}`);
        }

        if (t1 != null && !isNaN(Number(t1))) {
            const t1Score = Math.min(
                100,
                Math.max(0, ((Number(t1) - 20) / 280) * 100)
            );
            score += t1Score * 0.2;
            totalWeight += 0.2;
            parts.push(`T1: ${t1Score.toFixed(1)}`);
        }

        if (t2 != null && !isNaN(Number(t2))) {
            const t2Score = Math.min(
                100,
                Math.max(0, ((Number(t2) - 10) / 190) * 100)
            );
            score += t2Score * 0.15;
            totalWeight += 0.15;
            parts.push(`T2: ${t2Score.toFixed(1)}`);
        }

        const normalized = totalWeight > 0 ? score / totalWeight : 0;
        const rounded = Math.round(normalized);

        let tier;
        if (rounded >= 90) tier = 'excellent';
        else if (rounded >= 75) tier = 'good';
        else if (rounded >= 50) tier = 'fair';
        else tier = 'poor';

        return {
            label: `${rounded}`,
            tier,
            breakdown: parts.join(' | ')
        };
    }

    formatTime(val) {
        if (val == null || val === undefined) return '\u2014';
        const n = Number(val);
        if (isNaN(n)) return '\u2014';
        if (n > 1000) return (n / 1000).toFixed(1) + ' ms';
        return n.toFixed(1) + ' us';
    }

    formatPercent(val) {
        if (val == null || val === undefined) return '\u2014';
        const n = Number(val);
        if (isNaN(n)) return '\u2014';
        return (n * 100).toFixed(3) + '%';
    }
}
