import { LightningElement, api } from 'lwc';

export default class QrngBellTestIndicator extends LightningElement {
    @api sValue = 0;

    get displayValue() {
        const val = parseFloat(this.sValue) || 0;
        return val.toFixed(3);
    }

    get isQuantum() {
        return parseFloat(this.sValue) > 2.0;
    }

    get gaugeStyle() {
        // Map S-value (0 to 2*sqrt(2) ~ 2.828) to degrees (0 to 180)
        const maxS = 2.828;
        const val = Math.min(parseFloat(this.sValue) || 0, maxS);
        const degrees = (val / maxS) * 180;
        return `--gauge-rotation: ${degrees}deg; --gauge-value: ${val}`;
    }
}
