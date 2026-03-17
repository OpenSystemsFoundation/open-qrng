import { LightningElement, api, wire, track } from 'lwc';
import getCertificate from '@salesforce/apex/QRNGSetupController.getCertificate';
import verifyCertificate from '@salesforce/apex/QRNGSetupController.verifyCertificate';

export default class QrngFairnessCertificate extends LightningElement {
    @api certificateId;
    @track certificate;
    @track validationResults;
    @track verificationResult;
    @track isVerifying = false;

    @wire(getCertificate, { certificateId: '$certificateId' })
    wiredCert({ data }) {
        if (data) {
            this.certificate = data;
            if (data.Validation_Results__c) {
                try {
                    this.validationResults = JSON.parse(
                        data.Validation_Results__c
                    );
                } catch {
                    this.validationResults = null;
                }
            }
            this.drawVisualHash();
        }
    }

    renderedCallback() {
        if (this.certificate) {
            this.drawVisualHash();
        }
    }

    get formattedDate() {
        if (!this.certificate || !this.certificate.CreatedDate) return '';
        return new Date(this.certificate.CreatedDate).toLocaleString();
    }

    get hasCHSH() {
        return (
            this.certificate &&
            this.certificate.CHSH_S_Value__c != null &&
            this.certificate.CHSH_S_Value__c > 0
        );
    }

    get statusBadgeClass() {
        if (!this.certificate) return '';
        return this.certificate.Status__c === 'Certified'
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-theme_error';
    }

    // Validation result getters
    get frequencyTestIcon() {
        return this.validationResults?.frequencyTest
            ? 'utility:success'
            : 'utility:error';
    }
    get frequencyTestClass() {
        return (
            'test-badge ' +
            (this.validationResults?.frequencyTest ? 'test-pass' : 'test-fail')
        );
    }
    get runsTestIcon() {
        return this.validationResults?.runsTest
            ? 'utility:success'
            : 'utility:error';
    }
    get runsTestClass() {
        return (
            'test-badge ' +
            (this.validationResults?.runsTest ? 'test-pass' : 'test-fail')
        );
    }
    get chiSquaredTestIcon() {
        return this.validationResults?.chiSquaredTest
            ? 'utility:success'
            : 'utility:error';
    }
    get chiSquaredTestClass() {
        return (
            'test-badge ' +
            (this.validationResults?.chiSquaredTest ? 'test-pass' : 'test-fail')
        );
    }

    get verificationClass() {
        if (!this.verificationResult) return '';
        return (
            'slds-m-top_small ' +
            (this.verificationResult.integrityVerified
                ? 'slds-text-color_success'
                : 'slds-text-color_error')
        );
    }

    get verificationMessage() {
        if (!this.verificationResult) return '';
        return this.verificationResult.integrityVerified
            ? 'Integrity verified - all hashes match'
            : 'Integrity check failed - data may have been modified';
    }

    async handleVerify() {
        this.isVerifying = true;
        try {
            this.verificationResult = await verifyCertificate({
                certificateId: this.certificateId
            });
        } catch {
            this.verificationResult = { integrityVerified: false };
        } finally {
            this.isVerifying = false;
        }
    }

    drawVisualHash() {
        const canvas = this.refs.hashCanvas;
        if (!canvas || !this.certificate?.Raw_Bitstring_Hash__c) return;

        const ctx = canvas.getContext('2d');
        const hash = this.certificate.Raw_Bitstring_Hash__c;
        const size = 128;
        const cellSize = size / 8;

        ctx.clearRect(0, 0, size, size);

        // Generate pixel art from hash hex characters
        for (let i = 0; i < Math.min(hash.length, 64); i++) {
            const val = parseInt(hash[i], 16);
            const row = Math.floor(i / 8);
            const col = i % 8;

            // Map hex value to color
            const hue = (val * 22.5) % 360;
            const lightness = 40 + val * 3;
            ctx.fillStyle = `hsl(${hue}, 70%, ${lightness}%)`;
            ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
        }

        // Border
        ctx.strokeStyle = '#c9c7c5';
        ctx.lineWidth = 1;
        ctx.strokeRect(0, 0, size, size);
    }
}
