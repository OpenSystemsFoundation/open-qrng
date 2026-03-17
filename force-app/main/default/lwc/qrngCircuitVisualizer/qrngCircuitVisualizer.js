import { LightningElement, api } from 'lwc';

// CHSH basis configurations matching QRNGCircuitBuilder.buildBellCircuitFromPairs
const CHSH_CONFIGS = [
    { label: 'S₀', alice: '0', bob: 'π/8', aliceLabel: '', bobLabel: 'π/8' },
    {
        label: 'S₁',
        alice: '0',
        bob: '3π/8',
        aliceLabel: '',
        bobLabel: '3π/8'
    },
    {
        label: 'S₂',
        alice: 'π/4',
        bob: 'π/8',
        aliceLabel: 'π/4',
        bobLabel: 'π/8'
    },
    {
        label: 'S₃',
        alice: 'π/4',
        bob: '3π/8',
        aliceLabel: 'π/4',
        bobLabel: '3π/8'
    }
];

// Colors for each CHSH basis config
const BASIS_COLORS = ['#0176d3', '#9050e9', '#e3066a', '#ff6d2e'];
const BASIS_BG = ['#eaf5fe', '#f3edff', '#fde4ef', '#fff1ea'];

export default class QrngCircuitVisualizer extends LightningElement {
    @api numQubits = 4;
    @api useBellTest = false;

    _resizeObserver;

