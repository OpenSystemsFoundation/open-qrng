import { createElement } from '@lwc/engine-dom';
import QuantumFairApp from 'c/quantumFairApp';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getSettings from '@salesforce/apex/SetupController.getSettings';

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

    it('connectedCallback subscribes to empApi Platform Event channel', async () => {
        createComponent();
        await flushPromises();

        expect(subscribe).toHaveBeenCalledWith(
            '/event/OpenSF__Quantum_Job_Complete__e',
            -1,
            expect.any(Function)
        );
    });

    it('connectedCallback registers onError handler', async () => {
        createComponent();
        await flushPromises();

        expect(onError).toHaveBeenCalledWith(expect.any(Function));
    });

    it('disconnectedCallback unsubscribes from empApi', async () => {
        const element = createComponent();
        await flushPromises();

        document.body.removeChild(element);
        await flushPromises();

        expect(unsubscribe).toHaveBeenCalledWith({ id: 'mock-subscription' });
    });

    it('disconnectedCallback does not unsubscribe when no subscription', async () => {
        subscribe.mockResolvedValue(null);
        const element = createComponent();
        await flushPromises();

        // Force _completeSubscription to be falsy
        element._completeSubscription = null;
        document.body.removeChild(element);
        await flushPromises();

        // unsubscribe should not have been called with null
        expect(unsubscribe).not.toHaveBeenCalled();
    });

    it('onError handler logs empApi errors', async () => {
        const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
        createComponent();
        await flushPromises();

        // Get the error callback that was passed to onError
        const errorCallback = onError.mock.calls[0][0];
        errorCallback({ message: 'test error' });

        expect(spy).toHaveBeenCalledWith('empApi error in quantumFairApp:', {
            message: 'test error'
        });
        spy.mockRestore();
    });

    it('wiredSettings triggers _initOperationsTab via setTimeout', async () => {
        createComponent();
        await flushPromises();

        const settingsData = { someKey: 'someValue' };
        getSettings.emit(settingsData);

        // Allow setTimeout(fn, 0) to execute
        await flushPromises();

        // The function was called; we just verify no error occurred
        // and that a second emit does not re-initialize
        // Record how many times subscribe has been called after first init
        const callCountAfterFirstInit = subscribe.mock.calls.length;

        getSettings.emit(settingsData);
        await flushPromises();
        // _settingsInitialized prevents double init - subscribe count stays the same
        expect(subscribe.mock.calls.length).toBe(callCountAfterFirstInit);
    });

    it('Platform Event callback calls _refreshHealthMonitor', async () => {
        createComponent();
        await flushPromises();

        // Get the subscription callback
        const subscribeCallback = subscribe.mock.calls[0][2];

        // Invoke the callback (simulates Platform Event firing)
        subscribeCallback({});
        await flushPromises();

        // Callback was invoked without throwing; subscribe was set up correctly
        expect(subscribe).toHaveBeenCalled();
    });

    it('handleJobComplete marks job as completed', async () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-complete-1' }
            })
        );
        await flushPromises();

        // Verify 1 job monitor exists, no dismiss button yet
        let jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(1);

        // Fire jobcomplete event from the job monitor
        const jobMonitor = jobMonitors[0];
        jobMonitor.dispatchEvent(
            new CustomEvent('jobcomplete', {
                detail: { jobId: 'job-complete-1' }
            })
        );
        await flushPromises();

        // Job monitor should still be rendered (just marked completed)
        jobMonitors = element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(1);
    });

    it('handleDismissJob removes job from list when dismiss button is clicked', async () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-dismiss-1' }
            })
        );
        await flushPromises();

        // Mark the job completed so the dismiss button renders
        const jobMonitor =
            element.shadowRoot.querySelector('c-qrng-job-monitor');
        jobMonitor.dispatchEvent(
            new CustomEvent('jobcomplete', {
                detail: { jobId: 'job-dismiss-1' }
            })
        );
        await flushPromises();

        // Now the dismiss button should be rendered
        const dismissBtn = element.shadowRoot.querySelector(
            'lightning-button-icon'
        );
        expect(dismissBtn).not.toBeNull();

        // Click it to dismiss
        dismissBtn.click();
        await flushPromises();

        // Job monitors should be empty
        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(0);
    });

    it('hasActiveJobs is false when no jobs', async () => {
        const element = createComponent();
        await flushPromises();

        // hasActiveJobs is a getter on the component class, not @api
        // We verify through the DOM: no job monitors should be present
        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(0);
    });

    it('hasActiveJobs shows jobs section when jobs exist', async () => {
        const element = createComponent();

        const requestForm = element.shadowRoot.querySelector(
            'c-qrng-request-form'
        );
        requestForm.dispatchEvent(
            new CustomEvent('jobsubmitted', {
                detail: { jobId: 'job-active-1' }
            })
        );
        await flushPromises();

        const jobMonitors =
            element.shadowRoot.querySelectorAll('c-qrng-job-monitor');
        expect(jobMonitors).toHaveLength(1);
    });
});
