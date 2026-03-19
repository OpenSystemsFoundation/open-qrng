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
        document.body.removeChild(element);
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
});
