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
});
