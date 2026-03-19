import { createElement } from '@lwc/engine-dom';
import QuantumFairApp from 'c/quantumFairApp';

// Mock Apex wire adapters used by child components
jest.mock(
    '@salesforce/apex/SetupController.getSettings',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/SetupController.getUsageStats',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/SetupController.getJobStatusDTO',
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
    '@salesforce/apex/SetupController.submitQuantumJob',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.testConnection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getAvailableBackends',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getCertificateByJobId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getAuditTrailDTO',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getCertificateDetails',
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
jest.mock(
    '@salesforce/apex/SetupController.discoverInstances',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getAllBackendHealth',
    () => ({ default: jest.fn().mockResolvedValue([]) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getRecentJobs',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.refreshAllBackendHealth',
    () => ({ default: jest.fn().mockResolvedValue([]) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.verifyBackendQuantum',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.startSweeper',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.stopSweeper',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.startIntegrityCheck',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.stopIntegrityCheck',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.exportComplianceEvidence',
    () => ({ default: jest.fn() }),
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

    it('renders lightning-tabset with 5 tabs', () => {
        const element = createComponent();

        const tabset = element.shadowRoot.querySelector('lightning-tabset');
        expect(tabset).not.toBeNull();

        const tabs = element.shadowRoot.querySelectorAll('lightning-tab');
        expect(tabs).toHaveLength(5);

        expect(tabs[0].label).toBe('Dashboard');
        expect(tabs[1].label).toBe('Jobs');
        expect(tabs[2].label).toBe('Setup');
        expect(tabs[3].label).toBe('Operations');
        expect(tabs[4].label).toBe('Compliance');
    });

    it('renders qrng-request-form in Dashboard tab', () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        expect(requestForm).not.toBeNull();
    });

    it('does not show qrng-job-monitor when no jobs submitted', () => {
        const element = createComponent();

        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(0);
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

        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(1);
        expect(jobMonitors[0].jobId).toBe('001xx000003DGb1');
    });

    it('tracks multiple jobs simultaneously', async () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-001' }
            })
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-002' }
            })
        );

        await flushPromises();

        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(2);
        expect(jobMonitors[0].jobId).toBe('job-001');
        expect(jobMonitors[1].jobId).toBe('job-002');
    });

    it('does not add duplicate job monitors', async () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-001' }
            })
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-001' }
            })
        );

        await flushPromises();

        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(1);
    });
});
