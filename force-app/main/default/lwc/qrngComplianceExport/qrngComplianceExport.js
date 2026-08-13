import { LightningElement, track } from 'lwc';
import exportComplianceEvidence from '@salesforce/apex/SetupController.exportComplianceEvidence';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceErrors } from 'c/qrngUtils';

/** Format a Date as YYYY-MM-DD in the user's local time zone. */
function toLocalDateString(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

export default class QrngComplianceExport extends LightningElement {
    @track selectedFramework = 'ALL';
    @track startDate;
    @track endDate;
    @track isExporting = false;

    frameworkOptions = [
        { label: 'All Frameworks', value: 'ALL' },
        { label: 'ISO 27001', value: 'ISO_27001' },
        { label: 'SOC 2', value: 'SOC_2' },
        { label: 'NIST SP 800-90B', value: 'NIST_800_90B' },
        { label: 'GDPR', value: 'GDPR' },
        { label: 'eIDAS', value: 'EIDAS' }
    ];

    connectedCallback() {
        // Default to last 30 days, computed in the user's local time zone
        // (toISOString shifts the date near midnight for non-UTC users)
        const now = new Date();
        const thirtyDaysAgo = new Date(
            now.getTime() - 30 * 24 * 60 * 60 * 1000
        );
        this.endDate = toLocalDateString(now);
        this.startDate = toLocalDateString(thirtyDaysAgo);
    }

    handleFrameworkChange(event) {
        this.selectedFramework = event.detail.value;
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }

    async handleExport() {
        if (!this.startDate || !this.endDate) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Missing Dates',
                    message: 'Please select both start and end dates.',
                    variant: 'warning'
                })
            );
            return;
        }

        this.isExporting = true;
        try {
            const result = await exportComplianceEvidence({
                framework: this.selectedFramework,
                startDate: this.startDate,
                endDate: this.endDate
            });

            // Trigger download as JSON file
            this.downloadJson(result, this.selectedFramework);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Export Complete',
                    message: 'Compliance evidence package downloaded.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Export Failed',
                    message: reduceErrors(error),
                    variant: 'error'
                })
            );
        } finally {
            this.isExporting = false;
        }
    }

    downloadJson(jsonString, framework) {
        const blob = new Blob([jsonString], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `quantumfair-evidence-${framework.toLowerCase()}-${this.startDate}-${this.endDate}.json`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }
}
