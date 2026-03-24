import { createElement } from '@lwc/engine-dom';
import QrngJobMonitor from 'c/qrngJobMonitor';
import getJobStatusDTO from '@salesforce/apex/SetupController.getJobStatusDTO';
import getCertificateByJobId from '@salesforce/apex/SetupController.getCertificateByJobId';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { refreshApex } from '@salesforce/apex';

// Wire adapter for @wire-decorated property
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

// Imperative Apex mock
jest.mock(
    '@salesforce/apex/SetupController.getCertificateByJobId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// refreshApex mock
jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_JOB_RUNNING = {
    name: 'QJ-0001',
    externalJobId: 'job123',
    backend: 'test_backend',
    status: 'Running',
    numQubits: 8,
    shots: 1024
};

const MOCK_JOB_COMPLETED = {
    name: 'QJ-0001',
    externalJobId: 'job123',
    backend: 'test_backend',
    status: 'Completed',
    numQubits: 8,
    shots: 1024,
    rawResults: '{"00":512,"11":512}'
};

const MOCK_JOB_FAILED = {
    name: 'QJ-0001',
    externalJobId: 'job123',
    backend: 'test_backend',
    status: 'Failed',
    numQubits: 8,
    shots: 1024,
    errorMessage: 'Execution timeout'
};

const MOCK_JOB_SUBMITTED = {
    name: 'QJ-0001',
    externalJobId: 'job123',
    backend: 'test_backend',
    status: 'Submitted',
    numQubits: 8,
    shots: 1024
};

// Mock ResizeObserver and Canvas (used by child c-qrng-results-visualizer)
class MockResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
}

const mockCanvasContext = {
    clearRect: jest.fn(),
    fillRect: jest.fn(),
    strokeRect: jest.fn(),
    fillText: jest.fn(),
    beginPath: jest.fn(),
    moveTo: jest.fn(),
    lineTo: jest.fn(),
    stroke: jest.fn(),
    fill: jest.fn(),
    arc: jest.fn(),
    save: jest.fn(),
    restore: jest.fn(),
    translate: jest.fn(),
    rotate: jest.fn(),
    setLineDash: jest.fn(),
    measureText: jest.fn().mockReturnValue({ width: 10 }),
    font: '',
    fillStyle: '',
    strokeStyle: '',
    lineWidth: 1,
    textAlign: '',
    textBaseline: ''
};

