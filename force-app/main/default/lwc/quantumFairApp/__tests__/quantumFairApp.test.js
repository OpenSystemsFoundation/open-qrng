import { createElement } from '@lwc/engine-dom';
import QuantumFairApp from 'c/quantumFairApp';

// Mock Apex wire adapters used by child components
jest.mock(
    '@salesforce/apex/QRNGSetupController.getSettings',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.getUsageStats',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.getJobStatusDTO',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// Mock imperative Apex methods used by children
jest.mock(
    '@salesforce/apex/QRNGSetupController.submitQRNGJob',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.testConnection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.getAvailableBackends',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.getCertificateByJobId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.getAuditTrailDTO',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.getCertificateDetails',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
    { virtual: true }
);

// Mock ResizeObserver (used by c-qrng-circuit-visualizer)
class MockResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
}

// Mock Canvas getContext (used by c-qrng-circuit-visualizer)
const mockCanvasContext = {
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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-quantum-fair-app', () => {
    beforeAll(() => {
        global.ResizeObserver = MockResizeObserver;
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    afterAll(() => {
        delete global.ResizeObserver;
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    function createComponent() {
        const element = createElement('c-quantum-fair-app', {
            is: QuantumFairApp
        });
        document.body.appendChild(element);
        return element;
    }

    it('renders lightning-tabset with 3 tabs', () => {
        const element = createComponent();

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset).not.toBeNull();

        const tabs = element.shadowRoot.querySelectorAll('lightning-tab');
        expect(tabs).toHaveLength(3);

        expect(tabs[0].label).toBe('Dashboard');
        expect(tabs[1].label).toBe('Setup');
        expect(tabs[2].label).toBe('Audit Trail');
    });

    it('renders qrng-request-form in Dashboard tab', () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        expect(requestForm).not.toBeNull();
    });

    it('does not show qrng-job-monitor when no activeJobId', () => {
        const element = createComponent();

        const jobMonitor =
            element.shadowRoot.querySelector('c-qrng-job-monitor');
        expect(jobMonitor).toBeNull();
    });

    it('shows qrng-job-monitor after jobsubmitted event', async () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: '001xx000003DGb1' }
            })
        );

        await flushPromises();

        const jobMonitor =
            element.shadowRoot.querySelector('c-qrng-job-monitor');
        expect(jobMonitor).not.toBeNull();
        expect(jobMonitor.jobId).toBe('001xx000003DGb1');
    });
});
