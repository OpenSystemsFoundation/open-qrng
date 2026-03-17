import { LightningElement, api } from 'lwc';

export default class QrngResultsVisualizer extends LightningElement {
    @api rawResults = '';
    @api numQubits = 8;

    _resizeObserver;
    _distribution = {};
    _totalSamples = 0;
    _lastComputedInput = '';

    get hasData() {
        return this.rawResults && this.rawResults.length > 0;
    }

    get totalSamples() {
        return this._totalSamples;
    }

    get uniqueCount() {
        return Object.keys(this._distribution).length;
    }

    renderedCallback() {
        if (this.hasData) {
            this.computeDistribution();
            this.drawChart();
        }
        if (!this._resizeObserver) {
            const container = this.refs.chartContainer;
            if (container) {
                this._resizeObserver = new ResizeObserver(() => {
                    if (this.hasData) this.drawChart();
                });
                this._resizeObserver.observe(container);
            }
        }
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
        }
    }

    computeDistribution() {
        const bits = this.rawResults;
        const n = parseInt(this.numQubits, 10) || 8;
        const inputKey = `${bits}|${n}`;
        if (inputKey === this._lastComputedInput) return;
        this._lastComputedInput = inputKey;

        this._distribution = {};
        this._totalSamples = 0;

        // Split raw results into chunks of numQubits
        for (let i = 0; i + n <= bits.length; i += n) {
            const sample = bits.substring(i, i + n);
            this._distribution[sample] = (this._distribution[sample] || 0) + 1;
            this._totalSamples++;
        }
    }

    drawChart() {
        const canvas = this.refs.chartCanvas;
        if (!canvas) return;

        const container = this.refs.chartContainer;
        const width = container.clientWidth || 600;
        const qubits = parseInt(this.numQubits, 10) || 8;
        const height = Math.max(300, 200 + qubits * 6);
        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, width, height);

        const entries = Object.entries(this._distribution).sort((a, b) =>
            a[0].localeCompare(b[0])
        );
        if (entries.length === 0) return;

        const maxCount = Math.max(...entries.map((e) => e[1]));
        const idealCount =
            this._totalSamples / Math.pow(2, parseInt(this.numQubits, 10) || 8);

        // Chart dimensions — adjust bottom margin for rotated labels
        const n = parseInt(this.numQubits, 10) || 8;
        const marginLeft = 50;
        const marginBottom = Math.max(60, n * 6 + 30);
        const marginTop = 20;
        const marginRight = 20;
        const chartWidth = width - marginLeft - marginRight;
        const chartHeight = height - marginTop - marginBottom;

        // Limit display to top 32 entries if too many
        const displayEntries =
            entries.length > 32 ? entries.slice(0, 32) : entries;
        const totalBarSpace = chartWidth / displayEntries.length;
        const barGap = Math.max(1, Math.min(4, totalBarSpace * 0.15));
        const barWidth = Math.max(2, totalBarSpace - barGap);

        // Draw bars with labels and counts
        displayEntries.forEach(([label, count], i) => {
            const barHeight = Math.max(1, (count / maxCount) * chartHeight);
            const x = marginLeft + i * totalBarSpace;
            const y = marginTop + chartHeight - barHeight;

            // Color based on deviation from ideal
            const ratio = count / idealCount;
            if (ratio > 1.5 || ratio < 0.5) {
                ctx.fillStyle = '#ea001e'; // red - outlier
            } else if (ratio > 1.25 || ratio < 0.75) {
                ctx.fillStyle = '#fe9339'; // amber - marginal
            } else {
                ctx.fillStyle = '#2e844a'; // green - within variance
            }

            ctx.fillRect(x, y, barWidth, barHeight);

            // Count value on top of bar
            ctx.font = '10px monospace';
            ctx.fillStyle = '#181818';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'bottom';
            ctx.fillText(count.toString(), x + barWidth / 2, y - 2);

            // Bitstring label below x-axis (always shown, rotated 45°)
            ctx.save();
            ctx.translate(x + barWidth / 2, marginTop + chartHeight + 4);
            ctx.rotate(Math.PI / 4);
            ctx.font = '9px monospace';
            ctx.fillStyle = '#706e6b';
            ctx.textAlign = 'left';
            ctx.textBaseline = 'top';
            ctx.fillText(label, 0, 0);
            ctx.restore();
        });

        // Ideal line (dashed)
        if (idealCount > 0 && idealCount <= maxCount) {
            const idealY =
                marginTop + chartHeight - (idealCount / maxCount) * chartHeight;
            ctx.beginPath();
            ctx.setLineDash([5, 5]);
            ctx.strokeStyle = '#0176d3';
            ctx.lineWidth = 1.5;
            ctx.moveTo(marginLeft, idealY);
            ctx.lineTo(width - marginRight, idealY);
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.font = '11px sans-serif';
            ctx.fillStyle = '#0176d3';
            ctx.textAlign = 'right';
            ctx.fillText('ideal', marginLeft - 5, idealY + 4);
        }

        // Y-axis
        ctx.beginPath();
        ctx.strokeStyle = '#c9c7c5';
        ctx.lineWidth = 1;
        ctx.moveTo(marginLeft, marginTop);
        ctx.lineTo(marginLeft, marginTop + chartHeight);
        ctx.stroke();

        // Y-axis labels
        ctx.font = '11px sans-serif';
        ctx.fillStyle = '#706e6b';
        ctx.textAlign = 'right';
        ctx.fillText(maxCount.toString(), marginLeft - 5, marginTop + 10);
        ctx.fillText('0', marginLeft - 5, marginTop + chartHeight);

        // X-axis
        ctx.beginPath();
        ctx.moveTo(marginLeft, marginTop + chartHeight);
        ctx.lineTo(width - marginRight, marginTop + chartHeight);
        ctx.stroke();

        // Legend
        const legendY = height - 10;
        ctx.font = '10px sans-serif';
        ctx.textAlign = 'left';

        ctx.fillStyle = '#2e844a';
        ctx.fillRect(marginLeft, legendY - 8, 10, 10);
        ctx.fillStyle = '#706e6b';
        ctx.fillText('Expected', marginLeft + 14, legendY);

        ctx.fillStyle = '#fe9339';
        ctx.fillRect(marginLeft + 80, legendY - 8, 10, 10);
        ctx.fillStyle = '#706e6b';
        ctx.fillText('Marginal', marginLeft + 94, legendY);

        ctx.fillStyle = '#ea001e';
        ctx.fillRect(marginLeft + 160, legendY - 8, 10, 10);
        ctx.fillStyle = '#706e6b';
        ctx.fillText('Outlier', marginLeft + 174, legendY);
    }
}