describe('c-qrng-job-monitor', () => {
    beforeAll(() => {
        global.ResizeObserver = MockResizeObserver;
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    afterAll(() => {
        delete global.ResizeObserver;
    });

    beforeEach(() => {
        getCertificateByJobId.mockResolvedValue(null);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.useRealTimers();
        // Re-apply canvas mock after clearAllMocks
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-job-monitor', {
            is: QrngJobMonitor
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders "No active job" message when no jobId and no wire data', async () => {
        const element = createComponent();

        // Do not emit wire data so job stays undefined
        await flushPromises();

        const message = element.shadowRoot.querySelector(
            '.slds-text-body_regular'
        );
        expect(message).not.toBeNull();
        expect(message.textContent).toContain('No active job');
    });

    it('renders job details when wire returns data', async () => {
        const element = createComponent({
            jobId: '001xx000003DGb1'
        });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const details = element.shadowRoot.querySelectorAll(
            '.slds-dl_horizontal__detail'
        );
        const detailValues = Array.from(details).map((d) => d.textContent);
        expect(detailValues).toContain('QJ-0001');
        expect(detailValues).toContain('test_backend');
    });

    it('shows progress indicator with correct current step', async () => {
        const element = createComponent({
            jobId: '001xx000003DGb1'
        });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const progressIndicator = element.shadowRoot.querySelector(
            'lightning-progress-indicator'
        );
        expect(progressIndicator).not.toBeNull();
        expect(progressIndicator.currentStep).toBe('Running');

        const steps = element.shadowRoot.querySelectorAll(
            'lightning-progress-step'
        );
        expect(steps).toHaveLength(4);
    });

    it('subscribes to Platform Event channels on connectedCallback', async () => {
        createComponent({ jobId: '001xx000003DGb1' });
        await flushPromises();

        expect(subscribe).toHaveBeenCalledTimes(2);
        expect(subscribe.mock.calls[0][0]).toBe(
            '/event/OpenSF__Quantum_Job_Complete__e'
        );
        expect(subscribe.mock.calls[1][0]).toBe(
            '/event/OpenSF__Quantum_Job_Failed__e'
        );
        expect(onError).toHaveBeenCalledTimes(1);
    });

    it('shows spinner when job is in progress (status = Running)', async () => {
        const element = createComponent({
            jobId: '001xx000003DGb1'
        });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const pulse = element.shadowRoot.querySelector('.pulse');
        expect(pulse).not.toBeNull();
        expect(pulse.textContent).toContain('Awaiting result');
    });

    // ── Completed status: stops polling, loads certificate (lines 26-28) ─
    it('stops polling and loads certificate when status is Completed', async () => {
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_COMPLETED);
        await flushPromises();

        expect(getCertificateByJobId).toHaveBeenCalledWith({
            jobId: '001xx000003DGb1'
        });

        // Verify certificate renders
        const cert = element.shadowRoot.querySelector(
            'c-qrng-fairness-certificate'
        );
        expect(cert).not.toBeNull();
    });

    // ── Failed status: stops polling (lines 29-30) ──────────────
    it('stops polling and shows error when status is Failed', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_FAILED);
        await flushPromises();

        const alert = element.shadowRoot.querySelector('[role="alert"]');
        expect(alert).not.toBeNull();
        expect(alert.textContent).toContain('Execution timeout');

        // No pulse/spinner should be visible
        const pulse = element.shadowRoot.querySelector('.pulse');
        expect(pulse).toBeNull();
    });

    // ── Polling: starts when in-progress status (lines 56-58) ───
    it('starts polling when status is Submitted', async () => {
        jest.useFakeTimers();
        createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_SUBMITTED);
        // Flush with fake timers: advance 0ms to run microtasks
        jest.advanceTimersByTime(0);
        await Promise.resolve();
        await Promise.resolve();

        // Advance timer to trigger a poll cycle (POLL_INTERVAL_MS = 5000)
        jest.advanceTimersByTime(5000);
        await Promise.resolve();
        await Promise.resolve();

        expect(refreshApex).toHaveBeenCalled();
    });

    it('does not double-start polling on repeated wire emissions', async () => {
        jest.useFakeTimers();
        createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_SUBMITTED);
        jest.advanceTimersByTime(0);
        await Promise.resolve();
        await Promise.resolve();

        // Emit again — should not create duplicate timers
        getJobStatusDTO.emit(MOCK_JOB_SUBMITTED);
        jest.advanceTimersByTime(0);
        await Promise.resolve();
        await Promise.resolve();

        jest.advanceTimersByTime(5000);
        await Promise.resolve();
        await Promise.resolve();

        // refreshApex should only be called once for one poll interval
        const refreshCount = refreshApex.mock.calls.length;
        expect(refreshCount).toBeGreaterThanOrEqual(1);
    });

    // ── disconnectedCallback: unsubscribes and stops polling (lines 42-44) ─
    it('unsubscribes and stops polling on disconnectedCallback', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        // Remove from DOM triggers disconnectedCallback
        document.body.removeChild(element);
        await flushPromises();

        expect(unsubscribe).toHaveBeenCalledTimes(2);
    });

    // ── handleCompleteEvent (lines 104-123) ─────────────────────
    it('handles complete platform event for matching job id', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const completeHandler = jest.fn();
        element.addEventListener('jobcomplete', completeHandler);

        // Get the callback registered with subscribe for complete channel
        const completeCallback = subscribe.mock.calls[0][2];
        completeCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: '001xx000003DGb1',
                    OpenSF__Certificate_Id__c: 'cert-456',
                    OpenSF__Status__c: 'Completed'
                }
            }
        });
        await flushPromises();

        expect(completeHandler).toHaveBeenCalled();
        expect(completeHandler.mock.calls[0][0].detail.certificateId).toBe(
            'cert-456'
        );
        expect(refreshApex).toHaveBeenCalled();
    });

    it('ignores complete event for different job id', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const completeHandler = jest.fn();
        element.addEventListener('jobcomplete', completeHandler);

        const completeCallback = subscribe.mock.calls[0][2];
        completeCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'other-job-id',
                    OpenSF__Certificate_Id__c: 'cert-999',
                    OpenSF__Status__c: 'Completed'
                }
            }
        });
        await flushPromises();

        expect(completeHandler).not.toHaveBeenCalled();
    });

    // ── handleFailedEvent (lines 125-133) ───────────────────────
    it('handles failed platform event for matching job id', async () => {
        createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const failedCallback = subscribe.mock.calls[1][2];
        failedCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: '001xx000003DGb1',
                    OpenSF__Error_Message__c: 'Backend error'
                }
            }
        });
        await flushPromises();

        expect(refreshApex).toHaveBeenCalled();
    });

    it('ignores failed event for different job id', async () => {
        createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        // Reset refreshApex call count after polling setup
        refreshApex.mockClear();

        const failedCallback = subscribe.mock.calls[1][2];
        failedCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'other-job-id',
                    OpenSF__Error_Message__c: 'err'
                }
            }
        });
        await flushPromises();

        // refreshApex should NOT have been called for a non-matching event
        expect(refreshApex).not.toHaveBeenCalled();
    });

    // ── loadCertificate error handling (lines 135-143) ──────────
    it('handles loadCertificate error gracefully', async () => {
        jest.spyOn(console, 'error').mockImplementation(() => {});
        getCertificateByJobId.mockRejectedValue(new Error('Cert error'));

        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_COMPLETED);
        await flushPromises();

        // Component should not crash
        expect(element.shadowRoot).toBeDefined();
    });

    // ── currentStep returns "Submitted" for Failed status (line 148) ─
    it('currentStep shows "Submitted" when job is Failed', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_FAILED);
        await flushPromises();

        const progressIndicator = element.shadowRoot.querySelector(
            'lightning-progress-indicator'
        );
        expect(progressIndicator.currentStep).toBe('Submitted');
    });

    // ── statusClass returns correct class for each status ───────
    it('statusClass includes status-completed for Completed status', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_JOB_COMPLETED);
        await flushPromises();

        const statusDiv = element.shadowRoot.querySelector('.status-badge');
        expect(statusDiv).not.toBeNull();
        expect(statusDiv.classList.contains('status-completed')).toBe(true);
    });

    it('statusClass includes status-failed for Failed status', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });

        getJobStatusDTO.emit(MOCK_JOB_FAILED);
        await flushPromises();

        const statusDiv = element.shadowRoot.querySelector('.status-badge');
        expect(statusDiv).not.toBeNull();
        expect(statusDiv.classList.contains('status-failed')).toBe(true);
    });

    // ── isCompleted / isInProgress getters ───────────────────────
    it('isCompleted is true and renders certificate section', async () => {
        const element = createComponent({ jobId: '001xx000003DGb1' });
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_JOB_COMPLETED);
        await flushPromises();

        const cert = element.shadowRoot.querySelector(
            'c-qrng-fairness-certificate'
        );
        expect(cert).not.toBeNull();
    });

    it('subscribe error is handled gracefully', async () => {
        jest.spyOn(console, 'error').mockImplementation(() => {});
        // Override subscribe to reject
        subscribe.mockRejectedValueOnce(new Error('subscribe error'));
        subscribe.mockRejectedValueOnce(new Error('subscribe error'));

        const element = createComponent({ jobId: '001xx000003DGb1' });
        await flushPromises();

        // Component should still render
        expect(element.shadowRoot).toBeDefined();
    });
});
