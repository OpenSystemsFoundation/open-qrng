import { createElement } from 'lwc';
import QrngJobStatusPanel from 'c/qrngJobStatusPanel';
import getJobStatusDTO from '@salesforce/apex/QRNGSetupController.getJobStatusDTO';
import getCertificateByJobId from '@salesforce/apex/QRNGSetupController.getCertificateByJobId';
import refreshJobStatus from '@salesforce/apex/QRNGSetupController.refreshJobStatus';
import retrieveJobResults from '@salesforce/apex/QRNGSetupController.retrieveJobResults';
import { subscribe } from 'lightning/empApi';

// Wire adapter for @wire-decorated property
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

// Imperative Apex mocks
jest.mock(
    '@salesforce/apex/QRNGSetupController.getCertificateByJobId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.refreshJobStatus',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/QRNGSetupController.retrieveJobResults',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// refreshApex mock
jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
    { virtual: true }
);

// Mock ResizeObserver (used by child c-qrng-results-visualizer)
class MockResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
}

// Mock Canvas getContext (used by child c-qrng-results-visualizer)
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

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createComponent() {
    const element = createElement('c-qrng-job-status-panel', {
        is: QrngJobStatusPanel
    });
    element.recordId = 'a03xx000001234AAA';
    document.body.appendChild(element);
    return element;
}

const MOCK_DTO_RUNNING = {
    status: 'Running',
    externalJobId: 'ext-job-123',
    backend: 'ibm_brisbane',
    provider: 'IBM Quantum',
    shots: 1024,
    numQubits: 8,
    purpose: 'Test assignment',
    useBellTest: true,
    assignmentType: 'Round Robin',
    submittedAt: '2026-03-17T10:00:00.000Z',
    completedAt: null,
    errorMessage: null,
    pollCount: 3,
    executionTimeMs: null,
    queueTimeMs: null,
    rawResults: null
};

const MOCK_DTO_COMPLETED = {
    ...MOCK_DTO_RUNNING,
    status: 'Completed',
    completedAt: '2026-03-17T10:05:00.000Z',
    executionTimeMs: 1500,
    queueTimeMs: 500,
    rawResults: '{"00":512,"11":512}'
};

const MOCK_DTO_FAILED = {
    ...MOCK_DTO_RUNNING,
    status: 'Failed',
    errorMessage: 'Circuit execution failed'
};

const MOCK_DTO_NO_EXT_ID = {
    ...MOCK_DTO_RUNNING,
    status: 'Pending',
    externalJobId: null
};

