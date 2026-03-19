/**
 * Generic OpenQASM 3.0 circuit diagram renderer.
 * Takes raw QASM source and renders a visual circuit diagram on Canvas.
 * Supports: h, x, y, z, s, t, cx, cz, rz, ry, rx, sx, measure, barrier, reset.
 * Reusable across any Salesforce app — no QuantumFair-specific logic.
 */
import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import CIRCUIT_QASM_FIELD from '@salesforce/schema/Quantum_Job__c.Circuit_QASM__c';

// Gate display configuration
const GATE_CONFIG = {
    h: { label: 'H', color: '#0176d3', bg: '#eaf5fe', width: 40 },
    x: { label: 'X', color: '#e3066a', bg: '#fde4ef', width: 40 },
    y: { label: 'Y', color: '#9050e9', bg: '#f3edff', width: 40 },
    z: { label: 'Z', color: '#2e844a', bg: '#e6f5ec', width: 40 },
    s: { label: 'S', color: '#0d9ddb', bg: '#e8f7ff', width: 40 },
    t: { label: 'T', color: '#0d9ddb', bg: '#e8f7ff', width: 40 },
    sx: { label: '√X', color: '#e3066a', bg: '#fde4ef', width: 44 },
    rx: { label: 'Rx', color: '#ff6d2e', bg: '#fff1ea', width: 48 },
    ry: { label: 'Ry', color: '#ff6d2e', bg: '#fff1ea', width: 48 },
    rz: { label: 'Rz', color: '#ff6d2e', bg: '#fff1ea', width: 48 },
    cx: {
        label: 'CX',
        color: '#0176d3',
        bg: '#eaf5fe',
        width: 40,
        twoQubit: true
    },
    cz: {
        label: 'CZ',
        color: '#0d9ddb',
        bg: '#e8f7ff',
        width: 40,
        twoQubit: true
    },
    measure: { label: 'M', color: '#ca8a04', bg: '#fefce8', width: 40 },
    barrier: { label: '|', color: '#706e6b', bg: 'transparent', width: 8 },
    reset: { label: '|0⟩', color: '#706e6b', bg: '#f3f3f3', width: 44 }
};

export default class QrngQasmViewer extends LightningElement {
    @api recordId; // When placed on a record page, auto-loads QASM from the record

    @track _qasm = '';
    @track parsedCircuit = null;
    @track currentCircuitIndex = 0;
    @track totalCircuits = 1;

    _resizeObserver;
    _lastQasm = '';
    _circuits = [];

    @api
    get qasm() {
        return this._qasm;
    }
    set qasm(value) {
        this._qasm = value;
    }

    // Wire record data when recordId is set (record page usage)
    @wire(getRecord, {
        recordId: '$recordId',
        fields: [CIRCUIT_QASM_FIELD]
    })
    wiredRecord({ data }) {
        if (data) {
            const qasmFromRecord = getFieldValue(data, CIRCUIT_QASM_FIELD);
            if (qasmFromRecord) {
                this._qasm = qasmFromRecord;
            }
        }
    }

    get hasMultipleCircuits() {
        return this.totalCircuits > 1;
    }

    get circuitLabel() {
        return `${this.currentCircuitIndex + 1} / ${this.totalCircuits}`;
    }

    get isPrevDisabled() {
        return this.currentCircuitIndex === 0;
    }

    get isNextDisabled() {
        return this.currentCircuitIndex >= this.totalCircuits - 1;
    }

    handlePrev() {
        if (this.currentCircuitIndex > 0) {
            this.currentCircuitIndex--;
            this.parsedCircuit = this.parseQasm(
                this._circuits[this.currentCircuitIndex]
            );
            this.draw();
        }
    }

    handleNext() {
        if (this.currentCircuitIndex < this.totalCircuits - 1) {
            this.currentCircuitIndex++;
            this.parsedCircuit = this.parseQasm(
                this._circuits[this.currentCircuitIndex]
            );
            this.draw();
        }
    }

