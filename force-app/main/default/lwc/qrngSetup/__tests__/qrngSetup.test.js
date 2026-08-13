import { createElement } from '@lwc/engine-dom';
import QrngSetup from 'c/qrngSetup';
import getSettings from '@salesforce/apex/SetupController.getSettings';
import getUsageStats from '@salesforce/apex/SetupController.getUsageStats';

// Wire adapters
jest.mock(
    '@salesforce/apex/SetupController.getSettings',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/SetupController.getUsageStats',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// Imperative Apex mocks used by child components
jest.mock(
    '@salesforce/apex/SetupController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.testConnection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.getAvailableBackends',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.discoverInstances',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_SETTINGS = {
    hasApiKey: true,
    hasCRN: true,
    crnValue: 'crn:v1:test',
    defaultBackend: 'test_backend',
    defaultShots: 1024,
    useBellTest: false,
    useLeastBusy: false,
    pollIntervalMinutes: 5,
    complianceEmail: '',
    cachedBackends: [{ name: 'ibm_brisbane', qubits: 127, status: 'online' }]
};

const MOCK_USAGE_STATS = {
    totalJobs: 5,
    completedJobs: 3,
    totalCertificates: 3
};

describe('c-qrng-setup', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent() {
        const element = createElement('c-qrng-setup', {
            is: QrngSetup
        });
        document.body.appendChild(element);
        return element;
    }

    it('renders connection setup always, settings panel only when API key configured', async () => {
        const element = createComponent();

        const connectionSetup = element.shadowRoot.querySelector(
            'c-qrng-connection-setup'
        );
        expect(connectionSetup).not.toBeNull();

        // Settings panel hidden before API key is set
        let settingsPanel = element.shadowRoot.querySelector(
            'c-qrng-settings-panel'
        );
        expect(settingsPanel).toBeNull();

        // After settings wire fires with hasApiKey=true, settings panel appears
        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        settingsPanel = element.shadowRoot.querySelector(
            'c-qrng-settings-panel'
        );
        expect(settingsPanel).not.toBeNull();
    });

    it('renders usage stats with wire data', async () => {
        const element = createComponent();

        getUsageStats.emit(MOCK_USAGE_STATS);
        await flushPromises();

        const statValues = element.shadowRoot.querySelectorAll('.stat-value');
        expect(statValues).toHaveLength(3);

        const values = Array.from(statValues).map((el) => el.textContent);
        expect(values).toContain('5');
        expect(values).toContain('3');
    });

    it('passes hasApiKey and instanceCRN to connection setup', async () => {
        const element = createComponent();

        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        const connectionSetup = element.shadowRoot.querySelector(
            'c-qrng-connection-setup'
        );
        expect(connectionSetup.hasApiKey).toBe(true);
        expect(connectionSetup.instanceCRN).toBe('crn:v1:test');
    });

    it('passes backend options to settings panel', async () => {
        const element = createComponent();

        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        const settingsPanel = element.shadowRoot.querySelector(
            'c-qrng-settings-panel'
        );
        // Options include "Least Busy" + 1 backend = 2 options
        expect(settingsPanel.backendOptions.length).toBe(2);
    });

    it('updates backend options when backendsloaded event fires', async () => {
        const element = createComponent();

        // Must set hasApiKey so settings panel renders
        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        const connectionSetup = element.shadowRoot.querySelector(
            'c-qrng-connection-setup'
        );
        connectionSetup.dispatchEvent(
            new CustomEvent('backendsloaded', {
                detail: {
                    backends: [
                        { name: 'ibm_kyoto', qubits: 127, status: 'online' },
                        { name: 'ibm_osaka', qubits: 127, status: 'online' }
                    ]
                }
            })
        );
        await flushPromises();

        const settingsPanel = element.shadowRoot.querySelector(
            'c-qrng-settings-panel'
        );
        // 2 backends + Least Busy = 3 options
        expect(settingsPanel.backendOptions.length).toBe(3);
    });

    it('handles apikeychange event from connection setup', async () => {
        const element = createComponent();

        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        const connectionSetup = element.shadowRoot.querySelector(
            'c-qrng-connection-setup'
        );
        connectionSetup.dispatchEvent(
            new CustomEvent('apikeychange', {
                detail: { hasApiKey: false }
            })
        );
        await flushPromises();

        expect(connectionSetup.hasApiKey).toBe(false);
    });

    it('renders inline error when settings wire errors', async () => {
        const element = createComponent();

        getSettings.error({ message: 'settings boom' });
        await flushPromises();

        const errorBox = element.shadowRoot.querySelector(
            '[data-testid="setup-settings-error"]'
        );
        expect(errorBox).not.toBeNull();
        expect(errorBox.textContent).toContain('settings boom');
    });

    it('renders inline error when usage stats wire errors', async () => {
        const element = createComponent();

        getUsageStats.error({ message: 'stats boom' });
        await flushPromises();

        const errorMsg = element.shadowRoot.querySelector(
            '[data-testid="setup-stats-error"]'
        );
        expect(errorMsg).not.toBeNull();
        expect(errorMsg.textContent).toContain('stats boom');
    });

    it('handles crnchange event from connection setup', async () => {
        const element = createComponent();
        await flushPromises();

        const connectionSetup = element.shadowRoot.querySelector(
            'c-qrng-connection-setup'
        );
        connectionSetup.dispatchEvent(
            new CustomEvent('crnchange', {
                detail: { crn: 'crn:new:value' }
            })
        );
        await flushPromises();

        expect(connectionSetup.instanceCRN).toBe('crn:new:value');
    });
});
