import { LightningElement, api } from 'lwc';

const CLASSICAL_BOUND = 2.0;
const QUANTUM_BOUND = 2 * Math.sqrt(2); // 2√2 ≈ 2.828
const SCALE_MAX = 3.0;

export default class QrngChshVisualizer extends LightningElement {
    @api validationResults = '';

    _parsed = null;

    get results() {
        if (!this.validationResults) return null;
        if (this._parsed) return this._parsed;
        try {
            this._parsed =
                typeof this.validationResults === 'string'
                    ? JSON.parse(this.validationResults)
                    : this.validationResults;
        } catch {
            this._parsed = null;
        }
        return this._parsed;
    }

    get hasData() {
        return this.results && this.results.chshSValue != null;
    }

    get sValue() {
        return this.results ? Number(this.results.chshSValue).toFixed(4) : '—';
    }

    get passed() {
        return this.results && this.results.bellTestPassed === true;
    }

    get resultLabel() {
        return this.passed
            ? 'Bell Inequality Violated'
            : 'No Violation Detected';
    }

    get resultClass() {
        return this.passed
            ? 'result-badge slds-theme_success'
            : 'result-badge slds-theme_error';
    }

    get classicalBound() {
        return CLASSICAL_BOUND.toFixed(1);
    }

    get quantumBound() {
        return QUANTUM_BOUND.toFixed(3);
    }

    // Gauge bar: S-value position as percentage of scale
    get sValuePercent() {
        const s = this.results ? Number(this.results.chshSValue) : 0;
        return Math.min((s / SCALE_MAX) * 100, 100).toFixed(1);
    }

    get classicalPercent() {
        return ((CLASSICAL_BOUND / SCALE_MAX) * 100).toFixed(1);
    }

    get quantumPercent() {
        return ((QUANTUM_BOUND / SCALE_MAX) * 100).toFixed(1);
    }

    get gaugeBarStyle() {
        const s = this.results ? Number(this.results.chshSValue) : 0;
        const pct = Math.min((s / SCALE_MAX) * 100, 100);
        const color = s > CLASSICAL_BOUND ? '#2e844a' : '#ea001e';
        return `width: ${pct}%; background: ${color};`;
    }

    get classicalLineStyle() {
        return `left: ${this.classicalPercent}%;`;
    }

    get quantumLineStyle() {
        return `left: ${this.quantumPercent}%;`;
    }

    // Per-correlator breakdown
    get hasBreakdown() {
        return (
            this.results &&
            this.results.termBreakdown &&
            Object.keys(this.results.termBreakdown).length > 0
        );
    }

    get correlators() {
        if (!this.hasBreakdown) return [];
        const breakdown = this.results.termBreakdown;
        return Object.keys(breakdown).map((key) => {
            const term = breakdown[key];
            const ev = Number(term.expectationValue);
            const coeff = Number(term.coefficient);
            const contribution = Number(term.contribution);
            // Bar from 0 at center (50%) to value
            const barLeft = ev >= 0 ? 50 : 50 + (ev / 2) * 100;
            const barWidth = Math.abs(ev / 2) * 100;
            return {
                label: key,
                expectationValue: ev.toFixed(4),
                coefficient: coeff > 0 ? '+1' : '-1',
                contribution: contribution.toFixed(4),
                std: term.std ? Number(term.std).toFixed(4) : null,
                barStyle: `left: ${barLeft.toFixed(1)}%; width: ${barWidth.toFixed(1)}%; background: ${ev >= 0 ? '#0176d3' : '#ea001e'};`,
                isPositive: contribution >= 0,
                contributionClass:
                    contribution >= 0
                        ? 'contribution-positive'
                        : 'contribution-negative'
            };
        });
    }

    get formulaString() {
        if (!this.hasBreakdown) return '';
        const keys = Object.keys(this.results.termBreakdown);
        const breakdown = this.results.termBreakdown;
        return keys
            .map((key, i) => {
                const coeff = Number(breakdown[key].coefficient);
                const sign = coeff >= 0 ? '+' : '-';
                return i === 0 && coeff >= 0 ? `${key}` : `${sign} ${key}`;
            })
            .join(' ');
    }
}
