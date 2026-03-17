import { LightningElement, api } from 'lwc';

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
        const rowHeight = 50;
        const height = Math.max(qubits * rowHeight + 40, 100);

        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, width, height);

        // Colors
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

            if (this.useBellTest && i % 2 === 0 && i + 1 < qubits) {
                // Bell test circuit: H on first qubit of pair
                this.drawGate(
                    ctx,
                    startX + gateSpacing,
                    y,
                    gateWidth,
                    'H',
                    gateBg,
                    gateColor
                );
                // CNOT gate (Qiskit notation: dot on control, ⊕ on target)
                const y2 = 20 + (i + 1) * rowHeight + rowHeight / 2;
                const cxX = startX + gateSpacing + gateWidth + gateSpacing;
                this.drawCNOTGate(ctx, cxX, y, y2, gateWidth, gateColor);
                // Measure both
                const measX = cxX + gateWidth + gateSpacing;
                this.drawMeasure(
                    ctx,
                    measX,
                    y,
                    gateWidth,
                    measureBg,
                    measureColor
                );
                // Bit label
                ctx.font = '11px monospace';
                ctx.fillStyle = wireColor;
                ctx.textAlign = 'left';
                ctx.fillText(`bit[${i}]`, measX + gateWidth + 10, y);
            } else if (this.useBellTest && i % 2 === 1) {
                // Second qubit of Bell pair - measure gate
                const cxX = startX + gateSpacing + gateWidth + gateSpacing;
                const measX = cxX + gateWidth + gateSpacing;
                this.drawMeasure(
                    ctx,
                    measX,
                    y,
                    gateWidth,
                    measureBg,
                    measureColor
                );
                ctx.font = '11px monospace';
                ctx.fillStyle = wireColor;
                ctx.textAlign = 'left';
                ctx.fillText(`bit[${i}]`, measX + gateWidth + 10, y);
            } else if (!this.useBellTest) {
                // Standard circuit: H + Measure
                this.drawGate(
                    ctx,
                    startX + gateSpacing,
                    y,
                    gateWidth,
                    'H',
                    gateBg,
                    gateColor
                );
                const measX = startX + gateSpacing + gateWidth + gateSpacing;
                this.drawMeasure(
                    ctx,
                    measX,
                    y,
                    gateWidth,
                    measureBg,
                    measureColor
                );
                // Bit label
                ctx.font = '11px monospace';
                ctx.fillStyle = wireColor;
                ctx.textAlign = 'left';
                ctx.fillText(`bit[${i}]`, measX + gateWidth + 10, y);
            }
        }
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

    drawCNOTGate(ctx, x, y1, y2, size, color) {
        // Vertical line connecting control to target
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.moveTo(x, y1);
        ctx.lineTo(x, y2);
        ctx.stroke();

        // Control qubit: filled dot
        const dotRadius = 5;
        ctx.beginPath();
        ctx.arc(x, y1, dotRadius, 0, 2 * Math.PI);
        ctx.fillStyle = color;
        ctx.fill();

        // Target qubit: ⊕ (circle with plus)
        const targetRadius = size * 0.35;
        ctx.beginPath();
        ctx.arc(x, y2, targetRadius, 0, 2 * Math.PI);
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.stroke();
        // Horizontal line of plus
        ctx.beginPath();
        ctx.moveTo(x - targetRadius, y2);
        ctx.lineTo(x + targetRadius, y2);
        ctx.stroke();
        // Vertical line of plus
        ctx.beginPath();
        ctx.moveTo(x, y2 - targetRadius);
        ctx.lineTo(x, y2 + targetRadius);
        ctx.stroke();
    }
}
