import { LightningElement, api } from 'lwc';

const MAX_S = 2.828; // 2√2 — Tsirelson bound
const CLASSICAL_LIMIT = 2.0;

export default class QrngBellTestIndicator extends LightningElement {
    @api sValue = 0;

    get displayValue() {
        const val = parseFloat(this.sValue) || 0;
        return val.toFixed(3);
    }

    get isQuantum() {
        return parseFloat(this.sValue) > CLASSICAL_LIMIT;
    }

    get valuePosition() {
        const val = Math.min(Math.max(parseFloat(this.sValue) || 0, 0), MAX_S);
        const pct = (val / MAX_S) * 100;
        return `left: ${pct}%`;
    }

    get valueIndicatorClass() {
        return this.isQuantum
            ? 'value-indicator quantum'
            : 'value-indicator classical';
    }
}
