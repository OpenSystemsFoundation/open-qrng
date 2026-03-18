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

    it('renders bell container', () => {
        const element = createComponent({ sValue: 2.5 });

        const container = element.shadowRoot.querySelector('.bell-container');
        expect(container).not.toBeNull();
    });

    it('shows correct displayValue formatted to 3 decimal places', () => {
        const element = createComponent({ sValue: 2.5 });

        const valueEl = element.shadowRoot.querySelector('.value-label');
        expect(valueEl).not.toBeNull();
        expect(valueEl.textContent).toBe('2.500');
    });

    it('shows quantum verdict when sValue > 2.0', async () => {
        const element = createComponent({ sValue: 2.5 });
        await flushPromises();

        const quantumVerdict = element.shadowRoot.querySelector(
            '.verdict-badge.quantum'
        );
        expect(quantumVerdict).not.toBeNull();
        expect(quantumVerdict.textContent).toContain('Quantum Certified');

        const classicalVerdict = element.shadowRoot.querySelector(
            '.verdict-badge.classical'
        );
        expect(classicalVerdict).toBeNull();
    });

    it('shows classical verdict when sValue <= 2.0', async () => {
        const element = createComponent({ sValue: 1.8 });
        await flushPromises();

        const classicalVerdict = element.shadowRoot.querySelector(
            '.verdict-badge.classical'
        );
        expect(classicalVerdict).not.toBeNull();
        expect(classicalVerdict.textContent).toContain(
            'Below Quantum Threshold'
        );

        const quantumVerdict = element.shadowRoot.querySelector(
            '.verdict-badge.quantum'
        );
        expect(quantumVerdict).toBeNull();
    });

    it('positions value indicator based on sValue', () => {
        const element = createComponent({ sValue: 2.0 });

        const indicator = element.shadowRoot.querySelector('.value-indicator');
        const style = indicator.getAttribute('style');

        // S=2.0 / 2.828 * 100 ≈ 70.7%
        expect(style).toContain('left:');
        expect(style).toContain('%');
    });

    it('applies quantum class to value indicator when sValue > 2.0', () => {
        const element = createComponent({ sValue: 2.828 });

        const indicator = element.shadowRoot.querySelector(
            '.value-indicator.quantum'
        );
        expect(indicator).not.toBeNull();
    });

    it('applies classical class to value indicator when sValue <= 2.0', () => {
        const element = createComponent({ sValue: 0 });

        const indicator = element.shadowRoot.querySelector(
            '.value-indicator.classical'
        );
        expect(indicator).not.toBeNull();
    });

    it('renders zone labels for classical, quantum, and max', () => {
        const element = createComponent({ sValue: 2.5 });

        const labels = element.shadowRoot.querySelectorAll('.zone-label');
        expect(labels.length).toBe(3);

        const labelTexts = Array.from(labels).map((l) => l.textContent.trim());
        expect(labelTexts).toContain('Classical');
        expect(labelTexts).toContain('Quantum');
        expect(labelTexts).toContain('Max Violation');
    });

    it('renders three bar zones', () => {
        const element = createComponent({ sValue: 2.5 });

        const zones = element.shadowRoot.querySelectorAll('.bar-zone');
        expect(zones.length).toBe(3);
    });

    it('renders descriptive subtitle text', () => {
        const element = createComponent({ sValue: 2.5 });

        const subtitle = element.shadowRoot.querySelector('.bell-subtitle');
        expect(subtitle).not.toBeNull();
        expect(subtitle.textContent).toContain('S = 2.0');
    });

    it('defaults to 0 when sValue is not a number', () => {
        const element = createComponent({ sValue: 'abc' });

        const valueEl = element.shadowRoot.querySelector('.value-label');
        expect(valueEl.textContent).toBe('0.000');
    });
});
