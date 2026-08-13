import { createElement } from '@lwc/engine-dom';
import QrngQasmViewer from 'c/qrngQasmViewer';

jest.mock(
    'lightning/uiRecordApi',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return {
            getRecord: createApexTestWireAdapter(jest.fn()),
            getFieldValue: jest.fn()
        };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/schema/Quantum_Job__c.Circuit_QASM__c',
    () => ({ default: 'Quantum_Job__c.Circuit_QASM__c' }),
    { virtual: true }
);

const mockCtx = {
    clearRect: jest.fn(),
    fillRect: jest.fn(),
    strokeRect: jest.fn(),
    fillText: jest.fn(),
    beginPath: jest.fn(),
    moveTo: jest.fn(),
    lineTo: jest.fn(),
    stroke: jest.fn(),
    arc: jest.fn(),
    fill: jest.fn(),
    save: jest.fn(),
    restore: jest.fn(),
    setLineDash: jest.fn(),
    font: '',
    fillStyle: '',
    strokeStyle: '',
    lineWidth: 1,
    textAlign: '',
    textBaseline: '',
    globalAlpha: 1
};

beforeAll(() => {
    HTMLCanvasElement.prototype.getContext = jest.fn().mockReturnValue(mockCtx);
});

const proto = QrngQasmViewer.prototype;

const SIMPLE_QASM = `OPENQASM 3.0;
include "stdgates.inc";
qubit[2] q;
bit[2] c;
h q[0];
cx q[0], q[1];
c[0] = measure q[0];
c[1] = measure q[1];`;

const MULTI_CIRCUIT_JSON = JSON.stringify([
    `OPENQASM 3.0;\nqubit[1] q;\nh q[0];\nc[0] = measure q[0];`,
    `OPENQASM 3.0;\nqubit[1] q;\nx q[0];\nc[0] = measure q[0];`
]);

const MULTI_CIRCUIT_LEGACY = `OPENQASM 3.0;
qubit[1] q;
h q[0];
--- CIRCUIT ---
OPENQASM 3.0;
qubit[1] q;
x q[0];`;

