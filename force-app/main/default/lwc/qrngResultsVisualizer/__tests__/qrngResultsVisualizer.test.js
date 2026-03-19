import { createElement } from '@lwc/engine-dom';
import QrngResultsVisualizer from 'c/qrngResultsVisualizer';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-qrng-results-visualizer', () => {
    let mockContext;

    beforeEach(() => {
        // jsdom does not provide ResizeObserver
        global.ResizeObserver = jest.fn().mockImplementation(() => ({
            observe: jest.fn(),
            unobserve: jest.fn(),
            disconnect: jest.fn()
        }));

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
        const element = createElement('c-qrng-results-visualizer', {
            is: QrngResultsVisualizer
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders "No measurement data available" when rawResults is empty', () => {
        const element = createComponent({ rawResults: '' });

        const emptyMsg = element.shadowRoot.querySelector(
            '.slds-text-color_weak'
        );
        expect(emptyMsg).not.toBeNull();
        expect(emptyMsg.textContent).toContain('No measurement data available');
    });

    it('renders canvas when rawResults is provided', async () => {
        const element = createComponent({
            rawResults: '0110100111000101',
            numQubits: 4
        });
        await flushPromises();

        const canvas = element.shadowRoot.querySelector('canvas');
        expect(canvas).not.toBeNull();
    });

    it('calls getContext("2d") when data is present', async () => {
        createComponent({
            rawResults: '0110100111000101',
            numQubits: 4
        });
        await flushPromises();

        expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalledWith(
            '2d'
        );
    });

    it('computes distribution correctly (totalSamples, uniqueCount)', async () => {
        // 16 bits / 4 qubits = 4 samples: '0110', '1001', '1100', '0101'
        const element = createComponent({
            rawResults: '0110100111000101',
            numQubits: 4
        });
        await flushPromises();

        const cols = element.shadowRoot.querySelectorAll('.slds-col');
        const texts = Array.from(cols).map((c) => c.textContent.trim());
        expect(texts.some((t) => t.includes('Total samples: 4'))).toBe(true);
        expect(texts.some((t) => t.includes('Unique bitstrings: 4'))).toBe(
            true
        );
    });

    it('shows possible bitstring count based on numQubits', async () => {
        const element = createComponent({
            rawResults: '0110100111000101',
            numQubits: 4
        });
        await flushPromises();

        const cols = element.shadowRoot.querySelectorAll('.slds-col');
        const texts = Array.from(cols).map((c) => c.textContent.trim());
        // 2^4 = 16 possible
        expect(texts.some((t) => t.includes('/ 16'))).toBe(true);
    });

    it('handles different numQubits values', async () => {
        // 16 bits / 8 qubits = 2 samples
        const element = createComponent({
            rawResults: '0110100111000101',
            numQubits: 8
        });
        await flushPromises();

        const cols = element.shadowRoot.querySelectorAll('.slds-col');
        const texts = Array.from(cols).map((c) => c.textContent.trim());
        expect(texts.some((t) => t.includes('Total samples: 2'))).toBe(true);
        expect(texts.some((t) => t.includes('Unique bitstrings: 2'))).toBe(
            true
        );
    });

    it('renders Raw Results section title', async () => {
        const element = createComponent({
            rawResults: '0110100111000101',
            numQubits: 4
        });
        await flushPromises();

        const titles = element.shadowRoot.querySelectorAll(
            '.chart-section-title'
        );
        expect(titles.length).toBeGreaterThanOrEqual(1);
        expect(titles[0].textContent).toContain('Raw Results');
    });

    it('renders debiased chart when debiasedResults is provided', async () => {
        const element = createComponent({
            rawResults: '0110100111000101',
            debiasedResults: '01101001',
            numQubits: 4
        });
        await flushPromises();

        const titles = element.shadowRoot.querySelectorAll(
            '.chart-section-title'
        );
        const titleTexts = Array.from(titles).map((t) => t.textContent.trim());
        expect(titleTexts.some((t) => t.includes('Debiased'))).toBe(true);
    });

    it('does not render debiased chart when debiasedResults is empty', async () => {
        const element = createComponent({
            rawResults: '0110100111000101',
            debiasedResults: '',
            numQubits: 4
        });
        await flushPromises();

        const titles = element.shadowRoot.querySelectorAll(
            '.chart-section-title'
        );
        expect(titles.length).toBe(1);
        expect(titles[0].textContent).toContain('Raw Results');
    });
});
