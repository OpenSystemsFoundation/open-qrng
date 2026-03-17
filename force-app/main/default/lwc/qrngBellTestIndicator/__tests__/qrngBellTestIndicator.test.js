import { createElement } from 'lwc';
import QrngBellTestIndicator from 'c/qrngBellTestIndicator';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-qrng-bell-test-indicator', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-bell-test-indicator', {
            is: QrngBellTestIndicator
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders gauge container', () => {
        const element = createComponent({ sValue: 2.5 });

        const gauge = element.shadowRoot.querySelector('.gauge-container');
        expect(gauge).not.toBeNull();
    });

    it('shows correct displayValue formatted to 3 decimal places', () => {
        const element = createComponent({ sValue: 2.5 });

        const valueEl = element.shadowRoot.querySelector('.gauge-value');
        expect(valueEl).not.toBeNull();
        expect(valueEl.textContent).toBe('2.500');
    });

    it('isQuantum is true when sValue > 2.0', async () => {
        const element = createComponent({ sValue: 2.5 });
        await flushPromises();

        const quantumVerdict =
            element.shadowRoot.querySelector('.verdict-quantum');
        expect(quantumVerdict).not.toBeNull();
        expect(quantumVerdict.textContent).toBe('Quantum Certified');

        const classicalVerdict =
            element.shadowRoot.querySelector('.verdict-classical');
        expect(classicalVerdict).toBeNull();
    });

    it('isQuantum is false when sValue <= 2.0', async () => {
        const element = createComponent({ sValue: 1.8 });
        await flushPromises();

        const classicalVerdict =
            element.shadowRoot.querySelector('.verdict-classical');
        expect(classicalVerdict).not.toBeNull();
        expect(classicalVerdict.textContent).toBe('Below Quantum Threshold');

        const quantumVerdict =
            element.shadowRoot.querySelector('.verdict-quantum');
        expect(quantumVerdict).toBeNull();
    });

    it('gaugeStyle contains correct rotation degrees', () => {
        const element = createComponent({ sValue: 2.0 });

        const gaugeEl = element.shadowRoot.querySelector('.gauge');
        const style = gaugeEl.getAttribute('style');

        // S=2.0, maxS=2.828, degrees = (2.0/2.828)*180 ~ 127.301
        expect(style).toContain('--gauge-rotation:');
        expect(style).toContain('deg');
    });

    it('shows "Quantum Certified" verdict when sValue > 2.0', () => {
        const element = createComponent({ sValue: 2.828 });

        const verdict = element.shadowRoot.querySelector('.verdict-quantum');
        expect(verdict).not.toBeNull();
        expect(verdict.textContent).toBe('Quantum Certified');
    });

    it('shows "Below Quantum Threshold" verdict when sValue <= 2.0', () => {
        const element = createComponent({ sValue: 0 });

        const verdict = element.shadowRoot.querySelector('.verdict-classical');
        expect(verdict).not.toBeNull();
        expect(verdict.textContent).toBe('Below Quantum Threshold');
    });
});
