import { LightningElement, api, wire, track } from 'lwc';
import getCertificateDTO from '@salesforce/apex/SetupController.getCertificateDTO';
import verifyCertificate from '@salesforce/apex/SetupController.verifyCertificate';
import { reduceErrors, setupHiDpiCanvas } from 'c/qrngUtils';

const HASH_CANVAS_SIZE = 128;

export default class QrngFairnessCertificate extends LightningElement {
    @track certificate;
    @track validationResults;
    @track verificationResult;
    @track isVerifying = false;
    @track loadError;

    // Effective certificate id — recordId (record page) wins over
    // certificateId (explicit binding from parent components).
    @track _certId;
    _recordId;
    _certificateId;

    /** Record-page support: flexipages inject the record id here. */
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this._updateCertId();
    }

    /** Explicit certificate id binding (parent components). */
    @api
    get certificateId() {
        return this._certificateId;
    }
    set certificateId(value) {
        this._certificateId = value;
        this._updateCertId();
    }

    _updateCertId() {
        this._certId = this._recordId || this._certificateId;
    }

    @wire(getCertificateDTO, { certificateId: '$_certId' })
    wiredCert({ data, error }) {
        if (data) {
            this.loadError = undefined;
            this.certificate = data;
            if (data.validationResults) {
                try {
                    this.validationResults = JSON.parse(data.validationResults);
                } catch {
                    this.validationResults = null;
                }
            }
            this.drawVisualHash();
        } else if (error) {
            this.certificate = undefined;
            this.validationResults = null;
            this.loadError = reduceErrors(error);
        }
    }

    renderedCallback() {
        if (this.certificate) {
            this.drawVisualHash();
        }
    }

    get hasCertId() {
        return !!this._certId;
    }

    get isLoading() {
        return this.hasCertId && !this.certificate && !this.loadError;
    }

    get chshSValueLabel() {
        return this.hasCHSH
            ? Number(this.certificate.chshSValue).toFixed(3)
            : null;
    }

    get hasCHSH() {
        return (
            this.certificate &&
            this.certificate.chshSValue != null &&
            this.certificate.chshSValue > 0
        );
    }

    get hasBackendVerification() {
        return this.certificate?.backendVerified != null;
    }

    get backendVerifiedLabel() {
        if (!this.hasBackendVerification) return 'Not Verified';
        return this.certificate.backendVerified ? 'Verified' : 'Not Verified';
    }

    get backendVerifiedClass() {
        if (!this.hasBackendVerification)
            return 'slds-badge slds-theme_default';
        return this.certificate.backendVerified
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-theme_default';
    }

    get isTampered() {
        return this.certificate?.tampered === true;
    }

    get statusBadgeClass() {
        if (!this.certificate) return '';
        if (this.certificate.tampered) return 'slds-badge slds-theme_warning';
        return this.certificate.status === 'Certified'
            ? 'slds-badge slds-theme_success'
            : 'slds-badge slds-theme_error';
    }

    get statusLabel() {
        if (!this.certificate) return '';
        return this.certificate.tampered ? 'Tampered' : this.certificate.status;
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

    // Extended test getters
    get hasExtendedResults() {
        return (
            this.validationResults?.extendedTestsCompleted === true ||
            this.validationResults?.allTestsCompleted === true
        );
    }

    get extendedTests() {
        if (!this.hasExtendedResults) return [];
        const tests = [
            {
                key: 'minEntropyTest',
                label: 'Min-Entropy'
            },
            {
                key: 'repetitionCountTest',
                label: 'Rep. Count'
            },
            {
                key: 'adaptiveProportionTest',
                label: 'Adapt. Proportion'
            },
            {
                key: 'approximateEntropyTest',
                label: 'Approx. Entropy'
            },
            { key: 'serialTest', label: 'Serial' },
            { key: 'cumulativeSumsTest', label: 'CUSUM' },
            {
                key: 'longestRunOfOnesTest',
                label: 'Longest Run'
            }
        ];
        return tests.map((t) => ({
            ...t,
            passed: this.validationResults?.[t.key] === true,
            iconName: this.validationResults?.[t.key]
                ? 'utility:success'
                : 'utility:error',
            badgeClass:
                'test-badge ' +
                (this.validationResults?.[t.key] ? 'test-pass' : 'test-fail')
        }));
    }

    get verificationClass() {
        if (!this.verificationResult) return '';
        if (this.verificationResult.error) {
            // Transient error — neutral styling, NOT a tamper alarm
            return 'slds-m-top_small slds-text-color_weak';
        }
        return (
            'slds-m-top_small ' +
            (this.verificationResult.integrityVerified
                ? 'slds-text-color_success'
                : 'slds-text-color_error')
        );
    }

    get verificationMessage() {
        if (!this.verificationResult) return '';
        if (this.verificationResult.error) {
            return 'Verification could not be completed. Try again.';
        }
        return this.verificationResult.integrityVerified
            ? 'Integrity verified - all hashes match'
            : 'Integrity check failed - data may have been modified';
    }

    async handleVerify() {
        this.isVerifying = true;
        try {
            this.verificationResult = await verifyCertificate({
                certificateId: this._certId
            });
        } catch (error) {
            // A failed callout is NOT evidence of tampering — surface it
            // as an inconclusive verification, never as a tamper alarm.
            this.verificationResult = { error: reduceErrors(error) };
        } finally {
            this.isVerifying = false;
        }
    }

    drawVisualHash() {
        const canvas = this.refs.hashCanvas;
        if (!canvas || !this.certificate?.rawBitstringHash) return;

        const size = HASH_CANVAS_SIZE;
        const ctx = setupHiDpiCanvas(canvas, size, size);
        if (!ctx) return;
        const hash = this.certificate.rawBitstringHash;
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
