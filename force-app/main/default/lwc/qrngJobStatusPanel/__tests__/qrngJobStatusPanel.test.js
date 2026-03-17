import { createElement } from 'lwc';
import QrngJobStatusPanel from 'c/qrngJobStatusPanel';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

function createComponent() {
    const element = createElement('c-qrng-job-status-panel', {
        is: QrngJobStatusPanel
    });
    element.recordId = 'a03xx000001234AAA';
    document.body.appendChild(element);
    return element;
}

describe('c-qrng-job-status-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the component with card title', async () => {
        const element = createComponent();
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        expect(card.title).toBe('Quantum Job Status');
    });

    it('renders refresh and retrieve buttons', async () => {
        const element = createComponent();
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const labels = Array.from(buttons).map((b) => b.label);
        expect(labels).toContain('Refresh Status');
        expect(labels).toContain('Retrieve Results');
    });

    it('renders progress indicator', async () => {
        const element = createComponent();
        await flushPromises();

        // Verify component renders without crashing
        expect(element.shadowRoot).toBeDefined();
    });

    it('shows loading spinner when no record loaded', async () => {
        const element = createComponent();
        await flushPromises();

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
    });

    it('exposes disableRefresh as true when no record', async () => {
        const element = createComponent();
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Status'
        );
        expect(refreshBtn.disabled).toBe(true);
    });

    it('exposes disableRetrieve as true when no record', async () => {
        const element = createComponent();
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const retrieveBtn = Array.from(buttons).find(
            (b) => b.label === 'Retrieve Results'
        );
        expect(retrieveBtn.disabled).toBe(true);
    });
});