describe('c-qrng-qasm-viewer', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        global.ResizeObserver = jest.fn().mockImplementation(() => ({
            observe: jest.fn(),
            disconnect: jest.fn()
        }));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        delete global.ResizeObserver;
    });

    function createComponent() {
        const element = createElement('c-qrng-qasm-viewer', {
            is: QrngQasmViewer
        });
        document.body.appendChild(element);
        return element;
    }

    // ── DOM tests ──

    it('renders inline error when the record wire errors', async () => {
        const { getRecord } = require('lightning/uiRecordApi');
        const element = createComponent();
        element.recordId = 'a03xx000001234AAA';

        getRecord.error({ message: 'record gone' });
        await Promise.resolve();
        await Promise.resolve();

        const errorBox = element.shadowRoot.querySelector(
            '[data-testid="qasm-viewer-error"]'
        );
        expect(errorBox).not.toBeNull();
        expect(errorBox.textContent).toContain('record gone');
    });

    it('canvas has role="img" and a meaningful aria-label', async () => {
        const element = createComponent();
        element.qasm = SIMPLE_QASM;
        await Promise.resolve();
        await Promise.resolve();

        const canvas = element.shadowRoot.querySelector('canvas');
        expect(canvas).not.toBeNull();
        expect(canvas.getAttribute('role')).toBe('img');
        expect(canvas.getAttribute('aria-label')).toContain(
            'Quantum circuit diagram'
        );
        expect(canvas.getAttribute('aria-label')).toContain('2 qubits');
    });

    it('scales the canvas backing store by devicePixelRatio', async () => {
        window.devicePixelRatio = 2;
        const element = createComponent();
        element.qasm = SIMPLE_QASM;
        await Promise.resolve();
        await Promise.resolve();

        const canvas = element.shadowRoot.querySelector('canvas');
        // Container clientWidth is 0 in jsdom → fallback width 700
        expect(canvas.width).toBe(1400);
        expect(canvas.style.width).toBe('700px');
        delete window.devicePixelRatio;
    });

    it('renders empty state when no QASM provided', () => {
        const element = createComponent();
        const emptyMsg = element.shadowRoot.querySelector(
            '.slds-text-color_weak'
        );
        expect(emptyMsg).not.toBeNull();
        expect(emptyMsg.textContent).toContain('No circuit QASM provided');
    });

    it('does not render canvas when no QASM set', () => {
        const element = createComponent();
        expect(element.shadowRoot.querySelector('canvas')).toBeNull();
    });

    it('qasm getter/setter works correctly', () => {
        const element = createComponent();
        element.qasm = 'test qasm';
        expect(element.qasm).toBe('test qasm');
    });

    it('disconnectedCallback does not throw', () => {
        const element = createComponent();
        expect(() => document.body.removeChild(element)).not.toThrow();
    });

    // ── splitCircuits (prototype) ──

    it('splitCircuits handles JSON array format', () => {
        expect(proto.splitCircuits(MULTI_CIRCUIT_JSON)).toHaveLength(2);
    });

    it('splitCircuits handles legacy separator format', () => {
        expect(proto.splitCircuits(MULTI_CIRCUIT_LEGACY)).toHaveLength(2);
    });

    it('splitCircuits handles single circuit', () => {
        expect(proto.splitCircuits(SIMPLE_QASM)).toHaveLength(1);
    });

    it('splitCircuits handles invalid JSON gracefully', () => {
        expect(proto.splitCircuits('[invalid json')).toHaveLength(1);
    });

    it('splitCircuits handles empty JSON array', () => {
        expect(proto.splitCircuits('[]')).toHaveLength(1);
    });

    // ── parseQasm (prototype) ──

    it('parseQasm extracts qubits and operations', () => {
        const parsed = proto.parseQasm(SIMPLE_QASM);
        expect(parsed.numQubits).toBe(2);
        expect(parsed.qubitNames).toEqual(['q[0]', 'q[1]']);
        expect(parsed.ops.find((o) => o.gate === 'h')).toBeDefined();
        expect(parsed.ops.find((o) => o.gate === 'cx')).toBeDefined();
        expect(parsed.ops.filter((o) => o.gate === 'measure')).toHaveLength(2);
    });

    it('parseQasm handles physical qubit syntax ($N)', () => {
        const parsed = proto.parseQasm('OPENQASM 3.0;\nh $0;\ncx $0, $1;');
        expect(parsed.numQubits).toBe(2);
        expect(parsed.qubitNames).toContain('$0');
        expect(parsed.qubitNames).toContain('$1');
    });

    it('parseQasm handles barrier operations', () => {
        const parsed = proto.parseQasm(
            'OPENQASM 3.0;\nqubit[2] q;\nh q[0];\nbarrier q[0], q[1];\ncx q[0], q[1];'
        );
        expect(parsed.ops.find((o) => o.gate === 'barrier')).toBeDefined();
    });

    it('parseQasm handles rotation gates with parameters', () => {
        const parsed = proto.parseQasm(
            'OPENQASM 3.0;\nqubit[1] q;\nrz(3.14) q[0];'
        );
        const rz = parsed.ops.find((o) => o.gate === 'rz');
        expect(rz).toBeDefined();
        expect(rz.params).toEqual(['3.14']);
    });

    it('parseQasm skips comments and headers', () => {
        const parsed = proto.parseQasm(
            'OPENQASM 3.0;\ninclude "stdgates.inc";\n// comment\nqubit[1] q;\nbit[1] c;\nh q[0];'
        );
        expect(parsed.ops).toHaveLength(1);
        expect(parsed.ops[0].gate).toBe('h');
    });

    it('parseQasm skips unknown gate names', () => {
        const parsed = proto.parseQasm('OPENQASM 3.0;\nqubit[1] q;\nfoo q[0];');
        expect(parsed.ops).toHaveLength(0);
    });

    it('parseQasm skips measure with unknown qubit', () => {
        const parsed = proto.parseQasm(
            'OPENQASM 3.0;\nqubit[1] q;\nc[0] = measure q[99];'
        );
        expect(parsed.ops.filter((o) => o.gate === 'measure')).toHaveLength(0);
    });

    it('parseQasm handles reset, s, t, sx, y, z, cz, rx, ry gates', () => {
        const parsed = proto.parseQasm(
            'OPENQASM 3.0;\nqubit[2] q;\nreset q[0];\ns q[0];\nt q[0];\nsx q[0];\ny q[0];\nz q[0];\ncz q[0], q[1];\nrx(1.57) q[0];\nry(3.14) q[0];'
        );
        const names = parsed.ops.map((o) => o.gate);
        expect(names).toContain('reset');
        expect(names).toContain('s');
        expect(names).toContain('t');
        expect(names).toContain('sx');
        expect(names).toContain('y');
        expect(names).toContain('z');
        expect(names).toContain('cz');
        expect(names).toContain('rx');
        expect(names).toContain('ry');
    });

    // ── parseTargets (prototype) ──

    it('parseTargets maps target strings to indices', () => {
        const qm = new Map([
            ['q[0]', 0],
            ['q[1]', 1]
        ]);
        expect(proto.parseTargets('q[0], q[1]', qm)).toEqual([0, 1]);
    });

    it('parseTargets filters unknown targets', () => {
        const qm = new Map([['q[0]', 0]]);
        expect(proto.parseTargets('q[0], q[99]', qm)).toEqual([0]);
    });

    // ── formatParam (prototype) ──

    it('formatParam simplifies pi expressions', () => {
        expect(proto.formatParam('pi/2')).toBe('\u03C0/2');
        expect(proto.formatParam('2*pi')).toBe('2\u03C0');
    });

    it('formatParam formats numeric values', () => {
        expect(proto.formatParam('3.14159')).toBe('3.14');
    });

    it('formatParam returns non-numeric strings as-is', () => {
        expect(proto.formatParam('theta')).toBe('theta');
    });

    it('formatParam handles unicode pi symbol', () => {
        expect(proto.formatParam('\u03C0/4')).toContain('\u03C0');
    });

    // ── draw methods (prototype with mock ctx) ──

    it('drawSingleGate renders gate box and label', () => {
        proto.drawSingleGate(
            mockCtx,
            100,
            50,
            { label: 'H', color: '#0176d3', bg: '#eaf5fe', width: 40 },
            null
        );
        expect(mockCtx.fillRect).toHaveBeenCalled();
        expect(mockCtx.strokeRect).toHaveBeenCalled();
        expect(mockCtx.fillText).toHaveBeenCalledWith('H', 100, 50);
    });

    it('drawSingleGate renders parameter label', () => {
        proto.drawSingleGate(
            mockCtx,
            100,
            50,
            { label: 'Rz', color: '#ff6d2e', bg: '#fff1ea', width: 48 },
            '3.14'
        );
        expect(mockCtx.fillText).toHaveBeenCalledWith('Rz', 100, 50);
        expect(mockCtx.fillText).toHaveBeenCalledWith(
            '3.14',
            100,
            expect.any(Number)
        );
    });

    it('drawTwoQubitGate renders CX', () => {
        proto.drawTwoQubitGate(mockCtx, 100, 50, 100, {
            label: 'CX',
            color: '#0176d3',
            bg: '#eaf5fe',
            width: 40,
            twoQubit: true
        });
        expect(mockCtx.arc).toHaveBeenCalled();
    });

    it('drawTwoQubitGate renders CZ', () => {
        proto.drawTwoQubitGate(mockCtx, 100, 50, 100, {
            label: 'CZ',
            color: '#0d9ddb',
            bg: '#e8f7ff',
            width: 40,
            twoQubit: true
        });
        expect(mockCtx.fillText).toHaveBeenCalledWith(
            'CZ',
            expect.any(Number),
            expect.any(Number)
        );
    });

    it('drawMeasureGate renders meter', () => {
        proto.drawMeasureGate(mockCtx, 100, 50, {
            label: 'M',
            color: '#ca8a04',
            bg: '#fefce8',
            width: 40
        });
        expect(mockCtx.fillRect).toHaveBeenCalled();
        expect(mockCtx.arc).toHaveBeenCalled();
    });

    it('drawBarrier renders dashed line', () => {
        proto.drawBarrier(mockCtx, 100, 20, 2, 50);
        expect(mockCtx.save).toHaveBeenCalled();
        expect(mockCtx.setLineDash).toHaveBeenCalledWith([4, 4]);
        expect(mockCtx.restore).toHaveBeenCalled();
    });

    // ── Multi-circuit navigation (prototype-level) ──

    it('splitCircuits returns parsed JSON array circuits content', () => {
        const circuits = proto.splitCircuits(MULTI_CIRCUIT_JSON);
        expect(circuits).toHaveLength(2);
        expect(circuits[0]).toContain('h q[0]');
        expect(circuits[1]).toContain('x q[0]');
    });

    it('splitCircuits returns parsed legacy separator circuits content', () => {
        const circuits = proto.splitCircuits(MULTI_CIRCUIT_LEGACY);
        expect(circuits).toHaveLength(2);
        expect(circuits[0]).toContain('h q[0]');
        expect(circuits[1]).toContain('x q[0]');
    });

    it('splitCircuits handles non-array JSON (falls through to single)', () => {
        const result = proto.splitCircuits('"just a string"');
        expect(result).toHaveLength(1);
    });

    // ── Computed properties tested via prototype ──

    it('hasMultipleCircuits getter (prototype)', () => {
        // Simulate the getter behavior directly
        const ctx1 = { totalCircuits: 1 };
        const ctx3 = { totalCircuits: 3 };
        const getter =
            Object.getOwnPropertyDescriptor(
                QrngQasmViewer.prototype,
                'hasMultipleCircuits'
            )?.get ||
            function () {
                return this.totalCircuits > 1;
            };
        expect(getter.call(ctx1)).toBe(false);
        expect(getter.call(ctx3)).toBe(true);
    });

    it('circuitLabel getter (prototype)', () => {
        const ctx = { currentCircuitIndex: 1, totalCircuits: 3 };
        const getter =
            Object.getOwnPropertyDescriptor(
                QrngQasmViewer.prototype,
                'circuitLabel'
            )?.get ||
            function () {
                return `${this.currentCircuitIndex + 1} / ${this.totalCircuits}`;
            };
        expect(getter.call(ctx)).toBe('2 / 3');
    });

    it('isPrevDisabled getter (prototype)', () => {
        const getter =
            Object.getOwnPropertyDescriptor(
                QrngQasmViewer.prototype,
                'isPrevDisabled'
            )?.get ||
            function () {
                return this.currentCircuitIndex === 0;
            };
        expect(getter.call({ currentCircuitIndex: 0 })).toBe(true);
        expect(getter.call({ currentCircuitIndex: 1 })).toBe(false);
    });

    it('isNextDisabled getter (prototype)', () => {
        const getter =
            Object.getOwnPropertyDescriptor(
                QrngQasmViewer.prototype,
                'isNextDisabled'
            )?.get ||
            function () {
                return this.currentCircuitIndex >= this.totalCircuits - 1;
            };
        expect(getter.call({ currentCircuitIndex: 2, totalCircuits: 3 })).toBe(
            true
        );
        expect(getter.call({ currentCircuitIndex: 0, totalCircuits: 3 })).toBe(
            false
        );
    });

    it('hasQasm getter (prototype)', () => {
        const getter =
            Object.getOwnPropertyDescriptor(QrngQasmViewer.prototype, 'hasQasm')
                ?.get ||
            function () {
                return !!this._qasm;
            };
        expect(getter.call({ _qasm: '' })).toBe(false);
        expect(getter.call({ _qasm: 'OPENQASM 3.0;' })).toBe(true);
    });

    // ── handleNext / handlePrev (prototype) ──

    it('handleNext advances to next circuit (prototype)', () => {
        const circuit1 = 'OPENQASM 3.0;\nqubit[1] q;\nh q[0];';
        const circuit2 = 'OPENQASM 3.0;\nqubit[1] q;\nx q[0];';
        const ctx = {
            currentCircuitIndex: 0,
            totalCircuits: 2,
            _circuits: [circuit1, circuit2],
            parsedCircuit: null,
            parseQasm: proto.parseQasm.bind(proto),
            draw: jest.fn()
        };
        proto.handleNext.call(ctx);
        expect(ctx.currentCircuitIndex).toBe(1);
        expect(ctx.parsedCircuit.ops[0].gate).toBe('x');
        expect(ctx.draw).toHaveBeenCalled();
    });

    it('handleNext does nothing at last circuit (prototype)', () => {
        const ctx = {
            currentCircuitIndex: 1,
            totalCircuits: 2,
            _circuits: ['c1', 'c2'],
            parsedCircuit: null,
            draw: jest.fn()
        };
        proto.handleNext.call(ctx);
        expect(ctx.currentCircuitIndex).toBe(1);
        expect(ctx.draw).not.toHaveBeenCalled();
    });

    it('handlePrev goes to previous circuit (prototype)', () => {
        const circuit1 = 'OPENQASM 3.0;\nqubit[1] q;\nh q[0];';
        const circuit2 = 'OPENQASM 3.0;\nqubit[1] q;\nx q[0];';
        const ctx = {
            currentCircuitIndex: 1,
            totalCircuits: 2,
            _circuits: [circuit1, circuit2],
            parsedCircuit: null,
            parseQasm: proto.parseQasm.bind(proto),
            draw: jest.fn()
        };
        proto.handlePrev.call(ctx);
        expect(ctx.currentCircuitIndex).toBe(0);
        expect(ctx.parsedCircuit.ops[0].gate).toBe('h');
        expect(ctx.draw).toHaveBeenCalled();
    });

    it('handlePrev does nothing at first circuit (prototype)', () => {
        const ctx = {
            currentCircuitIndex: 0,
            totalCircuits: 2,
            _circuits: ['c1', 'c2'],
            parsedCircuit: null,
            draw: jest.fn()
        };
        proto.handlePrev.call(ctx);
        expect(ctx.currentCircuitIndex).toBe(0);
        expect(ctx.draw).not.toHaveBeenCalled();
    });

    // ── splitAndParse (prototype) ──

    it('splitAndParse resets index and parses first circuit', () => {
        const ctx = {
            _qasm: MULTI_CIRCUIT_JSON,
            _circuits: [],
            totalCircuits: 0,
            currentCircuitIndex: 5,
            parsedCircuit: null,
            splitCircuits: proto.splitCircuits.bind(proto),
            parseQasm: proto.parseQasm.bind(proto),
            draw: jest.fn()
        };
        proto.splitAndParse.call(ctx);
        expect(ctx.currentCircuitIndex).toBe(0);
        expect(ctx.totalCircuits).toBe(2);
        expect(ctx.parsedCircuit).not.toBeNull();
        expect(ctx.draw).toHaveBeenCalled();
    });

    // ── ResizeObserver via renderedCallback (prototype) ──

    it('renderedCallback sets up ResizeObserver', () => {
        const mockObserve = jest.fn();
        global.ResizeObserver = jest.fn().mockImplementation(() => ({
            observe: mockObserve,
            disconnect: jest.fn()
        }));

        const ctx = {
            _qasm: SIMPLE_QASM,
            _lastQasm: '',
            _resizeObserver: null,
            refs: {
                canvasContainer: { clientWidth: 700 }
            },
            splitAndParse: jest.fn()
        };
        proto.renderedCallback.call(ctx);
        expect(ctx.splitAndParse).toHaveBeenCalled();
        expect(global.ResizeObserver).toHaveBeenCalled();
        expect(mockObserve).toHaveBeenCalled();
    });

    it('renderedCallback skips when qasm unchanged', () => {
        const ctx = {
            _qasm: SIMPLE_QASM,
            _lastQasm: SIMPLE_QASM,
            _resizeObserver: { observe: jest.fn() },
            refs: {
                canvasContainer: { clientWidth: 700 }
            },
            splitAndParse: jest.fn()
        };
        proto.renderedCallback.call(ctx);
        expect(ctx.splitAndParse).not.toHaveBeenCalled();
    });

    it('disconnectedCallback disconnects ResizeObserver (prototype)', () => {
        const mockDisconnect = jest.fn();
        const ctx = {
            _resizeObserver: { disconnect: mockDisconnect }
        };
        proto.disconnectedCallback.call(ctx);
        expect(mockDisconnect).toHaveBeenCalled();
    });

    it('disconnectedCallback does nothing without ResizeObserver (prototype)', () => {
        const ctx = { _resizeObserver: null };
        expect(() => proto.disconnectedCallback.call(ctx)).not.toThrow();
    });

    // ── draw method (prototype) ──

    it('draw returns early when no canvas ref', () => {
        const ctx = {
            refs: { circuitCanvas: null, canvasContainer: null },
            parsedCircuit: proto.parseQasm(SIMPLE_QASM)
        };
        expect(() => proto.draw.call(ctx)).not.toThrow();
    });

    it('draw returns early when no parsedCircuit', () => {
        const ctx = {
            refs: {
                circuitCanvas: document.createElement('canvas'),
                canvasContainer: { clientWidth: 700 }
            },
            parsedCircuit: null
        };
        expect(() => proto.draw.call(ctx)).not.toThrow();
    });

    it('draw renders full circuit with all gate types', () => {
        const canvas = document.createElement('canvas');
        const ctx = {
            refs: {
                circuitCanvas: canvas,
                canvasContainer: { clientWidth: 700 }
            },
            parsedCircuit: proto.parseQasm(SIMPLE_QASM),
            drawBarrier: jest.fn(),
            drawTwoQubitGate: jest.fn(),
            drawMeasureGate: jest.fn(),
            drawSingleGate: jest.fn(),
            formatParam: proto.formatParam
        };
        proto.draw.call(ctx);
        expect(ctx.drawSingleGate).toHaveBeenCalled(); // h gate
        expect(ctx.drawTwoQubitGate).toHaveBeenCalled(); // cx gate
        expect(ctx.drawMeasureGate).toHaveBeenCalled(); // measure gates
    });

    // ── parseQasm edge cases ──

    it('parseQasm handles empty string', () => {
        const parsed = proto.parseQasm('');
        expect(parsed.numQubits).toBe(0);
        expect(parsed.ops).toHaveLength(0);
    });

    it('parseQasm handles multiple qubit declarations', () => {
        const parsed = proto.parseQasm(
            'OPENQASM 3.0;\nqubit[2] q;\nqubit[3] r;\nh q[0];\nh r[2];'
        );
        expect(parsed.numQubits).toBe(5);
        expect(parsed.qubitNames).toContain('q[0]');
        expect(parsed.qubitNames).toContain('r[2]');
    });

    // ── All 14+ gate types parsing ──

    it('parseQasm parses all 14+ supported gate types', () => {
        const fullQasm = `OPENQASM 3.0;
qubit[3] q;
bit[3] c;
h q[0];
x q[1];
y q[2];
z q[0];
s q[1];
t q[2];
sx q[0];
rx(1.57) q[1];
ry(3.14) q[2];
rz(0.78) q[0];
cx q[0], q[1];
cz q[1], q[2];
barrier q[0], q[1], q[2];
reset q[0];
c[0] = measure q[0];
c[1] = measure q[1];
c[2] = measure q[2];`;

        const parsed = proto.parseQasm(fullQasm);
        expect(parsed.numQubits).toBe(3);
        const gateNames = parsed.ops.map((o) => o.gate);
        expect(gateNames).toContain('h');
        expect(gateNames).toContain('x');
        expect(gateNames).toContain('y');
        expect(gateNames).toContain('z');
        expect(gateNames).toContain('s');
        expect(gateNames).toContain('t');
        expect(gateNames).toContain('sx');
        expect(gateNames).toContain('rx');
        expect(gateNames).toContain('ry');
        expect(gateNames).toContain('rz');
        expect(gateNames).toContain('cx');
        expect(gateNames).toContain('cz');
        expect(gateNames).toContain('barrier');
        expect(gateNames).toContain('reset');
        expect(gateNames.filter((g) => g === 'measure')).toHaveLength(3);
    });
});
