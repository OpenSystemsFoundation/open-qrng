import { createElement } from 'lwc';
import QrngRequestForm from 'c/qrngRequestForm';
import submitQRNGJob from '@salesforce/apex/QRNGSetupController.submitQRNGJob';

// Wire adapter for @wire-decorated property
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

// Imperative Apex mock
jest.mock(
    '@salesforce/apex/QRNGSetupController.submitQRNGJob',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// Mock ResizeObserver (used by child c-qrng-circuit-visualizer)
class MockResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
}

// Mock Canvas getContext (used by child c-qrng-circuit-visualizer)
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
    font: '',
    fillStyle: '',
    strokeStyle: '',
    lineWidth: 1,
    textAlign: '',
    textBaseline: ''
};

describe('c-qrng-request-form', () => {
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

    function createComponent() {
        const element = createElement('c-qrng-request-form', {
            is: QrngRequestForm
        });
        document.body.appendChild(element);
        return element;
    }

    it('renders form inputs', () => {
        const element = createComponent();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
        expect(combobox.label).toBe('Backend');

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const inputLabels = Array.from(inputs).map((i) => i.label);
        expect(inputLabels).toContain('Number of Qubits');
        expect(inputLabels).toContain('Shots');
        expect(inputLabels).toContain('Use Bell Test (stronger certification)');

        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        expect(textarea).not.toBeNull();
        expect(textarea.label).toBe('Purpose');
    });

    it('renders circuit visualizer child component', () => {
        const element = createComponent();

        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-circuit-visualizer'
        );
        expect(visualizer).not.toBeNull();
    });

    it('dispatches jobsubmitted event on successful submit', async () => {
        const element = createComponent();

        submitQRNGJob.mockResolvedValue('001xx000003DGb1');

        // Set purpose via the component's handler
        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = 'Test purpose';
        textarea.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const handler = jest.fn();
        element.addEventListener('jobsubmitted', handler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        expect(submitButton).toBeDefined();
        submitButton.click();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.jobId).toBe('001xx000003DGb1');
    });

    it('submits job without purpose (purpose is optional)', async () => {
        const element = createComponent();

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        expect(submitButton).toBeDefined();
        submitButton.click();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.variant).toBe('success');
    });

    it('toggles useBellTest when bell test checkbox is changed', async () => {
        const element = createComponent();

        const bellTestInput = Array.from(
            element.shadowRoot.querySelectorAll('lightning-input')
        ).find((i) => i.label === 'Use Bell Test (stronger certification)');
        expect(bellTestInput).not.toBeNull();

        bellTestInput.checked = true;
        bellTestInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-circuit-visualizer'
        );
        expect(visualizer.useBellTest).toBe(true);
    });

    // ── wiredSettings coverage (lines 20-46) ────────────────────
    it('populates form defaults from wire settings with useLeastBusy', async () => {
        const getSettings =
            require('@salesforce/apex/QRNGSetupController.getSettings').default;
        const element = createComponent();

        getSettings.emit({
            defaultShots: 2048,
            useBellTest: true,
            useLeastBusy: true,
            defaultBackend: 'ibm_brisbane',
            cachedBackends: [
                { name: 'ibm_brisbane', qubits: 127, status: 'online' },
                {
                    name: 'ibm_kyoto',
                    qubits: 127,
                    status: { name: 'online' }
                }
            ]
        });
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('__least_busy__');
        // 2 backends + Least Busy option
        expect(combobox.options.length).toBe(3);

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        expect(shotsInput.value).toBe(2048);
    });

    it('populates form defaults from wire settings with explicit backend', async () => {
        const getSettings =
            require('@salesforce/apex/QRNGSetupController.getSettings').default;
        const element = createComponent();

        getSettings.emit({
            defaultShots: 512,
            useBellTest: false,
            useLeastBusy: false,
            defaultBackend: 'ibm_kyoto',
            cachedBackends: [
                { name: 'ibm_kyoto', qubits: 127, status: 'online' }
            ]
        });
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('ibm_kyoto');
    });

    // ── handleBackendChange (lines 57-58) ───────────────────────
    it('updates backend on combobox change', async () => {
        const element = createComponent();
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'ibm_brisbane' } })
        );
        await flushPromises();

        // Submit and check that backend was sent
        submitQRNGJob.mockResolvedValue('job-001');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQRNGJob).toHaveBeenCalledWith(
            expect.objectContaining({ backend: 'ibm_brisbane' })
        );
    });

    // ── handleQubitsChange (lines 59-61) ────────────────────────
    it('updates numQubits on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const qubitsInput = Array.from(inputs).find(
            (i) => i.label === 'Number of Qubits'
        );
        qubitsInput.value = '16';
        qubitsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        submitQRNGJob.mockResolvedValue('job-002');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQRNGJob).toHaveBeenCalledWith(
            expect.objectContaining({ numQubits: 16 })
        );
    });

    // ── handleShotsChange (lines 62-64) ─────────────────────────
    it('updates shots on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        shotsInput.value = '4096';
        shotsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        submitQRNGJob.mockResolvedValue('job-003');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQRNGJob).toHaveBeenCalledWith(
            expect.objectContaining({ shots: 4096 })
        );
    });

    // ── handleSubmit error path (lines 98-108) ──────────────────
    it('shows error toast when submit fails', async () => {
        const element = createComponent();
        await flushPromises();

        submitQRNGJob.mockRejectedValue({
            body: { message: 'Submit error' }
        });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Submit error'
        );
    });

    it('shows error.message fallback when submit fails without body', async () => {
        const element = createComponent();
        await flushPromises();

        submitQRNGJob.mockRejectedValue(new Error('Network fail'));

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'Network fail'
        );
    });

    // ── handleSubmit with __least_busy__ backend (line 76) ──────
    it('submits empty backend when __least_busy__ is selected', async () => {
        const getSettings =
            require('@salesforce/apex/QRNGSetupController.getSettings').default;
        const element = createComponent();

        getSettings.emit({
            defaultShots: 1024,
            useBellTest: false,
            useLeastBusy: true,
            defaultBackend: '',
            cachedBackends: []
        });
        await flushPromises();

        submitQRNGJob.mockResolvedValue('job-004');

        const handler = jest.fn();
        element.addEventListener('jobsubmitted', handler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQRNGJob).toHaveBeenCalledWith(
            expect.objectContaining({ backend: '' })
        );
    });

    // ── effectiveQubits getter (lines 50-54) ────────────────────
    it('passes effectiveQubits to circuit visualizer', async () => {
        const element = createComponent();
        await flushPromises();

        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-circuit-visualizer'
        );
        // Default: bellTest=false, numQubits=8 -> effectiveQubits = 8
        expect(visualizer.numQubits).toBe(8);
    });
});