    renderedCallback() {
        this.drawCircuit();
        if (!this._resizeObserver) {
            const container = this.refs.canvasContainer;
            if (container) {
                this._resizeObserver = new ResizeObserver(() =>
                    this.drawCircuit()
                );
                this._resizeObserver.observe(container);
            }
        }
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
        }
    }

    drawCircuit() {
        const canvas = this.refs.circuitCanvas;
        if (!canvas) return;

        const container = this.refs.canvasContainer;
        const width = container.clientWidth || 600;
        const qubits = parseInt(this.numQubits, 10) || 4;

        if (this.useBellTest) {
            this.drawBellCircuit(canvas, width, qubits);
        } else {
            this.drawStandardCircuit(canvas, width, qubits);
        }
    }

    drawStandardCircuit(canvas, width, qubits) {
        const rowHeight = 50;
        const height = Math.max(qubits * rowHeight + 40, 100);
        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, width, height);

        const wireColor = '#706e6b';
        const gateColor = '#0176d3';
        const gateBg = '#eaf5fe';
        const measureColor = '#ca8a04';
        const measureBg = '#fefce8';
        const textColor = '#181818';
        const startX = 80;
        const gateWidth = 40;
        const gateSpacing = 20;
        const endX = width - 40;

        for (let i = 0; i < qubits; i++) {
            const y = 20 + i * rowHeight + rowHeight / 2;

            // Qubit label
            ctx.font = '13px monospace';
            ctx.fillStyle = textColor;
            ctx.textAlign = 'right';
            ctx.textBaseline = 'middle';
            ctx.fillText(`q[${i}]`, startX - 10, y);

            // Wire
            ctx.beginPath();
            ctx.strokeStyle = wireColor;
            ctx.lineWidth = 1;
            ctx.moveTo(startX, y);
            ctx.lineTo(endX, y);
            ctx.stroke();

            // H gate
            this.drawGate(
                ctx,
                startX + gateSpacing,
                y,
                gateWidth,
                'H',
                gateBg,
                gateColor
            );
            // Measure
            const measX = startX + gateSpacing + gateWidth + gateSpacing;
            this.drawMeasure(ctx, measX, y, gateWidth, measureBg, measureColor);
            // Bit label
            ctx.font = '11px monospace';
            ctx.fillStyle = wireColor;
            ctx.textAlign = 'left';
            ctx.fillText(`bit[${i}]`, measX + gateWidth + 10, y);
        }
    }

    drawBellCircuit(canvas, width, qubits) {
        const numPairs = Math.floor(qubits / 2);
        const rowHeight = 50;
        const pairSpacing = 16;
        const legendHeight = 60;
        const topPad = 20;
        const height = Math.max(
            numPairs * (rowHeight * 2 + pairSpacing) + topPad + legendHeight,
            150
        );
        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, width, height);

        const wireColor = '#706e6b';
        const measureColor = '#ca8a04';
        const measureBg = '#fefce8';
        const textColor = '#181818';
        const startX = 80;
        const gateWidth = 40;
        const rotGateWidth = 48;
        const gateSpacing = 16;
        const endX = width - 40;

        for (let p = 0; p < numPairs; p++) {
            const config = p % 4;
            const chsh = CHSH_CONFIGS[config];
            const basisColor = BASIS_COLORS[config];
            const basisBg = BASIS_BG[config];
            const yBase =
                topPad + p * (rowHeight * 2 + pairSpacing) + rowHeight / 2;
            const yA = yBase;
            const yB = yBase + rowHeight;
            const qA = p * 2;
            const qB = p * 2 + 1;

            // Pair bracket + basis label
            this.drawPairBracket(ctx, startX - 65, yA, yB, chsh, basisColor);

            // Qubit labels
            ctx.font = '13px monospace';
            ctx.fillStyle = textColor;
            ctx.textAlign = 'right';
            ctx.textBaseline = 'middle';
            ctx.fillText(`q[${qA}]`, startX - 10, yA);
            ctx.fillText(`q[${qB}]`, startX - 10, yB);

            // Wires
            ctx.beginPath();
            ctx.strokeStyle = wireColor;
            ctx.lineWidth = 1;
            ctx.moveTo(startX, yA);
            ctx.lineTo(endX, yA);
            ctx.moveTo(startX, yB);
            ctx.lineTo(endX, yB);
            ctx.stroke();

            // 1) H gate on Alice
            let curX = startX + gateSpacing;
            this.drawGate(ctx, curX, yA, gateWidth, 'H', '#eaf5fe', '#0176d3');

            // 2) CZ gate (symmetric — two filled dots connected)
            curX += gateWidth + gateSpacing;
            this.drawCZGate(ctx, curX, yA, yB, gateWidth, '#0d9ddb');

            // 3) Alice basis rotation (only when angle ≠ 0)
            curX += gateWidth + gateSpacing;
            if (chsh.aliceLabel) {
                this.drawGate(
                    ctx,
                    curX,
                    yA,
                    rotGateWidth,
                    `Ry`,
                    basisBg,
                    basisColor
                );
                // Angle subscript
                ctx.font = '10px monospace';
                ctx.fillStyle = basisColor;
                ctx.textAlign = 'center';
                ctx.textBaseline = 'top';
                ctx.fillText(chsh.aliceLabel, curX, yA + rotGateWidth / 2 + 2);
            } else {
                // Show identity (no rotation) as dashed gap
                this.drawIdentity(ctx, curX, yA, rotGateWidth, wireColor);
            }

            // 4) Bob basis rotation (always present)
            this.drawGate(
                ctx,
                curX,
                yB,
                rotGateWidth,
                `Ry`,
                basisBg,
                basisColor
            );
            ctx.font = '10px monospace';
            ctx.fillStyle = basisColor;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'top';
            ctx.fillText(chsh.bobLabel, curX, yB + rotGateWidth / 2 + 2);

            // 5) Measurement gates
            const measX = curX + rotGateWidth / 2 + gateSpacing + gateWidth / 2;
            this.drawMeasure(
                ctx,
                measX,
                yA,
                gateWidth,
                measureBg,
                measureColor
            );
            this.drawMeasure(
                ctx,
                measX,
                yB,
                gateWidth,
                measureBg,
                measureColor
            );

            // Bit labels
            ctx.font = '11px monospace';
            ctx.fillStyle = wireColor;
            ctx.textAlign = 'left';
            ctx.fillText(`bit[${qA}]`, measX + gateWidth / 2 + 8, yA);
            ctx.fillText(`bit[${qB}]`, measX + gateWidth / 2 + 8, yB);
        }

        // Draw CHSH legend at bottom
        this.drawCHSHLegend(ctx, startX, height - legendHeight + 8, width);
    }

    drawPairBracket(ctx, x, y1, y2, config, color) {
        const mid = (y1 + y2) / 2;

        // Bracket line
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.moveTo(x + 12, y1 - 4);
        ctx.lineTo(x + 6, y1 - 4);
        ctx.lineTo(x + 6, y2 + 4);
        ctx.lineTo(x + 12, y2 + 4);
        ctx.stroke();

        // Basis label
        ctx.font = 'bold 11px sans-serif';
        ctx.fillStyle = color;
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        ctx.fillText(config.label, x + 2, mid);
    }

    drawCZGate(ctx, x, y1, y2, size, color) {
        // Vertical line connecting the two qubits
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.moveTo(x, y1);
        ctx.lineTo(x, y2);
        ctx.stroke();

        // Both qubits get filled dots (CZ is symmetric)
        const dotRadius = 6;
        ctx.beginPath();
        ctx.arc(x, y1, dotRadius, 0, 2 * Math.PI);
        ctx.fillStyle = color;
        ctx.fill();
        ctx.beginPath();
        ctx.arc(x, y2, dotRadius, 0, 2 * Math.PI);
        ctx.fillStyle = color;
        ctx.fill();

        // "CZ" label centered between the dots
        const mid = (y1 + y2) / 2;
        ctx.font = 'bold 10px monospace';
        ctx.fillStyle = color;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';
        ctx.fillText('CZ', x + dotRadius + 3, mid);
    }

    drawIdentity(ctx, x, y, gateWidth, color) {
        // Dashed line segment to indicate "no rotation" (identity)
        const half = gateWidth / 2;
        ctx.save();
        ctx.setLineDash([4, 4]);
        ctx.strokeStyle = color;
        ctx.lineWidth = 1;
        ctx.globalAlpha = 0.4;
        ctx.strokeRect(x - half, y - 16, gateWidth, 32);
        ctx.restore();

        ctx.font = '10px monospace';
        ctx.fillStyle = color;
        ctx.globalAlpha = 0.5;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText('I', x, y);
        ctx.globalAlpha = 1.0;
    }

    drawCHSHLegend(ctx, x, y, width) {
        // Divider line
        ctx.beginPath();
        ctx.strokeStyle = '#e5e5e5';
        ctx.lineWidth = 1;
        ctx.moveTo(x, y - 4);
        ctx.lineTo(width - 40, y - 4);
        ctx.stroke();

        ctx.font = 'bold 11px sans-serif';
        ctx.fillStyle = '#181818';
        ctx.textAlign = 'left';
        ctx.textBaseline = 'top';
        ctx.fillText('CHSH Basis Settings:', x, y);

        const entryWidth = Math.min(140, (width - x - 40) / 4);
        for (let i = 0; i < 4; i++) {
            const ex = x + i * entryWidth;
            const ey = y + 18;
            const cfg = CHSH_CONFIGS[i];

            // Color swatch
            ctx.fillStyle = BASIS_COLORS[i];
            ctx.fillRect(ex, ey, 10, 10);

            // Label
            ctx.font = '10px monospace';
            ctx.fillStyle = '#181818';
            ctx.textAlign = 'left';
            ctx.textBaseline = 'top';
            const aStr = cfg.aliceLabel || '0';
            ctx.fillText(
                `${cfg.label} a=${aStr} b=${cfg.bobLabel}`,
                ex + 14,
                ey
            );
        }

        // S > 2 annotation
        ctx.font = '10px sans-serif';
        ctx.fillStyle = '#706e6b';
        ctx.textAlign = 'left';
        ctx.fillText(
            'S = |E(a,b) + E(a,b\u2032) + E(a\u2032,b) \u2212 E(a\u2032,b\u2032)| > 2 proves quantum origin',
            x,
            y + 36
        );
    }

    drawGate(ctx, x, y, size, label, bgColor, borderColor) {
        const half = size / 2;
        ctx.fillStyle = bgColor;
        ctx.strokeStyle = borderColor;
        ctx.lineWidth = 2;
        ctx.fillRect(x - half, y - half, size, size);
        ctx.strokeRect(x - half, y - half, size, size);
        ctx.fillStyle = borderColor;
        ctx.font = 'bold 14px monospace';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(label, x, y);
    }

    drawMeasure(ctx, x, y, size, bgColor, borderColor) {
        const half = size / 2;
        ctx.fillStyle = bgColor;
        ctx.strokeStyle = borderColor;
        ctx.lineWidth = 2;
        ctx.fillRect(x - half, y - half, size, size);
        ctx.strokeRect(x - half, y - half, size, size);
        // Meter arc
        ctx.beginPath();
        ctx.arc(x, y + 4, half * 0.5, Math.PI, 0);
        ctx.strokeStyle = borderColor;
        ctx.lineWidth = 1.5;
        ctx.stroke();
        // Needle
        ctx.beginPath();
        ctx.moveTo(x, y + 4);
        ctx.lineTo(x + half * 0.4, y - half * 0.3);
        ctx.strokeStyle = borderColor;
        ctx.lineWidth = 1.5;
        ctx.stroke();
        // M label
        ctx.fillStyle = borderColor;
        ctx.font = 'bold 10px monospace';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'bottom';
        ctx.fillText('M', x, y - half + 12);
    }
}
