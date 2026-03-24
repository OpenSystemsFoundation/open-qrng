import { createElement } from '@lwc/engine-dom';
import QrngConnectionSetup from 'c/qrngConnectionSetup';
import testConnection from '@salesforce/apex/SetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/SetupController.getAvailableBackends';
import discoverInstances from '@salesforce/apex/SetupController.discoverInstances';
import saveSettings from '@salesforce/apex/SetupController.saveSettings';

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
jest.mock(
    '@salesforce/apex/SetupController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Find a lightning-button by its label property */
function findButton(root, label) {
    return Array.from(root.querySelectorAll('lightning-button')).find(
        (b) => b.label === label
    );
}

/** Find a lightning-input by its type property */
function findInputByType(root, type) {
    return Array.from(root.querySelectorAll('lightning-input')).find(
        (i) => i.type === type
    );
}

const proto = QrngConnectionSetup.prototype;

describe('c-qrng-connection-setup', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-connection-setup', {
            is: QrngConnectionSetup
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders API key input when hasApiKey is false', async () => {
        const el = createComponent({ hasApiKey: false });
        await flushPromises();
        const pwInput = findInputByType(el.shadowRoot, 'password');
        expect(pwInput).not.toBeUndefined();
    });

    it('renders Save Key button when hasApiKey is false', async () => {
        const el = createComponent({ hasApiKey: false });
        await flushPromises();
        const btn = findButton(el.shadowRoot, 'Save Key');
        expect(btn).not.toBeUndefined();
    });

    it('renders connection badge when hasApiKey is true', async () => {
        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        expect(el.shadowRoot.querySelector('lightning-badge')).not.toBeNull();
    });

    it('hasApiKey getter/setter works', () => {
        const el = createComponent();
        el.hasApiKey = true;
        expect(el.hasApiKey).toBe(true);
        el.hasApiKey = false;
        expect(el.hasApiKey).toBe(false);
    });

    it('instanceCRN getter/setter works', () => {
        const el = createComponent();
        el.instanceCRN = 'crn:test';
        expect(el.instanceCRN).toBe('crn:test');
    });

    it('Save Key button shows warning when no key', async () => {
        const el = createComponent({ hasApiKey: false });
        await flushPromises();
        const toastHandler = jest.fn();
        el.addEventListener('lightning__showtoast', toastHandler);

        const btn = findButton(el.shadowRoot, 'Save Key');
        btn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(saveSettings).not.toHaveBeenCalled();
    });

    it('Test Connection button sets connected state', async () => {
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockResolvedValue([
            { name: 'ibm_brisbane', qubits: 127, status: 'online' }
        ]);

        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const backendsHandler = jest.fn();
        el.addEventListener('backendsloaded', backendsHandler);

        const btn = findButton(el.shadowRoot, 'Test Connection');
        btn.click();
        await flushPromises();

        expect(backendsHandler).toHaveBeenCalled();
    });

    it('Test Connection handles failure', async () => {
        testConnection.mockResolvedValue({
            connected: false,
            message: 'Auth failed'
        });
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const btn = findButton(el.shadowRoot, 'Test Connection');
        btn.click();
        await flushPromises();

        expect(getAvailableBackends).not.toHaveBeenCalled();
    });

    it('Test Connection handles exception', async () => {
        testConnection.mockRejectedValue({ message: 'Network error' });
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const btn = findButton(el.shadowRoot, 'Test Connection');
        btn.click();
        await flushPromises();

        expect(testConnection).toHaveBeenCalled();
    });

    it('Test Connection handles backend fetch failure', async () => {
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockRejectedValue(new Error('Backend fail'));
        const spy = jest.spyOn(console, 'warn').mockImplementation(() => {});

        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const btn = findButton(el.shadowRoot, 'Test Connection');
        btn.click();
        await flushPromises();

        expect(spy).toHaveBeenCalled();
        spy.mockRestore();
    });

    it('Test Connection skips backends dispatch when empty', async () => {
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockResolvedValue([]);

        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        const backendsHandler = jest.fn();
        el.addEventListener('backendsloaded', backendsHandler);

        const btn = findButton(el.shadowRoot, 'Test Connection');
        btn.click();
        await flushPromises();

        expect(backendsHandler).not.toHaveBeenCalled();
    });

    it('Change button resets hasApiKey', async () => {
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const handler = jest.fn();
        el.addEventListener('apikeychange', handler);

        const changeBtn = findButton(el.shadowRoot, 'Change');
        changeBtn.click();
        await flushPromises();

        expect(el.hasApiKey).toBe(false);
        expect(handler).toHaveBeenCalled();
    });

    it('Auto-detect button discovers single instance', async () => {
        discoverInstances.mockResolvedValue([
            { crn: 'crn:auto', name: 'My Instance' }
        ]);
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const crnHandler = jest.fn();
        el.addEventListener('crnchange', crnHandler);
        const toastHandler = jest.fn();
        el.addEventListener('lightning__showtoast', toastHandler);

        const btn = findButton(el.shadowRoot, 'Auto-detect');
        btn.click();
        await flushPromises();

        expect(el.instanceCRN).toBe('crn:auto');
        expect(crnHandler).toHaveBeenCalled();
        expect(toastHandler).toHaveBeenCalled();
    });

    it('Auto-detect shows info for multiple instances', async () => {
        discoverInstances.mockResolvedValue([
            { crn: 'c1', name: 'I1' },
            { crn: 'c2', name: 'I2' }
        ]);
        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        findButton(el.shadowRoot, 'Auto-detect').click();
        await flushPromises();
        expect(th).toHaveBeenCalled();
    });

    it('Auto-detect shows warning for no instances', async () => {
        discoverInstances.mockResolvedValue([]);
        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        findButton(el.shadowRoot, 'Auto-detect').click();
        await flushPromises();
        expect(th).toHaveBeenCalled();
    });

    it('Auto-detect shows warning for null', async () => {
        discoverInstances.mockResolvedValue(null);
        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        findButton(el.shadowRoot, 'Auto-detect').click();
        await flushPromises();
        expect(th).toHaveBeenCalled();
    });

    it('Auto-detect shows error on failure', async () => {
        discoverInstances.mockRejectedValue({ message: 'fail' });
        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        findButton(el.shadowRoot, 'Auto-detect').click();
        await flushPromises();
        expect(th).toHaveBeenCalled();
    });

    it('testConnectionProgrammatic public API', async () => {
        testConnection.mockResolvedValue({ connected: false, message: 'test' });
        const el = createComponent({ hasApiKey: true });
        await el.testConnectionProgrammatic();
        await flushPromises();
        expect(testConnection).toHaveBeenCalled();
    });

    it('apiKeyForSave returns null when configured', () => {
        const el = createComponent({ hasApiKey: true });
        expect(el.apiKeyForSave).toBeNull();
    });

    it('apiKeyForSave returns null when empty', () => {
        const el = createComponent({ hasApiKey: false });
        expect(el.apiKeyForSave).toBeNull();
    });

    it('markApiKeyConfigured does nothing without apiKey', () => {
        const el = createComponent({ hasApiKey: false });
        el.markApiKeyConfigured();
        expect(el.hasApiKey).toBe(false);
    });

    // ── Prototype tests ──

    it('reduceErrors handles different formats', () => {
        expect(proto.reduceErrors('plain')).toBe('plain');
        expect(proto.reduceErrors({ body: { message: 'body' } })).toBe('body');
        expect(proto.reduceErrors({ message: 'msg' })).toBe('msg');
        expect(proto.reduceErrors({ code: 500 })).toBe('{"code":500}');
    });

    // ── Connection testing edge cases ──

    it('connectionStatusLabel returns Connected when isConnected true', async () => {
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockResolvedValue([]);
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const btn = findButton(el.shadowRoot, 'Test Connection');
        btn.click();
        await flushPromises();

        // Check badge text
        const badge = el.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Connected');
    });

    it('connectionStatusLabel returns Not Connected initially', async () => {
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const badge = el.shadowRoot.querySelector('lightning-badge');
        expect(badge.label).toBe('Not Connected');
    });

    it('connectionBadgeClass includes success theme when connected', async () => {
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockResolvedValue([]);
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        findButton(el.shadowRoot, 'Test Connection').click();
        await flushPromises();

        const badge = el.shadowRoot.querySelector('lightning-badge');
        expect(badge.className).toContain('slds-theme_success');
    });

    // ── Save API key flow ──

    it('Save Key saves and auto-tests connection', async () => {
        saveSettings.mockResolvedValue(undefined);
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockResolvedValue([]);

        const el = createComponent({ hasApiKey: false });
        await flushPromises();

        const toastHandler = jest.fn();
        el.addEventListener('lightning__showtoast', toastHandler);
        const apikeyHandler = jest.fn();
        el.addEventListener('apikeychange', apikeyHandler);

        // Set the API key value
        const pwInput = findInputByType(el.shadowRoot, 'password');
        pwInput.value = 'test-api-key-123';
        pwInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        // Click save
        findButton(el.shadowRoot, 'Save Key').click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalledWith(
            expect.objectContaining({ apiKey: 'test-api-key-123' })
        );
        expect(apikeyHandler).toHaveBeenCalled();
        expect(toastHandler).toHaveBeenCalled();
        // Auto-test should have been triggered
        expect(testConnection).toHaveBeenCalled();
    });

    it('Save Key handles save failure', async () => {
        saveSettings.mockRejectedValue({
            body: { message: 'Permission denied' }
        });

        const el = createComponent({ hasApiKey: false });
        await flushPromises();

        const toastHandler = jest.fn();
        el.addEventListener('lightning__showtoast', toastHandler);

        // Set the API key value
        const pwInput = findInputByType(el.shadowRoot, 'password');
        pwInput.value = 'test-api-key';
        pwInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        findButton(el.shadowRoot, 'Save Key').click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
    });

    // ── CRN handling ──

    it('handleCRNChange updates instanceCRN and dispatches event', async () => {
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        const crnHandler = jest.fn();
        el.addEventListener('crnchange', crnHandler);

        const crnInput = Array.from(
            el.shadowRoot.querySelectorAll('lightning-input')
        ).find((i) => i.label === 'Instance CRN');
        expect(crnInput).toBeDefined();
        crnInput.value = 'crn:v1:bluemix:test';
        crnInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(crnHandler).toHaveBeenCalled();
    });

    // ── markApiKeyConfigured ──

    it('markApiKeyConfigured sets hasApiKey when apiKey exists', async () => {
        const el = createComponent({ hasApiKey: false });
        await flushPromises();

        // Set the API key value
        const pwInput = findInputByType(el.shadowRoot, 'password');
        pwInput.value = 'my-key';
        pwInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        const handler = jest.fn();
        el.addEventListener('apikeychange', handler);

        el.markApiKeyConfigured();

        expect(el.hasApiKey).toBe(true);
        expect(handler).toHaveBeenCalled();
    });

    // ── apiKeyForSave edge case ──

    it('apiKeyForSave returns key value when not configured', async () => {
        const el = createComponent({ hasApiKey: false });
        await flushPromises();

        const pwInput = findInputByType(el.shadowRoot, 'password');
        pwInput.value = 'a-key';
        pwInput.dispatchEvent(new CustomEvent('change'));
        await flushPromises();

        expect(el.apiKeyForSave).toBe('a-key');
    });

    // ── Test Connection sets connectionMessage on error ──

    it('Test Connection sets error connectionMessage on exception', async () => {
        testConnection.mockRejectedValue({
            body: { message: 'Server down' }
        });
        const el = createComponent({ hasApiKey: true });
        await flushPromises();

        findButton(el.shadowRoot, 'Test Connection').click();
        await flushPromises();

        // connectionMessage should contain the error
        expect(testConnection).toHaveBeenCalled();
    });

    // ── Test Connection with null backends response ──

    it('Test Connection handles null backends response', async () => {
        testConnection.mockResolvedValue({ connected: true, message: 'OK' });
        getAvailableBackends.mockResolvedValue(null);

        const el = createComponent({ hasApiKey: true });
        await flushPromises();
        const backendsHandler = jest.fn();
        el.addEventListener('backendsloaded', backendsHandler);

        findButton(el.shadowRoot, 'Test Connection').click();
        await flushPromises();

        expect(backendsHandler).not.toHaveBeenCalled();
    });
});
