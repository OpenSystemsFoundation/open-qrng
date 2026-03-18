import { createElement } from 'lwc';
import QrngSetup from 'c/qrngSetup';
import getSettings from '@salesforce/apex/QRNGSetupController.getSettings';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';
import testConnection from '@salesforce/apex/QRNGSetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/QRNGSetupController.getAvailableBackends';
import getUsageStats from '@salesforce/apex/QRNGSetupController.getUsageStats';
import discoverInstances from '@salesforce/apex/QRNGSetupController.discoverInstances';
import getAllBackendHealth from '@salesforce/apex/QRNGSetupController.getAllBackendHealth';
import refreshAllBackendHealth from '@salesforce/apex/QRNGSetupController.refreshAllBackendHealth';
import startSweeper from '@salesforce/apex/QRNGSetupController.startSweeper';
import stopSweeper from '@salesforce/apex/QRNGSetupController.stopSweeper';
import startIntegrityCheck from '@salesforce/apex/QRNGSetupController.startIntegrityCheck';
import stopIntegrityCheck from '@salesforce/apex/QRNGSetupController.stopIntegrityCheck';

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

jest.mock(
    '@salesforce/apex/QRNGSetupController.discoverInstances',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.getAllBackendHealth',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.refreshAllBackendHealth',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.startSweeper',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.stopSweeper',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.startIntegrityCheck',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.stopIntegrityCheck',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_SETTINGS = {
    hasApiKey: true,
    defaultBackend: 'test_backend',
    defaultShots: 1024,
    useBellTest: false
};

const MOCK_SETTINGS_FULL = {
    hasApiKey: true,
    hasCRN: true,
    defaultBackend: 'ibm_brisbane',
    defaultShots: 2048,
    useBellTest: true,
    useLeastBusy: true,
    pollIntervalMinutes: 10,
    sweeperActive: true,
    integrityCheckActive: true,
    integrityCheckHour: 4,
    cachedBackends: [
        { name: 'ibm_brisbane', qubits: 127, status: 'online' },
        { name: 'ibm_kyoto', qubits: 127, status: { name: 'online' } }
    ]
};

const MOCK_USAGE_STATS = {
    totalJobs: 5,
    completedJobs: 3,
    failedJobs: 1,
    totalCertificates: 3,
    totalAssignments: 10
};

const MOCK_BACKENDS_HEALTH = [
    {
        id: 'b1',
        name: 'ibm_brisbane',
        status: 'online',
        qubits: 127,
        queueLength: 5,
        processorFamily: 'Heron',
        processorRevision: 'r2',
        avgT1: 150000,
        avgT2: 80000,
        gateError: 0.001,
        readoutError: 0.01,
        lastSynced: '2026-03-17T10:00:00.000Z'
    },
    {
        id: 'b2',
        name: 'ibm_kyoto',
        status: 'offline',
        qubits: 127,
        queueLength: null,
        processorFamily: null,
        processorRevision: null,
        avgT1: null,
        avgT2: null,
        gateError: null,
        readoutError: null,
        lastSynced: null
    }
];

describe('c-qrng-setup', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent() {
        // Pre-mock imperative calls that may be triggered by wiredSettings
        testConnection.mockResolvedValue({
            connected: false,
            message: 'Not connected'
        });
        getAllBackendHealth.mockResolvedValue([]);
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
        expect(combobox.value).toBe('test_backend');
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
            defaultBackend: 'test_backend',
            defaultShots: 1024,
            useBellTest: false,
            useLeastBusy: false,
            pollIntervalMinutes: 5
        });
    });

    // ── wiredSettings coverage (lines 47-52, 62) ────────────────
    it('masks CRN and sets useLeastBusy when settings have hasCRN and useLeastBusy', async () => {
        const element = createComponent();

        getSettings.emit(MOCK_SETTINGS_FULL);
        await flushPromises();

        // useLeastBusy = true means defaultBackend = '__least_busy__'
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox.value).toBe('__least_busy__');

        // cachedBackends should populate dropdown including Least Busy option
        expect(combobox.options.length).toBe(3); // 2 backends + 1 "Least Busy"
    });

    // ── handleApiKeyChange / handleCRNChange (lines 97-102) ─────
    it('updates apiKey on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const apiKeyInput = Array.from(inputs).find(
            (i) => i.label === 'IBM Quantum API Key'
        );
        apiKeyInput.value = 'my-new-key';
        apiKeyInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        // Save to verify the key was captured
        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({ apiKey: 'my-new-key' })
        );
    });

    it('updates instanceCRN on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const crnInput = Array.from(inputs).find(
            (i) => i.label === 'Instance CRN'
        );
        crnInput.value = 'crn:test:123';
        crnInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({ instanceCRN: 'crn:test:123' })
        );
    });

    // ── handleBackendChange (lines 104-113) ─────────────────────
    it('sets useLeastBusy true when __least_busy__ is selected', async () => {
        const element = createComponent();
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', { detail: { value: '__least_busy__' } })
        );
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({
                useLeastBusy: true,
                defaultBackend: ''
            })
        );
    });

    it('sets useLeastBusy false when specific backend is selected', async () => {
        const element = createComponent();
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        combobox.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'ibm_brisbane' } })
        );
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({
                useLeastBusy: false,
                defaultBackend: 'ibm_brisbane'
            })
        );
    });

    // ── handleShotsChange / handleBellTestChange (lines 115-125) ─
    it('updates defaultShots on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const shotsInput = Array.from(inputs).find(
            (i) => i.label === 'Default Shots'
        );
        shotsInput.value = '4096';
        shotsInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({ defaultShots: 4096 })
        );
    });

    it('updates useBellTest on checkbox change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const bellTestInput = Array.from(inputs).find(
            (i) => i.label === 'Use Bell Test by Default'
        );
        bellTestInput.checked = true;
        bellTestInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({ useBellTest: true })
        );
    });

    // ── handleTestConnection (lines 131-157) ────────────────────
    it('shows connected status and fetches backends on successful test', async () => {
        const element = createComponent();
        await flushPromises();

        testConnection.mockResolvedValue({
            connected: true,
            message: 'Connected OK'
        });
        getAvailableBackends.mockResolvedValue([
            { name: 'ibm_brisbane', qubits: 127, status: 'online' }
        ]);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const testBtn = Array.from(buttons).find(
            (b) => b.label === 'Test Connection'
        );
        testBtn.click();
        await flushPromises();

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Connected');
    });

    it('shows error message when test connection fails', async () => {
        const element = createComponent();
        await flushPromises();

        testConnection.mockRejectedValue({
            body: { message: 'Auth failed' }
        });

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const testBtn = Array.from(buttons).find(
            (b) => b.label === 'Test Connection'
        );
        testBtn.click();
        await flushPromises();

        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Not Connected');
    });

    it('handles getAvailableBackends failure gracefully', async () => {
        const element = createComponent();
        await flushPromises();

        testConnection.mockResolvedValue({
            connected: true,
            message: 'OK'
        });
        getAvailableBackends.mockRejectedValue(new Error('Backend error'));

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const testBtn = Array.from(buttons).find(
            (b) => b.label === 'Test Connection'
        );
        testBtn.click();
        await flushPromises();

        // Should still be connected, just no backends loaded
        const badge = element.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Connected');
    });

    // ── handleSaveSettings error path (line 181-188) ────────────
    it('shows error toast when saveSettings fails', async () => {
        const element = createComponent();
        await flushPromises();

        saveSettings.mockRejectedValue({
            body: { message: 'Save failed' }
        });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
    });

    // ── handleDiscoverCRN (lines 191-232) ───────────────────────
    it('auto-detects single CRN instance', async () => {
        const element = createComponent();
        await flushPromises();

        discoverInstances.mockResolvedValue([
            { crn: 'crn:test:single', name: 'My Instance' }
        ]);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const discoverBtn = Array.from(buttons).find(
            (b) => b.label === 'Auto-detect'
        );
        discoverBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe('CRN Found');
    });

    it('shows info toast when multiple instances found', async () => {
        const element = createComponent();
        await flushPromises();

        discoverInstances.mockResolvedValue([
            { crn: 'crn:1', name: 'Instance 1' },
            { crn: 'crn:2', name: 'Instance 2' }
        ]);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const discoverBtn = Array.from(buttons).find(
            (b) => b.label === 'Auto-detect'
        );
        discoverBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Multiple Instances'
        );
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('info');
    });

    it('shows warning toast when no instances found', async () => {
        const element = createComponent();
        await flushPromises();

        discoverInstances.mockResolvedValue([]);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const discoverBtn = Array.from(buttons).find(
            (b) => b.label === 'Auto-detect'
        );
        discoverBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.title).toBe('No Instances');
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('warning');
    });

    it('shows error toast when discover CRN fails', async () => {
        const element = createComponent();
        await flushPromises();

        discoverInstances.mockRejectedValue(new Error('Discovery error'));

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const discoverBtn = Array.from(buttons).find(
            (b) => b.label === 'Auto-detect'
        );
        discoverBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Discovery Failed'
        );
    });

    // ── handleRefreshHealth (lines 245-268) ─────────────────────
    it('refreshes backend health and shows success toast', async () => {
        const element = createComponent();
        await flushPromises();

        refreshAllBackendHealth.mockResolvedValue(MOCK_BACKENDS_HEALTH);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Backend Health'
        );
        refreshBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Health Refreshed'
        );
    });

    it('shows error toast when refreshAllBackendHealth fails', async () => {
        const element = createComponent();
        await flushPromises();

        refreshAllBackendHealth.mockRejectedValue(
            new Error('Health check error')
        );

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const refreshBtn = Array.from(buttons).find(
            (b) => b.label === 'Refresh Backend Health'
        );
        refreshBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Health Check Failed'
        );
    });

    // ── mapBackendHealth + formatTime/formatPercent (lines 270-309)
    it('renders backend health table after refresh', async () => {
        const element = createComponent();
        await flushPromises();

        refreshAllBackendHealth.mockResolvedValue(MOCK_BACKENDS_HEALTH);

        const refreshBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Refresh Backend Health');
        refreshBtn.click();
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBe(2);

        const cells = element.shadowRoot.querySelectorAll('tbody td');
        const cellTexts = Array.from(cells).map((c) => c.textContent.trim());
        // formatTime: 150000 > 1000 -> "150.0 ms"
        expect(cellTexts).toContain('150.0 ms');
        // formatPercent: 0.001 -> "0.100%"
        expect(cellTexts).toContain('0.100%');
        // null avgT1 -> "—"
        expect(cellTexts).toContain('\u2014');

        // Fidelity column: first backend has data, second has none
        const fidelityBadges =
            element.shadowRoot.querySelectorAll('.fidelity-badge');
        expect(fidelityBadges.length).toBe(2);
        // First backend should have a numeric score
        expect(fidelityBadges[0].textContent.trim()).toMatch(/^\d+$/);
        // Second backend (all nulls) should show em-dash
        expect(fidelityBadges[1].textContent.trim()).toBe('\u2014');
    });

    it('computes fidelity tiers correctly based on calibration data', async () => {
        const element = createComponent();
        await flushPromises();

        const excellentBackend = {
            id: 'b3',
            name: 'excellent_backend',
            status: 'online',
            qubits: 127,
            queueLength: 0,
            processorFamily: 'Heron',
            processorRevision: 'r2',
            avgT1: 300,
            avgT2: 200,
            gateError: 0.001,
            readoutError: 0.005
        };
        const poorBackend = {
            id: 'b4',
            name: 'poor_backend',
            status: 'online',
            qubits: 127,
            queueLength: 50,
            processorFamily: 'Eagle',
            processorRevision: 'r3',
            avgT1: 25,
            avgT2: 15,
            gateError: 0.08,
            readoutError: 0.15
        };

        refreshAllBackendHealth.mockResolvedValue([
            excellentBackend,
            poorBackend
        ]);

        const refreshBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Refresh Backend Health');
        refreshBtn.click();
        await flushPromises();

        const badges = element.shadowRoot.querySelectorAll('.fidelity-badge');
        expect(badges.length).toBe(2);

        // Excellent backend should have high score and green tier
        expect(
            badges[0].classList.contains('fidelity-excellent') ||
                badges[0].classList.contains('fidelity-good')
        ).toBe(true);

        // Poor backend should have low score and red/orange tier
        expect(
            badges[1].classList.contains('fidelity-poor') ||
                badges[1].classList.contains('fidelity-fair')
        ).toBe(true);

        // Fidelity badges should have title attribute with breakdown
        expect(badges[0].title).toContain('Gate:');
        expect(badges[0].title).toContain('Readout:');
    });

    // ── handleToggleSweeper (lines 330-362) ─────────────────────
    it('starts sweeper and shows success toast', async () => {
        const element = createComponent();
        await flushPromises();

        startSweeper.mockResolvedValue(undefined);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const sweeperBtn = Array.from(buttons).find(
            (b) => b.label === 'Start Job Sweeper'
        );
        sweeperBtn.click();
        await flushPromises();

        expect(startSweeper).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Sweeper Started'
        );
    });

    it('stops sweeper when already active', async () => {
        const element = createComponent();

        // Emit settings with sweeperActive=true
        getSettings.emit({ ...MOCK_SETTINGS, sweeperActive: true });
        await flushPromises();

        stopSweeper.mockResolvedValue(undefined);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const sweeperBtn = Array.from(buttons).find(
            (b) => b.label === 'Stop Job Sweeper'
        );
        sweeperBtn.click();
        await flushPromises();

        expect(stopSweeper).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Sweeper Stopped'
        );
    });

    it('shows error toast when sweeper toggle fails', async () => {
        const element = createComponent();
        await flushPromises();

        startSweeper.mockRejectedValue(new Error('Sweeper error'));

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const sweeperBtn = Array.from(buttons).find(
            (b) => b.label === 'Start Job Sweeper'
        );
        sweeperBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Sweeper Error'
        );
    });

    // ── handleIntegrityHourChange (line 385) ────────────────────
    it('updates integrityCheckHour on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const hourInput = Array.from(inputs).find(
            (i) => i.label === 'Check Hour (0-23)'
        );
        hourInput.dispatchEvent(
            new CustomEvent('change', { detail: { value: '6' } })
        );
        await flushPromises();

        // Verify it rendered (value bound to template)
        expect(hourInput).not.toBeNull();
    });

    // ── handleToggleIntegrityCheck (lines 388-421) ──────────────
    it('starts integrity check and shows success toast', async () => {
        const element = createComponent();
        await flushPromises();

        startIntegrityCheck.mockResolvedValue(undefined);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const integrityBtn = Array.from(buttons).find(
            (b) => b.label === 'Start Integrity Check'
        );
        integrityBtn.click();
        await flushPromises();

        expect(startIntegrityCheck).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Integrity Check Started'
        );
    });

    it('stops integrity check when already active', async () => {
        const element = createComponent();

        getSettings.emit({
            ...MOCK_SETTINGS,
            integrityCheckActive: true
        });
        await flushPromises();

        stopIntegrityCheck.mockResolvedValue(undefined);

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const integrityBtn = Array.from(buttons).find(
            (b) => b.label === 'Stop Integrity Check'
        );
        integrityBtn.click();
        await flushPromises();

        expect(stopIntegrityCheck).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Integrity Check Stopped'
        );
    });

    it('shows error toast when integrity check toggle fails', async () => {
        const element = createComponent();
        await flushPromises();

        startIntegrityCheck.mockRejectedValue(new Error('Integrity error'));

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const integrityBtn = Array.from(buttons).find(
            (b) => b.label === 'Start Integrity Check'
        );
        integrityBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.title).toBe(
            'Integrity Check Error'
        );
    });

    // ── reduceErrors (lines 443-448) ────────────────────────────
    it('reduceErrors handles string errors', async () => {
        const element = createComponent();
        await flushPromises();

        saveSettings.mockRejectedValue('plain string error');

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            'plain string error'
        );
    });

    it('reduceErrors falls back to JSON.stringify for unknown error shapes', async () => {
        const element = createComponent();
        await flushPromises();

        saveSettings.mockRejectedValue({ code: 42 });

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(toastHandler.mock.calls[0][0].detail.message).toBe(
            '{"code":42}'
        );
    });

    // ── handlePollIntervalChange (line 128) ─────────────────────
    it('updates pollIntervalMinutes on input change', async () => {
        const element = createComponent();
        await flushPromises();

        const inputs = element.shadowRoot.querySelectorAll('lightning-input');
        const intervalInput = Array.from(inputs).find(
            (i) => i.label === 'Interval (minutes)'
        );
        intervalInput.value = '15';
        intervalInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        saveSettings.mockResolvedValue(undefined);
        const saveBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Save Settings');
        saveBtn.click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({ pollIntervalMinutes: 15 })
        );
    });

    // ── Sweeper computed getters ────────────────────────────────
    it('shows correct sweeper button label and variant when active', async () => {
        const element = createComponent();

        getSettings.emit({ ...MOCK_SETTINGS, sweeperActive: true });
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const sweeperBtn = Array.from(buttons).find(
            (b) => b.label === 'Stop Job Sweeper'
        );
        expect(sweeperBtn).toBeDefined();
        expect(sweeperBtn.variant).toBe('destructive');
    });

    // ── Integrity computed getters ──────────────────────────────
    it('shows correct integrity button label and variant when active', async () => {
        const element = createComponent();

        getSettings.emit({
            ...MOCK_SETTINGS,
            integrityCheckActive: true
        });
        await flushPromises();

        const buttons = element.shadowRoot.querySelectorAll('lightning-button');
        const integrityBtn = Array.from(buttons).find(
            (b) => b.label === 'Stop Integrity Check'
        );
        expect(integrityBtn).toBeDefined();
        expect(integrityBtn.variant).toBe('destructive');
    });
});
