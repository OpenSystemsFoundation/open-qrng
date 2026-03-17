import { createElement } from 'lwc';
import QrngSetup from 'c/qrngSetup';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';

// Wire adapters for @wire-decorated properties
jest.mock(
    '@salesforce/apex/QRNGSetupController.getSettings',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.getUsageStats',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// Imperative Apex mocks
jest.mock(
    '@salesforce/apex/QRNGSetupController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.testConnection',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.getAvailableBackends',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_SETTINGS = {
    hasApiKey: true,
    defaultBackend: 'ibm_kingston',
    defaultShots: 1024,
    useBellTest: false
};

const MOCK_USAGE_STATS = {
    totalJobs: 5,
    completedJobs: 3,
    failedJobs: 1,
    totalCertificates: 3,
    totalAssignments: 10
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

    it('renders with default settings when wire returns data', async () => {
        const element = createComponent();

        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
        expect(combobox.value).toBe('ibm_kingston');
    });

    it('displays connection status badge', () => {
        const element = createComponent();

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge).not.toBeNull();
        expect(badge.label).toBe('Not Connected');
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

    it('calls saveSettings apex method with correct params on save', async () => {
        const element = createComponent();

        getSettings.emit(MOCK_SETTINGS);
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const saveButton = Array.from(buttons).find(
            (b) => b.label === 'Save Settings'
        );
        expect(saveButton).toBeDefined();
        saveButton.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith({
            apiKey: null,
            instanceCRN: '',
            defaultBackend: 'ibm_kingston',
            defaultShots: 1024,
            useBellTest: false
        });
    });
});
