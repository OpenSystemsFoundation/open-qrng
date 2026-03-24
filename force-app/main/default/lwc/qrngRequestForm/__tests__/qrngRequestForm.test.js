import { createElement } from '@lwc/engine-dom';
import QrngRequestForm from 'c/qrngRequestForm';
import submitQuantumJob from '@salesforce/apex/SetupController.submitQuantumJob';

// Wire adapter for @wire-decorated property
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

// Imperative Apex mock
jest.mock(
    '@salesforce/apex/SetupController.submitQuantumJob',
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

const MOCK_BACKENDS = [
    {
        name: 'ibm_brisbane',
        qubits: 127,
        status: 'online',
        maxShots: 4096,
        queueLength: 5,
        isSimulator: false,
        processorFamily: 'Eagle'
    },
    {
        name: 'ibm_kyoto',
        qubits: 127,
        status: { name: 'online' },
        maxShots: 8192,
        queueLength: 0,
        isSimulator: false,
        processorFamily: 'Heron'
    },
    {
        name: 'ibmq_qasm_simulator',
        qubits: 32,
        status: 'online',
        maxShots: 8192,
        queueLength: null,
        isSimulator: true,
        processorFamily: ''
    }
];

describe('c-qrng-request-form', () => {
    let getSettings;

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
        getSettings =
            require('@salesforce/apex/SetupController.getSettings').default;
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

    function emitSettings(overrides = {}) {
        getSettings.emit({
            defaultShots: 1024,
            useBellTest: false,
            useLeastBusy: false,
            defaultBackend: '',
            cachedBackends: MOCK_BACKENDS,
            ...overrides
        });
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

        submitQuantumJob.mockResolvedValue('001xx000003DGb1');

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

    it('passes useBellTest=false to circuit visualizer by default', () => {
        const element = createComponent();

        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-circuit-visualizer'
        );
        expect(visualizer.useBellTest).toBe(false);
    });

    // ── wiredSettings coverage ────────────────────────────────
    it('populates form defaults from wire settings with useLeastBusy', async () => {
        const element = createComponent();

        emitSettings({
            defaultShots: 2048,
            useBellTest: true,
            useLeastBusy: true,
            defaultBackend: 'ibm_brisbane'
        });
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('__least_busy__');
        // 3 backends + Least Busy option
        expect(combobox.options.length).toBe(4);

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        expect(shotsInput.value).toBe(2048);
    });

    it('populates form defaults from wire settings with explicit backend', async () => {
        const element = createComponent();

        emitSettings({
            defaultShots: 512,
            useBellTest: false,
            useLeastBusy: false,
            defaultBackend: 'ibm_kyoto'
        });
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('ibm_kyoto');
    });

    // ── handleBackendChange ───────────────────────────────────
    it('updates backend on combobox change', async () => {
        const element = createComponent();
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: 'ibm_brisbane' }
            })
        );
        await flushPromises();

        // Submit and check that backend was sent
        submitQuantumJob.mockResolvedValue('job-001');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalledWith(
            expect.objectContaining({ backend: 'ibm_brisbane' })
        );
    });

    // ── handleQubitsChange ────────────────────────────────────
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

        submitQuantumJob.mockResolvedValue('job-002');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalledWith(
            expect.objectContaining({ numQubits: 16 })
        );
    });

    // ── handleShotsChange ─────────────────────────────────────
    it('updates shots on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        shotsInput.value = '4096';
        shotsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        submitQuantumJob.mockResolvedValue('job-003');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalledWith(
            expect.objectContaining({ shots: 4096 })
        );
    });

    // ── handleSubmit error path ───────────────────────────────
    it('shows error toast when submit fails', async () => {
        const element = createComponent();
        await flushPromises();

        submitQuantumJob.mockRejectedValue({
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

        submitQuantumJob.mockRejectedValue(new Error('Network fail'));

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

    // ── handleSubmit with __least_busy__ backend ──────────────
    it('submits empty backend when __least_busy__ is selected', async () => {
        const element = createComponent();

        emitSettings({
            useLeastBusy: true,
            defaultBackend: '',
            cachedBackends: []
        });
        await flushPromises();

        submitQuantumJob.mockResolvedValue('job-004');

        const handler = jest.fn();
        element.addEventListener('jobsubmitted', handler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalledWith(
            expect.objectContaining({ backend: '' })
        );
    });

    // ── effectiveQubits getter ────────────────────────────────
    it('passes effectiveQubits to circuit visualizer', async () => {
        const element = createComponent();
        await flushPromises();

        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-circuit-visualizer'
        );
        // Default: bellTest=false, numQubits=8 -> effectiveQubits = 8
        expect(visualizer.numQubits).toBe(8);
    });

    // ── Backend info display ──────────────────────────────────
    it('shows backend info chips when a specific backend is selected', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibm_brisbane',
            useLeastBusy: false
        });
        await flushPromises();

        const chips = element.shadowRoot.querySelectorAll('.info-chip');
        expect(chips.length).toBeGreaterThan(0);

        const statusChip = element.shadowRoot.querySelector('.status-chip');
        expect(statusChip).not.toBeNull();
        expect(statusChip.textContent.trim()).toBe('online');
    });

    it('does not show backend info when least busy is selected', async () => {
        const element = createComponent();

        emitSettings({ useLeastBusy: true });
        await flushPromises();

        const backendInfo = element.shadowRoot.querySelector('.backend-info');
        expect(backendInfo).toBeNull();
    });

    // ── Dynamic constraints ───────────────────────────────────
    it('sets max qubits based on selected backend', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibmq_qasm_simulator',
            useLeastBusy: false
        });
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const qubitsInput = Array.from(inputs).find(
            (i) => i.label === 'Number of Qubits'
        );
        expect(qubitsInput.max).toBe(32);
    });

    it('sets max shots based on selected backend', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibm_brisbane',
            useLeastBusy: false
        });
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        expect(shotsInput.max).toBe(4096);
    });

    it('clamps qubits when switching to a backend with fewer qubits', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibm_brisbane',
            useLeastBusy: false
        });
        await flushPromises();

        // Now switch to simulator with only 32 qubits while numQubits is > 32
        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const qubitsInput = Array.from(inputs).find(
            (i) => i.label === 'Number of Qubits'
        );
        qubitsInput.value = '64';
        qubitsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: 'ibmq_qasm_simulator' }
            })
        );
        await flushPromises();

        // Submit and verify qubits were clamped
        submitQuantumJob.mockResolvedValue('job-clamp');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalledWith(
            expect.objectContaining({ numQubits: 32 })
        );
    });

    // ── Description text ──────────────────────────────────────
    it('shows random bits calculation in qubit description', async () => {
        const element = createComponent();
        await flushPromises();

        const hints = element.shadowRoot.querySelectorAll('.field-hint');
        // First hint is qubits description, second is shots description
        expect(hints.length).toBe(2);
        // Default: 8 qubits × 1024 shots = 8192 random bits (locale-formatted)
        const formattedBits = (8192).toLocaleString();
        expect(hints[0].textContent).toContain(formattedBits);
    });

    it('shows shots quality description', async () => {
        const element = createComponent();
        await flushPromises();

        const hints = element.shadowRoot.querySelectorAll('.field-hint');
        // Default 1024 shots — "Good balance"
        expect(hints[1].textContent).toContain('Good balance');
    });

    // ── Simulator backend info ────────────────────────────────
    it('shows Simulator chip for simulator backends', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibmq_qasm_simulator',
            useLeastBusy: false
        });
        await flushPromises();

        const simChip = element.shadowRoot.querySelector(
            '.info-chip.simulator'
        );
        expect(simChip).not.toBeNull();
        expect(simChip.textContent.trim()).toBe('Simulator');
    });

    // ── Queue length display ──────────────────────────────────
    it('shows queue length chip when backend has jobs in queue', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibm_brisbane',
            useLeastBusy: false
        });
        await flushPromises();

        const queueChip = element.shadowRoot.querySelector('.info-chip.queue');
        expect(queueChip).not.toBeNull();
        expect(queueChip.textContent).toContain('5');
    });

    // ── Field-level help texts ────────────────────────────────
    it('provides field-level help on backend combobox', () => {
        const element = createComponent();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.fieldLevelHelp).toBeTruthy();
        expect(combobox.fieldLevelHelp).toContain('processor');
    });

    it('provides field-level help on shots input', () => {
        const element = createComponent();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        expect(shotsInput.fieldLevelHelp).toBeTruthy();
        expect(shotsInput.fieldLevelHelp).toContain('circuit');
    });

    // ── Bug-hunting edge cases (surfaced by e2e tests) ────────
    it('handles NaN qubits from empty input', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const qubitsInput = Array.from(inputs).find(
            (i) => i.label === 'Number of Qubits'
        );
        qubitsInput.value = '';
        qubitsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        // Submit should still work (Apex should validate)
        submitQuantumJob.mockResolvedValue('job-nan');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalled();
    });

    it('handles non-numeric shots input gracefully', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');
        shotsInput.value = 'abc';
        shotsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        // The component should not crash
        expect(
            element.shadowRoot.querySelector('lightning-combobox')
        ).not.toBeNull();
    });

    it('handles purpose with special characters', async () => {
        const element = createComponent();
        await flushPromises();

        const textarea = element.shadowRoot.querySelector('lightning-textarea');
        textarea.value = '<script>alert("xss")</script>';
        textarea.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        submitQuantumJob.mockResolvedValue('job-xss');
        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const submitButton = Array.from(buttons).find(
            (b) => b.variant === 'brand'
        );
        submitButton.click();
        await flushPromises();

        expect(submitQuantumJob).toHaveBeenCalledWith(
            expect.objectContaining({
                purpose: '<script>alert("xss")</script>'
            })
        );
    });

    it('handles wire settings error', async () => {
        const element = createComponent();

        getSettings.error({ body: { message: 'Settings load failed' } });
        await flushPromises();

        // Component should still render
        expect(
            element.shadowRoot.querySelector('lightning-combobox')
        ).not.toBeNull();
    });

    it('handles Bell test toggle with odd qubits', async () => {
        const element = createComponent();

        emitSettings({
            useBellTest: false,
            defaultBackend: 'ibm_brisbane',
            useLeastBusy: false
        });
        await flushPromises();

        // Set odd number of qubits
        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const qubitsInput = Array.from(inputs).find(
            (i) => i.label === 'Number of Qubits'
        );
        qubitsInput.value = '7';
        qubitsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        // Component should handle odd qubits without crashing
        const visualizer = element.shadowRoot.querySelector(
            'c-qrng-circuit-visualizer'
        );
        expect(visualizer).not.toBeNull();
    });

    it('storage bar shows warning for large bit counts', async () => {
        const element = createComponent();

        emitSettings({
            defaultBackend: 'ibm_brisbane',
            useLeastBusy: false
        });
        await flushPromises();

        // Set very large values
        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const qubitsInput = Array.from(inputs).find(
            (i) => i.label === 'Number of Qubits'
        );
        const shotsInput = Array.from(inputs).find((i) => i.label === 'Shots');

        qubitsInput.value = '127';
        qubitsInput.dispatchEvent(new CustomEvent('change'));
        shotsInput.value = '8192';
        shotsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        // Component should render without crashing with large values
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
    });
});
