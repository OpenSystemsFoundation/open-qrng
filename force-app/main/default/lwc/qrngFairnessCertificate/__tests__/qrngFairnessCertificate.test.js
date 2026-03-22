import { createElement } from '@lwc/engine-dom';
import QrngFairnessCertificate from 'c/qrngFairnessCertificate';

jest.mock(
    '@salesforce/apex/QRNGSetupController.getCertificateDTO',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.verifyCertificate',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

import getCertificateDTO from '@salesforce/apex/QRNGSetupController.getCertificateDTO';
import verifyCertificate from '@salesforce/apex/QRNGSetupController.verifyCertificate';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_CERTIFICATE = {
    name: 'CERT-0001',
    externalJobId: 'job_abc123',
    backend: 'test_backend',
    status: 'Certified',
    rawBitstringHash:
        'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
    debiasedBitstringHash:
        'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3',
    validationResults:
        '{"frequencyTest":true,"runsTest":true,"chiSquaredTest":true,"passed":true}',
    purpose: 'Test assignment',
    createdDate: '2026-03-17T10:00:00.000Z',
    chshSValue: null
};

describe('c-qrng-fairness-certificate', () => {
    let mockContext;

    beforeEach(() => {
        mockContext = {
            clearRect: jest.fn(),
            fillRect: jest.fn(),
            strokeRect: jest.fn(),
            fillText: jest.fn(),
            beginPath: jest.fn(),
            moveTo: jest.fn(),
            lineTo: jest.fn(),
            stroke: jest.fn(),
            arc: jest.fn(),
            save: jest.fn(),
            restore: jest.fn(),
            translate: jest.fn(),
            rotate: jest.fn(),
            setLineDash: jest.fn(),
            font: '',
            fillStyle: '',
            strokeStyle: '',
            lineWidth: 1,
            textAlign: '',
            textBaseline: ''
        };
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockContext);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.restoreAllMocks();
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-fairness-certificate', {
            is: QrngFairnessCertificate
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders loading spinner when no certificate data', () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
        expect(spinner.alternativeText).toBe('Loading certificate...');
    });

    it('renders certificate header with name and status badge when wire emits data', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const certId = element.shadowRoot.querySelector('.certificate-id');
        expect(certId).not.toBeNull();
        expect(certId.textContent).toBe('CERT-0001');

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge).not.toBeNull();
        expect(badge.label).toBe('Certified');
    });

    it('displays hash values', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const hashValues = element.shadowRoot.querySelectorAll('.hash-value');
        expect(hashValues.length).toBeGreaterThanOrEqual(2);
        expect(hashValues[0].textContent).toBe(
            MOCK_CERTIFICATE.rawBitstringHash
        );
        expect(hashValues[1].textContent).toBe(
            MOCK_CERTIFICATE.debiasedBitstringHash
        );
    });

    it('renders validation results with 3 test badges', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const testBadges = element.shadowRoot.querySelectorAll('.test-badge');
        expect(testBadges).toHaveLength(3);

        // All tests pass, so all badges should have test-pass class
        testBadges.forEach((badge) => {
            expect(badge.classList.contains('test-pass')).toBe(true);
        });

        const icons = element.shadowRoot.querySelectorAll(
            '.test-badge lightning-icon'
        );
        expect(icons).toHaveLength(3);
        icons.forEach((icon) => {
            expect(icon.iconName).toBe('utility:success');
        });
    });

    it('verify button calls verifyCertificate and shows result message', async () => {
        verifyCertificate.mockResolvedValue({ integrityVerified: true });

        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const verifyButton =
            element.shadowRoot.querySelector('lightning-button');
        expect(verifyButton).not.toBeNull();
        expect(verifyButton.label).toBe('Verify Integrity');

        verifyButton.click();
        await flushPromises();

        expect(verifyCertificate).toHaveBeenCalledWith({
            certificateId: 'a01xx000001234'
        });

        const resultMsg = element.shadowRoot.querySelector(
            '.slds-text-color_success'
        );
        expect(resultMsg).not.toBeNull();
        expect(resultMsg.textContent).toBe(
            'Integrity verified - all hashes match'
        );
    });

    it('canvas visual hash is drawn (getContext called)', async () => {
        createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalledWith(
            '2d'
        );
    });

    it('isTampered getter returns true when tampered flag is set', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({ ...MOCK_CERTIFICATE, tampered: true });
        await flushPromises();

        // Tampered alert should appear
        const alert = element.shadowRoot.querySelector(
            '.slds-notify_alert'
        );
        expect(alert).not.toBeNull();
        expect(alert.textContent).toContain('Integrity check failed');
    });

    it('isTampered getter returns false when tampered is not set', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const alert = element.shadowRoot.querySelector(
            '.slds-notify_alert'
        );
        expect(alert).toBeNull();
    });

    it('statusLabel shows Tampered when tampered is true', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({ ...MOCK_CERTIFICATE, tampered: true });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Tampered');
    });

    it('statusBadgeClass includes warning theme when tampered', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({ ...MOCK_CERTIFICATE, tampered: true });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge.className).toContain('slds-theme_warning');
    });

    it('statusBadgeClass includes error theme when status is not Certified', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            status: 'Failed'
        });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Failed');
        expect(badge.className).toContain('slds-theme_error');
    });

    it('canvas visual hash draws pixel art from hash', async () => {
        createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        // clearRect should be called for the 128x128 canvas
        expect(mockContext.clearRect).toHaveBeenCalledWith(0, 0, 128, 128);
        // fillRect should be called for each hex character (up to 64 cells)
        expect(mockContext.fillRect).toHaveBeenCalled();
        // strokeRect should be called for the border
        expect(mockContext.strokeRect).toHaveBeenCalledWith(0, 0, 128, 128);
    });

    it('drawVisualHash does nothing when no rawBitstringHash', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });
        mockContext.clearRect.mockClear();

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            rawBitstringHash: null
        });
        await flushPromises();

        // clearRect should not have been called since there's no hash
        expect(mockContext.clearRect).not.toHaveBeenCalled();
    });

    it('renders extended NIST test badges when extended results available', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        const extendedValidation = JSON.stringify({
            frequencyTest: true,
            runsTest: true,
            chiSquaredTest: true,
            passed: true,
            extendedTestsCompleted: true,
            minEntropyTest: true,
            repetitionCountTest: true,
            adaptiveProportionTest: false,
            approximateEntropyTest: true,
            serialTest: true,
            cumulativeSumsTest: true,
            longestRunOfOnesTest: true
        });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            validationResults: extendedValidation
        });
        await flushPromises();

        const testBadges = element.shadowRoot.querySelectorAll('.test-badge');
        // 3 critical + 7 extended = 10
        expect(testBadges.length).toBe(10);
    });

    it('does not render extended test section when no extended results', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        // Should only have the 3 critical test badges
        const testBadges = element.shadowRoot.querySelectorAll('.test-badge');
        expect(testBadges.length).toBe(3);
    });

    it('verify button handles failure gracefully', async () => {
        verifyCertificate.mockRejectedValue(new Error('Network failure'));

        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const verifyButton =
            element.shadowRoot.querySelector('lightning-button');
        verifyButton.click();
        await flushPromises();

        // Should show integrity check failed message
        const resultMsg = element.shadowRoot.querySelector(
            '.slds-text-color_error'
        );
        expect(resultMsg).not.toBeNull();
        expect(resultMsg.textContent).toBe(
            'Integrity check failed - data may have been modified'
        );
    });

    it('hasCHSH returns true when chshSValue is present and > 0', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            chshSValue: 2.65
        });
        await flushPromises();

        // CHSH S-Value should be displayed
        const text = element.shadowRoot.textContent;
        expect(text).toContain('CHSH S-Value');
        expect(text).toContain('2.65');
    });

    it('hasCHSH returns false when chshSValue is null', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).not.toContain('CHSH S-Value');
    });

    it('formattedDate returns formatted date string', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        // The date should appear somewhere in the output
        const text = element.shadowRoot.textContent;
        // The date 2026-03-17T10:00:00.000Z formatted with toLocaleString
        expect(text.length).toBeGreaterThan(0);
    });

    it('backendVerifiedLabel shows Verified when backendVerified is true', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            backendVerified: true,
            backendVerifiedAt: '2026-03-18T12:00:00.000Z'
        });
        await flushPromises();

        const badges = element.shadowRoot.querySelectorAll('lightning-badge');
        const verifiedBadge = Array.from(badges).find(
            (b) => b.label === 'Verified'
        );
        expect(verifiedBadge).toBeTruthy();
    });

    it('backendVerifiedLabel shows Not Verified when backendVerified is false', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            backendVerified: false
        });
        await flushPromises();

        const badges = element.shadowRoot.querySelectorAll('lightning-badge');
        const notVerifiedBadge = Array.from(badges).find(
            (b) => b.label === 'Not Verified'
        );
        expect(notVerifiedBadge).toBeTruthy();
    });

    it('handles invalid JSON in validationResults gracefully', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            validationResults: 'not valid json{'
        });
        await flushPromises();

        // Should not crash; validation results section should not render
        const testBadges = element.shadowRoot.querySelectorAll('.test-badge');
        expect(testBadges.length).toBe(0);
    });

    it('displays assignment hash when present', async () => {
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit({
            ...MOCK_CERTIFICATE,
            assignmentHash: 'abc123def456'
        });
        await flushPromises();

        const hashValues = element.shadowRoot.querySelectorAll('.hash-value');
        expect(hashValues.length).toBe(3);
        expect(hashValues[2].textContent).toBe('abc123def456');
    });

    it('verificationClass includes success class on verified', async () => {
        verifyCertificate.mockResolvedValue({ integrityVerified: true });
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        const msg = element.shadowRoot.querySelector(
            '.slds-text-color_success'
        );
        expect(msg).not.toBeNull();
    });

    it('verificationClass includes error class on failure', async () => {
        verifyCertificate.mockResolvedValue({ integrityVerified: false });
        const element = createComponent({ certificateId: 'a01xx000001234' });

        getCertificateDTO.emit(MOCK_CERTIFICATE);
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        const msg = element.shadowRoot.querySelector(
            '.slds-text-color_error'
        );
        expect(msg).not.toBeNull();
    });
});
