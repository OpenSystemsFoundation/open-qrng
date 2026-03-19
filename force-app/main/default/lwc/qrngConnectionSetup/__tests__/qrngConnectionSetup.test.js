import { createElement } from '@lwc/engine-dom';
import QrngConnectionSetup from 'c/qrngConnectionSetup';
import testConnection from '@salesforce/apex/QRNGSetupController.testConnection';
import getAvailableBackends from '@salesforce/apex/QRNGSetupController.getAvailableBackends';
import discoverInstances from '@salesforce/apex/QRNGSetupController.discoverInstances';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';

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
    '@salesforce/apex/QRNGSetupController.saveSettings',
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
});
