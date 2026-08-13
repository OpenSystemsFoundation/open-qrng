import { createElement } from '@lwc/engine-dom';
import QrngChshVisualizer from 'c/qrngChshVisualizer';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_RESULTS = {
    chshSValue: 2.6543,
    bellTestPassed: true,
    termBreakdown: {
        'E(a,b)': {
            expectationValue: 0.707,
            coefficient: 1,
            contribution: 0.707,
            std: 0.015
        },
        "E(a,b')": {
            expectationValue: 0.702,
            coefficient: 1,
            contribution: 0.702,
            std: 0.016
        },
        "E(a',b)": {
            expectationValue: 0.698,
            coefficient: 1,
            contribution: 0.698,
            std: 0.014
        },
        "E(a',b')": {
            expectationValue: -0.547,
            coefficient: -1,
            contribution: 0.547,
            std: 0.018
        }
    }
};

const MOCK_RESULTS_FAILED = {
    chshSValue: 1.8,
    bellTestPassed: false,
    termBreakdown: {
        'E(a,b)': {
            expectationValue: 0.45,
            coefficient: 1,
            contribution: 0.45,
            std: 0.02
        },
        "E(a,b')": {
            expectationValue: 0.44,
            coefficient: 1,
            contribution: 0.44,
            std: 0.02
        },
        "E(a',b)": {
            expectationValue: 0.46,
            coefficient: 1,
            contribution: 0.46,
            std: 0.02
        },
        "E(a',b')": {
            expectationValue: -0.45,
            coefficient: -1,
            contribution: 0.45,
            std: 0.02
        }
    }
};

describe('c-qrng-chsh-visualizer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-chsh-visualizer', {
            is: QrngChshVisualizer
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders nothing when no data provided', () => {
        const element = createComponent();
        expect(element.shadowRoot.querySelector('.result-badge')).toBeNull();
    });

    it('shows "Bell Inequality Violated" when passed', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('.result-badge');
        expect(badge).not.toBeNull();
        expect(badge.textContent).toContain('Bell Inequality Violated');
    });

    it('shows "No Violation Detected" when failed', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS_FAILED)
        });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('.result-badge');
        expect(badge).not.toBeNull();
        expect(badge.textContent).toContain('No Violation Detected');
    });

    it('displays S-value formatted to 4 decimals', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        const sText = element.shadowRoot.textContent;
        expect(sText).toContain('2.6543');
    });

    it('shows classical bound (2.0)', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('2.0');
    });

    it('shows quantum bound (2.828)', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('2.828');
    });

    it('renders gauge bar with correct width', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        const gaugeBar = element.shadowRoot.querySelector('.gauge-bar');
        expect(gaugeBar).not.toBeNull();
        const style = gaugeBar.getAttribute('style');
        expect(style).toContain('width:');
        expect(style).toContain('%');
    });

    it('renders green gauge for quantum S-value', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        const gaugeBar = element.shadowRoot.querySelector('.gauge-bar');
        expect(gaugeBar).not.toBeNull();
        const style = gaugeBar.getAttribute('style');
        expect(style).toContain('#2e844a');
    });

    it('renders red gauge for classical S-value', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS_FAILED)
        });
        await flushPromises();

        const gaugeBar = element.shadowRoot.querySelector('.gauge-bar');
        expect(gaugeBar).not.toBeNull();
        const style = gaugeBar.getAttribute('style');
        expect(style).toContain('#ea001e');
    });

    it('renders correlator breakdown table', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBe(4);
    });

    it('handles invalid JSON gracefully', async () => {
        const element = createComponent({
            validationResults: 'not-valid-json'
        });
        await flushPromises();

        // Should not crash
        expect(element.shadowRoot.querySelector('.result-badge')).toBeNull();
    });

    it('handles object input (not just string)', async () => {
        const element = createComponent({
            validationResults: MOCK_RESULTS
        });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('.result-badge');
        expect(badge).not.toBeNull();
    });

    it('shows formula string when breakdown available', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        const content = element.shadowRoot.textContent;
        expect(content).toContain('E(a,b)');
    });

    it('handles empty validationResults', async () => {
        const element = createComponent({ validationResults: '' });
        await flushPromises();

        expect(element.shadowRoot.querySelector('.result-badge')).toBeNull();
    });

    it('handles null chshSValue in results', async () => {
        const element = createComponent({
            validationResults: JSON.stringify({ bellTestPassed: false })
        });
        await flushPromises();

        expect(element.shadowRoot.querySelector('.result-badge')).toBeNull();
    });

    it('invalidates the parse cache when validationResults changes (no stale S-value)', async () => {
        const element = createComponent({
            validationResults: JSON.stringify(MOCK_RESULTS)
        });
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('2.6543');

        // Re-run produces a new S-value — the gauge must update
        element.validationResults = JSON.stringify(MOCK_RESULTS_FAILED);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain('1.8000');
        expect(element.shadowRoot.textContent).not.toContain('2.6543');
    });
});
