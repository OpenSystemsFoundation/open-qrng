import { createElement } from '@lwc/engine-dom';
import QrngSettingsPanel from 'c/qrngSettingsPanel';
import saveSettings from '@salesforce/apex/QRNGSetupController.saveSettings';

jest.mock(
    '@salesforce/apex/QRNGSetupController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const proto = QrngSettingsPanel.prototype;

describe('c-qrng-settings-panel', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent(props = {}) {
        const el = createElement('c-qrng-settings-panel', {
            is: QrngSettingsPanel
        });
        Object.assign(el, props);
        document.body.appendChild(el);
        return el;
    }

    it('renders backend combobox', async () => {
        const el = createComponent();
        await flushPromises();
        expect(
            el.shadowRoot.querySelector('lightning-combobox')
        ).not.toBeNull();
    });

    it('renders inputs', async () => {
        const el = createComponent();
        await flushPromises();
        expect(
            el.shadowRoot.querySelectorAll('lightning-input').length
        ).toBeGreaterThanOrEqual(2);
    });

    it('renders save button', async () => {
        const el = createComponent();
        await flushPromises();
        expect(el.shadowRoot.querySelector('lightning-button')).not.toBeNull();
    });

    it('initSettings sets values via public API', async () => {
        const el = createComponent();
        await flushPromises();
        el.initSettings({
            defaultShots: 2048,
            useLeastBusy: false,
            defaultBackend: 'ibm_kyoto',
            pollIntervalMinutes: 10,
            complianceEmail: 'a@b.c'
        });
        await flushPromises();
        const cb = el.shadowRoot.querySelector('lightning-combobox');
        expect(cb.value).toBe('ibm_kyoto');
    });

    it('Save button calls saveSettings and dispatches events', async () => {
        saveSettings.mockResolvedValue(undefined);
        const el = createComponent();
        await flushPromises();

        const toastH = jest.fn();
        el.addEventListener('lightning__showtoast', toastH);
        const savedH = jest.fn();
        el.addEventListener('settingssaved', savedH);
        const apiKeyH = jest.fn();
        el.addEventListener('requestapikey', apiKeyH);

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(saveSettings).toHaveBeenCalled();
        expect(toastH).toHaveBeenCalled();
        expect(savedH).toHaveBeenCalled();
        expect(apiKeyH).toHaveBeenCalled();
    });

    it('Save button shows error toast on failure', async () => {
        saveSettings.mockRejectedValue({ body: { message: 'Save error' } });
        const el = createComponent();
        await flushPromises();
        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();
        expect(th).toHaveBeenCalled();
    });

    it('combobox change to specific backend', async () => {
        const el = createComponent({
            backendOptions: [
                { label: 'Least Busy', value: '__least_busy__' },
                { label: 'ibm', value: 'ibm_brisbane' }
            ]
        });
        await flushPromises();
        const cb = el.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'ibm_brisbane' } })
        );
        await flushPromises();
        expect(cb.value).toBe('ibm_brisbane');
    });

    it('combobox change back to least busy', async () => {
        const el = createComponent();
        await flushPromises();
        const cb = el.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', { detail: { value: '__least_busy__' } })
        );
        await flushPromises();
        expect(cb.value).toBe('__least_busy__');
    });

    // ── Prototype tests ──

    it('initSettings with useLeastBusy true', () => {
        const ctx = {
            defaultShots: 0,
            useLeastBusy: false,
            defaultBackend: '',
            pollIntervalMinutes: 0,
            complianceEmail: ''
        };
        proto.initSettings.call(ctx, {
            defaultShots: 2048,
            useLeastBusy: true,
            defaultBackend: 'ibm',
            pollIntervalMinutes: 10,
            complianceEmail: 'a@b'
        });
        expect(ctx.defaultShots).toBe(2048);
        expect(ctx.useLeastBusy).toBe(true);
        expect(ctx.defaultBackend).toBe('__least_busy__');
    });

    it('initSettings with useLeastBusy false and specific backend', () => {
        const ctx = {
            defaultShots: 0,
            useLeastBusy: true,
            defaultBackend: '',
            pollIntervalMinutes: 0,
            complianceEmail: ''
        };
        proto.initSettings.call(ctx, {
            useLeastBusy: false,
            defaultBackend: 'ibm_kyoto'
        });
        expect(ctx.useLeastBusy).toBe(false);
        expect(ctx.defaultBackend).toBe('ibm_kyoto');
    });

    it('initSettings with useLeastBusy false but no backend falls back', () => {
        const ctx = {
            defaultShots: 0,
            useLeastBusy: false,
            defaultBackend: '',
            pollIntervalMinutes: 0,
            complianceEmail: ''
        };
        proto.initSettings.call(ctx, {
            useLeastBusy: false,
            defaultBackend: null
        });
        expect(ctx.useLeastBusy).toBe(true);
        expect(ctx.defaultBackend).toBe('__least_busy__');
    });

    it('initSettings with empty object uses defaults', () => {
        const ctx = {
            defaultShots: 0,
            useLeastBusy: false,
            defaultBackend: '',
            pollIntervalMinutes: 0,
            complianceEmail: ''
        };
        proto.initSettings.call(ctx, {});
        expect(ctx.defaultShots).toBe(1024);
        expect(ctx.useLeastBusy).toBe(true);
        expect(ctx.defaultBackend).toBe('__least_busy__');
        expect(ctx.pollIntervalMinutes).toBe(5);
        expect(ctx.complianceEmail).toBe('');
    });

    it('handleShotsChange updates defaultShots', () => {
        const ctx = { defaultShots: 0 };
        proto.handleShotsChange.call(ctx, { target: { value: '2048' } });
        expect(ctx.defaultShots).toBe(2048);
    });

    it('handleComplianceEmailChange updates email', () => {
        const ctx = { complianceEmail: '' };
        proto.handleComplianceEmailChange.call(ctx, {
            target: { value: 'x@y' }
        });
        expect(ctx.complianceEmail).toBe('x@y');
    });

    it('handleBackendChange to least busy', () => {
        const ctx = { useLeastBusy: false, defaultBackend: 'ibm' };
        proto.handleBackendChange.call(ctx, {
            detail: { value: '__least_busy__' }
        });
        expect(ctx.useLeastBusy).toBe(true);
        expect(ctx.defaultBackend).toBe('__least_busy__');
    });

    it('handleBackendChange to specific', () => {
        const ctx = { useLeastBusy: true, defaultBackend: '__least_busy__' };
        proto.handleBackendChange.call(ctx, {
            detail: { value: 'ibm_brisbane' }
        });
        expect(ctx.useLeastBusy).toBe(false);
        expect(ctx.defaultBackend).toBe('ibm_brisbane');
    });

    it('reduceErrors handles different formats', () => {
        expect(proto.reduceErrors('plain')).toBe('plain');
        expect(proto.reduceErrors({ body: { message: 'b' } })).toBe('b');
        expect(proto.reduceErrors({ message: 'm' })).toBe('m');
        expect(proto.reduceErrors({ x: 1 })).toBe('{"x":1}');
    });
});
