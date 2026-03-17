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

        // getContext should have been called (circuit drawn)
        expect(HTMLCanvasElement.prototype.getContext).toHaveBeenCalled();

        // Verify the description text shows the qubit count
        const description = element.shadowRoot.querySelector(
            '.slds-text-body_small'
        );
        expect(description).not.toBeNull();
        expect(description.textContent).toContain('6');
    });

    it('changes circuit description when useBellTest is set to true', async () => {
        const element = createComponent({
            numQubits: 4,
            useBellTest: true
        });
        await flushPromises();

        // With useBellTest true, the template shows "Bell-Test QRNG" text
        const description = element.shadowRoot.querySelector(
            '.slds-text-body_small'
        );
        expect(description).not.toBeNull();
        expect(description.textContent).toContain('Bell-Test QRNG');
    });
});
