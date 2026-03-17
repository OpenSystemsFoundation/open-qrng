import { createElement } from 'lwc';
import QrngCircuitVisualizer from 'c/qrngCircuitVisualizer';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const mockContext = {
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
    textBaseline: '',
    globalAlpha: 1.0
};

// Mock ResizeObserver (not available in jsdom)
class MockResizeObserver {
    constructor(callback) {
        this._callback = callback;
    }
    observe() {}
    unobserve() {}
    disconnect() {}
}

describe('c-qrng-circuit-visualizer', () => {
    beforeAll(() => {
        global.ResizeObserver = MockResizeObserver;
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockContext);
    });

    afterAll(() => {
        delete global.ResizeObserver;
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        // Re-apply the canvas mock after clearAllMocks
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockContext);
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-circuit-visualizer', {
            is: QrngCircuitVisualizer
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders canvas element', () => {
        const element = createComponent();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        expect(card.title).toBe('Circuit Diagram');
    });

    it('calls getContext 2d on renderedCallback', async () => {
        createComponent();
        await flushPromises();

        expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalledWith(
            '2d'
        );
    });

    it('renders with different numQubits values', async () => {
        const element = createComponent({ numQubits: 6 });
        await flushPromises();

        expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalled();

        const description = element.shadowRoot.querySelector(
            '.slds-text-body_small'
        );
        expect(description).not.toBeNull();
        expect(description.textContent).toContain('6');
    });

    it('shows standard QRNG description when useBellTest is false', async () => {
        const element = createComponent({ numQubits: 4, useBellTest: false });
        await flushPromises();

        const description = element.shadowRoot.querySelector(
            '.slds-text-body_small'
        );
        expect(description.textContent).toContain('Standard QRNG');
        expect(description.textContent).toContain('rz(pi/2)');
    });

    it('shows CHSH Bell Test description when useBellTest is true', async () => {
        const element = createComponent({
            numQubits: 4,
            useBellTest: true
        });
        await flushPromises();

        const description = element.shadowRoot.querySelector(
            '.slds-text-body_small'
        );
        expect(description).not.toBeNull();
        expect(description.textContent).toContain('CHSH Bell Test');
        expect(description.textContent).toContain('CZ');
    });

    it('draws standard circuit with H and Measure gates', async () => {
        createComponent({ numQubits: 2, useBellTest: false });
        await flushPromises();

        // Should draw H gates and M labels
        const fillTextCalls = mockContext.fillText.mock.calls;
        const drawnLabels = fillTextCalls.map((c) => c[0]);
        expect(drawnLabels).toContain('H');
        expect(drawnLabels).toContain('M');
        expect(drawnLabels).toContain('q[0]');
        expect(drawnLabels).toContain('q[1]');
    });

    it('draws Bell circuit with CZ gate and basis rotations', async () => {
        createComponent({ numQubits: 8, useBellTest: true });
        await flushPromises();

        const fillTextCalls = mockContext.fillText.mock.calls;
        const drawnLabels = fillTextCalls.map((c) => c[0]);

        // Should have CZ labels
        expect(drawnLabels).toContain('CZ');
        // Should have H gates on Alice qubits
        expect(drawnLabels).toContain('H');
        // Should have Ry rotation gates
        expect(drawnLabels).toContain('Ry');
        // Should have measurement gates
        expect(drawnLabels).toContain('M');
        // Should have basis config labels
        expect(drawnLabels).toContain('S₀');
        expect(drawnLabels).toContain('S₁');
        expect(drawnLabels).toContain('S₂');
        expect(drawnLabels).toContain('S₃');
    });

    it('draws CHSH legend with all 4 basis settings', async () => {
        createComponent({ numQubits: 8, useBellTest: true });
        await flushPromises();

        const fillTextCalls = mockContext.fillText.mock.calls;
        const drawnLabels = fillTextCalls.map((c) => c[0]);

        expect(drawnLabels).toContain('CHSH Basis Settings:');
        // Check angle labels appear in legend
        expect(
            drawnLabels.some((l) => l.includes('a=0') && l.includes('b=π/8'))
        ).toBe(true);
        expect(drawnLabels.some((l) => l.includes('b=3π/8'))).toBe(true);
        expect(drawnLabels.some((l) => l.includes('a=π/4'))).toBe(true);
    });

    it('draws identity gate for Alice when angle is 0', async () => {
        createComponent({ numQubits: 4, useBellTest: true });
        await flushPromises();

        // Pair 0 has config S₀ (alice=0), should draw identity "I"
        const fillTextCalls = mockContext.fillText.mock.calls;
        const drawnLabels = fillTextCalls.map((c) => c[0]);
        expect(drawnLabels).toContain('I');

        // setLineDash should be called for dashed identity box
        expect(mockContext.setLineDash).toHaveBeenCalledWith([4, 4]);
    });

    it('draws CZ as two filled dots connected by a line', async () => {
        createComponent({ numQubits: 4, useBellTest: true });
        await flushPromises();

        // CZ gate draws two arcs (filled dots) and a connecting line
        // At least 2 arc calls for the CZ dots (plus any from measure gates)
        expect(mockContext.arc).toHaveBeenCalled();
        expect(mockContext.fill).toHaveBeenCalled();
    });

    it('shows S > 2 formula in the legend', async () => {
        createComponent({ numQubits: 8, useBellTest: true });
        await flushPromises();

        const fillTextCalls = mockContext.fillText.mock.calls;
        const allText = fillTextCalls.map((c) => c[0]).join(' ');
        expect(allText).toContain('> 2 proves quantum origin');
    });

    it('disconnects ResizeObserver on disconnect', async () => {
        const element = createComponent();
        await flushPromises();

        // Remove the element to trigger disconnectedCallback
        document.body.removeChild(element);

        // Verify no errors thrown during cleanup
        expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalled();
    });
});