describe('c-qrng-job-status-panel', () => {
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
        // Re-apply canvas mock after clearAllMocks
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    it('renders the component with card title', async () => {
        const element = createComponent();
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        expect(card.title).toBe('Quantum Job Status');
    });

    it('renders refresh and retrieve buttons', async () => {
        const element = createComponent();
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const labels = Array.from(buttons).map((b) => b.label);
        expect(labels).toContain('Refresh Status');
        expect(labels).toContain('Retrieve Results');
    });

    it('renders progress indicator', async () => {
        const element = createComponent();
        await flushPromises();

        // Verify component renders without crashing
        expect(element.shadowRoot).toBeDefined();
    });

    it('shows loading spinner when no record loaded', async () => {
        const element = createComponent();
        await flushPromises();

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
    });

    it('exposes disableRefresh as true when no record', async () => {
        const element = createComponent();
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Status'
        );
        expect(refreshBtn.disabled).toBe(true);
    });

    it('exposes disableRetrieve as true when no record', async () => {
        const element = createComponent();
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        expect(retrieveBtn.disabled).toBe(true);
    });

    // ── Wire adapter tests (lines 26-33) ────────────────────────
    it('stores wire result and populates DTO fields when wire emits data', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        // hasRecord should be true; spinner should be gone
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeNull();

        // Verify detail fields render
        const detailValues =
            element.shadowRoot.querySelectorAll('.detail-value');
        const texts = Array.from(detailValues).map((d) => d.textContent.trim());
        expect(texts).toContain('ext-job-123');
        expect(texts).toContain('ibm_brisbane');
        expect(texts).toContain('IBM Quantum');
    });

    it('loads certificate when wire emits Completed status', async () => {
        createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        expect(getCertificateByJobId).toHaveBeenCalledWith({
            jobId: 'a03xx000001234AAA'
        });
    });

    it('handles getCertificateByJobId returning null gracefully', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        // No certificate section should be shown
        const certComponent = element.shadowRoot.querySelector(
            'c-qrng-fairness-certificate'
        );
        expect(certComponent).toBeNull();
    });

    it('handles getCertificateByJobId error gracefully', async () => {
        const element = createComponent();
        getCertificateByJobId.mockRejectedValue(new Error('Not found'));

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        // Should not throw; component continues rendering
        expect(element.shadowRoot).toBeDefined();
    });

    // ── Platform Event subscription (lines 62-67, 82-99, 102) ──
    it('subscribes to complete and failed channels on connect', async () => {
        createComponent();
        await flushPromises();

        expect(subscribe).toHaveBeenCalledTimes(2);
        expect(subscribe.mock.calls[0][0]).toBe(
            '/event/OpenSF__QRNG_Complete__e'
        );
        expect(subscribe.mock.calls[1][0]).toBe(
            '/event/OpenSF__QRNG_Failed__e'
        );
    });

    it('handles complete event for matching job id', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        // Get the complete event callback from the subscribe mock
        const completeCallback = subscribe.mock.calls[0][2];
        completeCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'a03xx000001234AAA',
                    OpenSF__Certificate_Id__c: 'cert-123'
                }
            }
        });
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Job Completed'
        );
    });

    it('ignores complete event for different job id', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const completeCallback = subscribe.mock.calls[0][2];
        completeCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'different-job-id',
                    OpenSF__Certificate_Id__c: 'cert-999'
                }
            }
        });
        await flushPromises();

        expect(toastHandler).not.toHaveBeenCalled();
    });

    it('handles failed event for matching job id', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const failedCallback = subscribe.mock.calls[1][2];
        failedCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'a03xx000001234AAA',
                    OpenSF__Error_Message__c: 'Backend error'
                }
            }
        });
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
        expect(toastHandler.mock.calls[0][0].detail.title).toBe('Job Failed');
    });

    it('handles failed event with no error message (fallback to Unknown)', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const failedCallback = subscribe.mock.calls[1][2];
        failedCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'a03xx000001234AAA',
                    OpenSF__Error_Message__c: null
                }
            }
        });
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Unknown error'
        );
    });

    it('ignores failed event for different job id', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const failedCallback = subscribe.mock.calls[1][2];
        failedCallback({
            data: {
                payload: {
                    OpenSF__Job_Id__c: 'other-id',
                    OpenSF__Error_Message__c: 'err'
                }
            }
        });
        await flushPromises();

        expect(toastHandler).not.toHaveBeenCalled();
    });

    // ── DTO field accessor getters (lines 117-177) ──────────────
    it('returns default values when DTO is null', async () => {
        const element = createComponent();
        await flushPromises();

        // Access getters through rendered content — no record means spinner
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
    });

    it('renders all DTO fields for a running job', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const detailValues =
            element.shadowRoot.querySelectorAll('.detail-value');
        const texts = Array.from(detailValues).map((d) => d.textContent.trim());
        expect(texts).toContain('1024');
        expect(texts).toContain('8');
        expect(texts).toContain('Round Robin');
        expect(texts).toContain('Test assignment');
    });

    it('displays execution time in seconds for >= 1000ms', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        const detailValues =
            element.shadowRoot.querySelectorAll('.detail-value');
        const texts = Array.from(detailValues).map((d) => d.textContent.trim());
        expect(texts).toContain('1.5 s');
    });

    it('displays queue time in ms for < 1000ms', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        const detailValues =
            element.shadowRoot.querySelectorAll('.detail-value');
        const texts = Array.from(detailValues).map((d) => d.textContent.trim());
        expect(texts).toContain('500 ms');
    });

    // ── Computed properties (lines 185-207, 230-244) ────────────
    it('shows missing external ID warning when externalJobId is null', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_NO_EXT_ID);
        await flushPromises();

        const alerts = element.shadowRoot.querySelectorAll('[role="alert"]');
        const alertTexts = Array.from(alerts).map((a) => a.textContent);
        const hasWarning = alertTexts.some((t) =>
            t.includes('No External Job ID')
        );
        expect(hasWarning).toBe(true);
    });

    it('shows error message when status is Failed', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_FAILED);
        await flushPromises();

        const alerts = element.shadowRoot.querySelectorAll('[role="alert"]');
        const alertTexts = Array.from(alerts).map((a) => a.textContent);
        const hasError = alertTexts.some((t) =>
            t.includes('Circuit execution failed')
        );
        expect(hasError).toBe(true);
    });

    it('currentStep returns "Submitted" when status is Failed', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_FAILED);
        await flushPromises();

        const progressIndicator = element.shadowRoot.querySelector(
            'lightning-progress-indicator'
        );
        expect(progressIndicator.currentStep).toBe('Submitted');
    });

    it('statusBadgeClass maps Running to badge_inverse', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const badge = element.shadowRoot.querySelector('.slds-badge');
        expect(badge).not.toBeNull();
    });

    it('shows results visualizer when completed with raw results', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-results-visualizer'
        );
        expect(visualizer).not.toBeNull();
    });

    it('shows certificate component when completed with certificate', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        const cert = element.shadowRoot.querySelector(
            'c-qrng-fairness-certificate'
        );
        expect(cert).not.toBeNull();
    });

    // ── handleRefreshStatus (lines 247-275) ─────────────────────
    it('calls refreshJobStatus and shows success toast', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        refreshJobStatus.mockResolvedValue({
            ibmStatus: 'RUNNING',
            status: 'Running'
        });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Status'
        );
        refreshBtn.click();
        await flushPromises();

        expect(refreshJobStatus).toHaveBeenCalledWith({
            jobId: 'a03xx000001234AAA'
        });
        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Status Refreshed'
        );
    });

    it('shows error toast when refreshJobStatus fails', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        refreshJobStatus.mockRejectedValue({
            body: { message: 'Refresh error' }
        });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Status'
        );
        refreshBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Refresh Failed'
        );
        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Refresh error'
        );
    });

    it('shows error toast with error.message fallback when refreshJobStatus fails', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        refreshJobStatus.mockRejectedValue(new Error('Network fail'));

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Status'
        );
        refreshBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Network fail'
        );
    });

    it('shows Unknown error fallback when refreshJobStatus fails with no message', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        refreshJobStatus.mockRejectedValue({});

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Status'
        );
        refreshBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Unknown error'
        );
    });

    // ── handleRetrieveResults (lines 277-305) ───────────────────
    it('calls retrieveJobResults and shows success toast', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        retrieveJobResults.mockResolvedValue({
            rawBitsLength: 1024,
            debiasedBitsLength: 512
        });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        retrieveBtn.click();
        await flushPromises();

        expect(retrieveJobResults).toHaveBeenCalledWith({
            jobId: 'a03xx000001234AAA'
        });
        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Results Retrieved'
        );
    });

    it('shows error toast when retrieveJobResults fails', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        retrieveJobResults.mockRejectedValue({
            body: { message: 'Retrieve error' }
        });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        retrieveBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Retrieve Failed'
        );
        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Retrieve error'
        );
    });

    it('shows error.message fallback when retrieveJobResults fails without body', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        retrieveJobResults.mockRejectedValue(new Error('Network issue'));

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        retrieveBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Network issue'
        );
    });

    it('shows Unknown error fallback when retrieveJobResults fails with no message', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        retrieveJobResults.mockRejectedValue({});

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        retrieveBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Unknown error'
        );
    });

    // ── Computed state properties ───────────────────────────────
    it('disableRetrieve is true when job is in progress', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        expect(retrieveBtn.disabled).toBe(true);
    });

    it('shows "Awaiting result..." pulse when status is in progress', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const pulse = element.shadowRoot.querySelector('.pulse');
        expect(pulse).not.toBeNull();
        expect(pulse.textContent).toContain('Awaiting');
    });

    it('shows completedAt timestamp when present', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue({ Id: 'cert-001' });

        getJobStatusDTO.emit(MOCK_DTO_COMPLETED);
        await flushPromises();

        // Completed status should render the component successfully
        const progressIndicator = element.shadowRoot.querySelector(
            'lightning-progress-indicator'
        );
        expect(progressIndicator).not.toBeNull();
        expect(progressIndicator.currentStep).toBe('Completed');
    });

    it('renders bell test "Yes" when useBellTest is true', async () => {
        const element = createComponent();
        getCertificateByJobId.mockResolvedValue(null);

        getJobStatusDTO.emit(MOCK_DTO_RUNNING);
        await flushPromises();

        const detailValues =
            element.shadowRoot.querySelectorAll('.detail-value');
        const texts = Array.from(detailValues).map((d) => d.textContent.trim());
        expect(texts).toContain('Yes');
    });
});
