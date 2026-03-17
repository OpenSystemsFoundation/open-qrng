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

    it('shows error toast when purpose is empty on submit', async () => {
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
        expect(handler.mock.calls[0][0].detail.variant).toBe('warning');
        expect(handler.mock.calls[0][0].detail.message).toContain('purpose');
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
});
