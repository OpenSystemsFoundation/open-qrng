import { LightningElement, api } from 'lwc';

const MIN_BAR_WIDTH = 14;
const BAR_GAP = 2;

export default class QrngResultsVisualizer extends LightningElement {
    @api rawResults = '';
    @api debiasedResults = '';
    @api numQubits = 8;

    _resizeObserver;
    _distribution = {};
    _debiasedDistribution = {};
    _totalSamples = 0;
    _debiasedTotalSamples = 0;
    _lastComputedInput = '';
    _lastDebiasedInput = '';

    get hasData() {
        return this.rawResults && this.rawResults.length > 0;
    }

    get hasDebiasedData() {
        return this.debiasedResults && this.debiasedResults.length > 0;
    }

    get totalSamples() {
        return this._totalSamples;
    }

    get debiasedTotalSamples() {
        return this._debiasedTotalSamples;
    }

    get uniqueCount() {
        return Object.keys(this._distribution).length;
    }

    get debiasedUniqueCount() {
        return Object.keys(this._debiasedDistribution).length;
    }

    get possibleCount() {
        const n = parseInt(this.numQubits, 10) || 8;
        return Math.pow(2, n);
    }

    renderedCallback() {
        if (this.hasData) {
            this._computeDistribution(
                this.rawResults,
                '_distribution',
                '_totalSamples',
                '_lastComputedInput'
            );
            this._drawChart(
                this.refs.chartCanvas,
                this.refs.chartContainer,
                this._distribution,
                this._totalSamples
            );
        }
        if (this.hasDebiasedData) {
            this._computeDistribution(
                this.debiasedResults,
                '_debiasedDistribution',
                '_debiasedTotalSamples',
                '_lastDebiasedInput'
            );
            this._drawChart(
                this.refs.debiasedCanvas,
                this.refs.debiasedContainer,
                this._debiasedDistribution,
                this._debiasedTotalSamples
            );
        }
        if (!this._resizeObserver) {
            const container = this.refs.chartContainer;
            if (container) {
                this._resizeObserver = new ResizeObserver(() => {
                    if (this.hasData) {
                        this._drawChart(
                            this.refs.chartCanvas,
                            this.refs.chartContainer,
                            this._distribution,
                            this._totalSamples
                        );
                    }
                    if (this.hasDebiasedData) {
                        this._drawChart(
                            this.refs.debiasedCanvas,
                            this.refs.debiasedContainer,
                            this._debiasedDistribution,
                            this._debiasedTotalSamples
                        );
                    }
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

    _computeDistribution(bits, distProp, totalProp, cacheProp) {
        const n = parseInt(this.numQubits, 10) || 8;
        const inputKey = `${bits}|${n}`;
        if (inputKey === this[cacheProp]) return;
        this[cacheProp] = inputKey;

        const dist = {};
        let total = 0;

        for (let i = 0; i + n <= bits.length; i += n) {
            const sample = bits.substring(i, i + n);
            dist[sample] = (dist[sample] || 0) + 1;
            total++;
        }

        this[distProp] = dist;
        this[totalProp] = total;
    }

    _drawChart(canvas, container, distribution, totalSamples) {
        if (!canvas || !container) return;

        const qubits = parseInt(this.numQubits, 10) || 8;
        const entries = Object.entries(distribution).sort((a, b) =>
            a[0].localeCompare(b[0])
        );
        if (entries.length === 0) return;

        const containerWidth = container.clientWidth || 600;
        const marginLeft = 50;
        const marginRight = 20;
        const marginTop = 20;
        const marginBottom = Math.max(60, qubits * 6 + 30);

        // Calculate width: ensure every bar gets at least MIN_BAR_WIDTH
        const totalBarSpace = MIN_BAR_WIDTH + BAR_GAP;
        const neededChartWidth = entries.length * totalBarSpace;
        const width = Math.max(
            containerWidth,
            neededChartWidth + marginLeft + marginRight
        );
        const height = Math.max(300, 200 + qubits * 6);

        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, width, height);

        const chartWidth = width - marginLeft - marginRight;
        const chartHeight = height - marginTop - marginBottom;

        const actualBarSpace = chartWidth / entries.length;
        const barWidth = Math.max(2, actualBarSpace - BAR_GAP);

        const maxCount = Math.max(...entries.map((e) => e[1]));
        const idealCount = totalSamples / Math.pow(2, qubits);

        // Draw bars
        entries.forEach(([label, count], i) => {
            const barHeight = Math.max(1, (count / maxCount) * chartHeight);
            const x = marginLeft + i * actualBarSpace;
            const y = marginTop + chartHeight - barHeight;

            // Color based on deviation from ideal
            const ratio = idealCount > 0 ? count / idealCount : 1;
            if (ratio > 1.5 || ratio < 0.5) {
                ctx.fillStyle = '#ea001e';
            } else if (ratio > 1.25 || ratio < 0.75) {
                ctx.fillStyle = '#fe9339';
            } else {
                ctx.fillStyle = '#2e844a';
            }

            ctx.fillRect(x, y, barWidth, barHeight);

            // Count value on top of bar
            if (actualBarSpace > 14) {
                ctx.font = '10px monospace';
                ctx.fillStyle = '#181818';
                ctx.textAlign = 'center';
                ctx.textBaseline = 'bottom';
                ctx.fillText(count.toString(), x + barWidth / 2, y - 2);
            }

            // Bitstring label below x-axis
            if (actualBarSpace > 8) {
                ctx.save();
                ctx.translate(x + barWidth / 2, marginTop + chartHeight + 4);
                ctx.rotate(Math.PI / 4);
                ctx.font = '9px monospace';
                ctx.fillStyle = '#706e6b';
                ctx.textAlign = 'left';
                ctx.textBaseline = 'top';
                ctx.fillText(label, 0, 0);
                ctx.restore();
            }
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
            ctx.fillText(
                `ideal (${idealCount.toFixed(1)})`,
                marginLeft - 5,
                idealY + 4
            );
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
        ctx.fillText('Expected (±25%)', marginLeft + 14, legendY);

        ctx.fillStyle = '#fe9339';
        ctx.fillRect(marginLeft + 120, legendY - 8, 10, 10);
        ctx.fillStyle = '#706e6b';
        ctx.fillText('Marginal (±50%)', marginLeft + 134, legendY);

        ctx.fillStyle = '#ea001e';
        ctx.fillRect(marginLeft + 240, legendY - 8, 10, 10);
        ctx.fillStyle = '#706e6b';
        ctx.fillText('Outlier (>50%)', marginLeft + 254, legendY);
    }
}