    renderedCallback() {
        if (this._qasm && this._qasm !== this._lastQasm) {
            this._lastQasm = this._qasm;
            this.splitAndParse();
        }
        if (!this._resizeObserver) {
            const container = this.refs.canvasContainer;
            if (container) {
                this._resizeObserver = new ResizeObserver(() => this.draw());
                this._resizeObserver.observe(container);
            }
        }
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
        }
    }

    get hasQasm() {
        return !!this._qasm;
    }

    splitAndParse() {
        this._circuits = this.splitCircuits(this._qasm);
        this.totalCircuits = this._circuits.length;
        this.currentCircuitIndex = 0;
        this.parsedCircuit = this.parseQasm(this._circuits[0]);
        this.draw();
    }

    /**
     * Split multi-circuit QASM into individual circuits.
     * Supports: JSON array, legacy "--- CIRCUIT ---" separator, or plain single circuit.
     */
    splitCircuits(source) {
        const trimmed = source.trim();

        // JSON array format: ["OPENQASM...", "OPENQASM...", ...]
        if (trimmed.startsWith('[')) {
            try {
                const arr = JSON.parse(trimmed);
                if (Array.isArray(arr) && arr.length > 0) {
                    return arr;
                }
            } catch {
                // Not valid JSON, fall through
            }
        }

        // Legacy separator format
        if (trimmed.includes('--- CIRCUIT ---')) {
            return trimmed
                .split(/---\s*CIRCUIT\s*---/i)
                .map((c) => c.trim())
                .filter((c) => c.length > 0);
        }

        // Single circuit
        return [trimmed];
    }

    // ── QASM Parser ──────────────────────────────────────────

    parseQasm(source) {
        const lines = source.split('\n');
        const qubits = new Map(); // name -> 0-based index
        const ops = [];

        // First pass: collect all qubit references
        for (const raw of lines) {
            const line = raw.trim();

            // Declared qubits: qubit[N] name;
            const qubitDecl = line.match(/^qubit\[(\d+)\]\s+(\w+)\s*;/);
            if (qubitDecl) {
                const count = parseInt(qubitDecl[1], 10);
                const name = qubitDecl[2];
                for (let i = 0; i < count; i++) {
                    const key = `${name}[${i}]`;
                    if (!qubits.has(key)) {
                        qubits.set(key, qubits.size);
                    }
                }
                continue;
            }

            // Physical qubits: $N (ISA format, no declaration)
            const physMatches = line.matchAll(/\$(\d+)/g);
            for (const m of physMatches) {
                const key = `$${m[1]}`;
                if (!qubits.has(key)) {
                    qubits.set(key, qubits.size);
                }
            }
        }

        // Second pass: parse operations
        for (const raw of lines) {
            const line = raw.trim();
            if (
                !line ||
                line.startsWith('//') ||
                line.startsWith('OPENQASM') ||
                line.startsWith('include') ||
                line.startsWith('qubit') ||
                line.startsWith('bit')
            ) {
                continue;
            }

            if (line.startsWith('barrier')) {
                const targets = this.parseTargets(
                    line.replace(/^barrier\s*/, '').replace(';', ''),
                    qubits
                );
                ops.push({ gate: 'barrier', targets, params: [] });
                continue;
            }

            // Measure: result = measure target;
            const measMatch = line.match(/^(\S+)\s*=\s*measure\s+(\S+)\s*;/);
            if (measMatch) {
                const qubitIdx = qubits.get(measMatch[2]);
                if (qubitIdx != null) {
                    ops.push({
                        gate: 'measure',
                        targets: [qubitIdx],
                        params: [],
                        bitLabel: measMatch[1]
                    });
                }
                continue;
            }

            // Gate operations: gate(params) target1, target2;
            const gateMatch = line.match(/^(\w+)(?:\(([^)]*)\))?\s+([^;]+);/);
            if (gateMatch) {
                const gateName = gateMatch[1].toLowerCase();
                const paramStr = gateMatch[2] || '';
                const params = paramStr
                    ? paramStr.split(',').map((p) => p.trim())
                    : [];
                const targets = this.parseTargets(gateMatch[3], qubits);
                if (targets.length > 0 && GATE_CONFIG[gateName]) {
                    ops.push({ gate: gateName, targets, params });
                }
            }
        }

        // Build qubit names sorted by index
        const qubitNames = new Array(qubits.size);
        for (const [name, idx] of qubits) {
            qubitNames[idx] = name;
        }

        return {
            numQubits: qubits.size,
            qubitNames,
            ops
        };
    }

    parseTargets(targetStr, qubitMap) {
        return targetStr
            .split(',')
            .map((t) => t.trim())
            .map((t) => qubitMap.get(t))
            .filter((idx) => idx != null);
    }

    // ── Canvas Renderer ──────────────────────────────────────

    draw() {
        const canvas = this.refs.circuitCanvas;
        if (!canvas || !this.parsedCircuit) return;

        const container = this.refs.canvasContainer;
        const width = container.clientWidth || 700;
        const circuit = this.parsedCircuit;
        const numQubits = circuit.numQubits || 1;

        const ROW_H = 50;
        const PAD_TOP = 20;
        const PAD_BOTTOM = 20;
        const START_X = 80;
        const GAP = 14;
        const height = PAD_TOP + numQubits * ROW_H + PAD_BOTTOM;

        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        ctx.clearRect(0, 0, width, height);

        // Assign columns: each op gets a column. Track max column per qubit.
        const qubitCol = new Array(numQubits).fill(0);
        const opCols = [];

        for (const op of circuit.ops) {
            const maxTarget = Math.max(...op.targets);
            const minTarget = Math.min(...op.targets);
            let col = 0;
            for (let q = minTarget; q <= maxTarget; q++) {
                col = Math.max(col, qubitCol[q]);
            }
            opCols.push(col);
            const gw = GATE_CONFIG[op.gate]?.width || 40;
            for (let q = minTarget; q <= maxTarget; q++) {
                qubitCol[q] = col + gw + GAP;
            }
        }

        const maxCol = Math.max(...qubitCol, START_X + 100);
        const endX = Math.min(maxCol + START_X + 40, width - 20);

        // Draw qubit wires and labels
        for (let q = 0; q < numQubits; q++) {
            const y = PAD_TOP + q * ROW_H + ROW_H / 2;
            const label = circuit.qubitNames[q] || `q[${q}]`;

            ctx.font = '13px monospace';
            ctx.fillStyle = '#181818';
            ctx.textAlign = 'right';
            ctx.textBaseline = 'middle';
            ctx.fillText(label, START_X - 10, y);

            ctx.beginPath();
            ctx.strokeStyle = '#706e6b';
            ctx.lineWidth = 1;
            ctx.moveTo(START_X, y);
            ctx.lineTo(endX, y);
            ctx.stroke();
        }

        // Draw operations
        for (let i = 0; i < circuit.ops.length; i++) {
            const op = circuit.ops[i];
            const cfg = GATE_CONFIG[op.gate];
            if (!cfg) continue;

            const x = START_X + GAP + opCols[i] + cfg.width / 2;

            if (op.gate === 'barrier') {
                this.drawBarrier(ctx, x, PAD_TOP, numQubits, ROW_H);
            } else if (cfg.twoQubit && op.targets.length >= 2) {
                const y1 = PAD_TOP + op.targets[0] * ROW_H + ROW_H / 2;
                const y2 = PAD_TOP + op.targets[1] * ROW_H + ROW_H / 2;
                this.drawTwoQubitGate(ctx, x, y1, y2, cfg);
            } else if (op.gate === 'measure') {
                const y = PAD_TOP + op.targets[0] * ROW_H + ROW_H / 2;
                this.drawMeasureGate(ctx, x, y, cfg);
            } else {
                const y = PAD_TOP + op.targets[0] * ROW_H + ROW_H / 2;
                const paramLabel =
                    op.params.length > 0
                        ? this.formatParam(op.params[0])
                        : null;
                this.drawSingleGate(ctx, x, y, cfg, paramLabel);
            }
        }
    }

    drawSingleGate(ctx, x, y, cfg, paramLabel) {
        const half = cfg.width / 2;
        const h = 36;

        ctx.fillStyle = cfg.bg;
        ctx.strokeStyle = cfg.color;
        ctx.lineWidth = 2;
        ctx.fillRect(x - half, y - h / 2, cfg.width, h);
        ctx.strokeRect(x - half, y - h / 2, cfg.width, h);

        ctx.fillStyle = cfg.color;
        ctx.font = 'bold 14px monospace';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(cfg.label, x, y);

        if (paramLabel) {
            ctx.font = '9px monospace';
            ctx.fillStyle = cfg.color;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'top';
            ctx.fillText(paramLabel, x, y + h / 2 + 1);
        }
    }

    drawTwoQubitGate(ctx, x, y1, y2, cfg) {
        // Vertical connecting line
        ctx.beginPath();
        ctx.strokeStyle = cfg.color;
        ctx.lineWidth = 2;
        ctx.moveTo(x, y1);
        ctx.lineTo(x, y2);
        ctx.stroke();

        // Control dot on first qubit
        ctx.beginPath();
        ctx.arc(x, y1, 6, 0, 2 * Math.PI);
        ctx.fillStyle = cfg.color;
        ctx.fill();

        if (cfg.label === 'CX') {
            // Target circle with + on second qubit
            ctx.beginPath();
            ctx.arc(x, y2, 10, 0, 2 * Math.PI);
            ctx.strokeStyle = cfg.color;
            ctx.lineWidth = 2;
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(x - 7, y2);
            ctx.lineTo(x + 7, y2);
            ctx.moveTo(x, y2 - 7);
            ctx.lineTo(x, y2 + 7);
            ctx.stroke();
        } else {
            // CZ: both dots
            ctx.beginPath();
            ctx.arc(x, y2, 6, 0, 2 * Math.PI);
            ctx.fillStyle = cfg.color;
            ctx.fill();

            // Label between
            const mid = (y1 + y2) / 2;
            ctx.font = 'bold 10px monospace';
            ctx.fillStyle = cfg.color;
            ctx.textAlign = 'left';
            ctx.textBaseline = 'middle';
            ctx.fillText(cfg.label, x + 9, mid);
        }
    }

    drawMeasureGate(ctx, x, y, cfg) {
        const half = cfg.width / 2;
        const h = 36;

        ctx.fillStyle = cfg.bg;
        ctx.strokeStyle = cfg.color;
        ctx.lineWidth = 2;
        ctx.fillRect(x - half, y - h / 2, cfg.width, h);
        ctx.strokeRect(x - half, y - h / 2, cfg.width, h);

        // Meter arc
        ctx.beginPath();
        ctx.arc(x, y + 4, half * 0.45, Math.PI, 0);
        ctx.strokeStyle = cfg.color;
        ctx.lineWidth = 1.5;
        ctx.stroke();

        // Needle
        ctx.beginPath();
        ctx.moveTo(x, y + 4);
        ctx.lineTo(x + half * 0.35, y - h * 0.2);
        ctx.stroke();

        // M label
        ctx.fillStyle = cfg.color;
        ctx.font = 'bold 9px monospace';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'bottom';
        ctx.fillText('M', x, y - h / 2 + 12);
    }

    drawBarrier(ctx, x, padTop, numQubits, rowH) {
        ctx.save();
        ctx.setLineDash([4, 4]);
        ctx.strokeStyle = '#706e6b';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(x, padTop + rowH / 2 - 10);
        ctx.lineTo(x, padTop + (numQubits - 1) * rowH + rowH / 2 + 10);
        ctx.stroke();
        ctx.restore();
    }

    formatParam(param) {
        // Simplify common angle expressions
        const p = param.trim();
        if (p.includes('pi') || p.includes('π')) {
            return p
                .replace(/pi/g, 'π')
                .replace(/\*\s*/g, '')
                .replace(/\s*\/\s*/g, '/');
        }
        const num = parseFloat(p);
        if (!isNaN(num)) {
            return num.toFixed(2);
        }
        return p;
    }
}
