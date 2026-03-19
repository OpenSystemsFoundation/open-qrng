import { LightningElement, track } from 'lwc';
import exportComplianceEvidence from '@salesforce/apex/QRNGSetupController.exportComplianceEvidence';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

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
        // Default to last 30 days
        const now = new Date();
        const thirtyDaysAgo = new Date(
            now.getTime() - 30 * 24 * 60 * 60 * 1000
        );
        this.endDate = now.toISOString().split('T')[0];
        this.startDate = thirtyDaysAgo.toISOString().split('T')[0];
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
                    message: this.reduceErrors(error),
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

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}
