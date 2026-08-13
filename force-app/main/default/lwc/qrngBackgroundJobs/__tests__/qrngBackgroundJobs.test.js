import { createElement } from '@lwc/engine-dom';
import QrngBackgroundJobs from 'c/qrngBackgroundJobs';
import getSettings from '@salesforce/apex/SetupController.getSettings';
import startSweeper from '@salesforce/apex/SetupController.startSweeper';
import stopSweeper from '@salesforce/apex/SetupController.stopSweeper';
import startIntegrityCheck from '@salesforce/apex/SetupController.startIntegrityCheck';
import stopIntegrityCheck from '@salesforce/apex/SetupController.stopIntegrityCheck';

jest.mock(
    '@salesforce/apex/SetupController.getSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.startSweeper',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.stopSweeper',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.startIntegrityCheck',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.stopIntegrityCheck',
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

function badgeLabels(root) {
    return Array.from(root.querySelectorAll('lightning-badge')).map(
        (b) => b.label
    );
}

const proto = QrngBackgroundJobs.prototype;

const INACTIVE_SETTINGS = {
    sweeperActive: false,
    pollIntervalMinutes: 5,
    integrityCheckActive: false,
    integrityCheckHour: 2
};

const ACTIVE_SETTINGS = {
    sweeperActive: true,
    pollIntervalMinutes: 10,
    integrityCheckActive: true,
    integrityCheckHour: 4
};

describe('c-qrng-background-jobs', () => {
    beforeEach(() => {
        getSettings.mockResolvedValue(INACTIVE_SETTINGS);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent() {
        const el = createElement('c-qrng-background-jobs', {
            is: QrngBackgroundJobs
        });
        document.body.appendChild(el);
        return el;
    }

    it('renders badges and buttons', async () => {
        const el = createComponent();
        await flushPromises();
        expect(
            el.shadowRoot.querySelectorAll('lightning-badge').length
        ).toBeGreaterThanOrEqual(2);
        expect(
            el.shadowRoot.querySelectorAll('lightning-button').length
        ).toBeGreaterThanOrEqual(2);
    });

    it('renders inputs for interval and hour', async () => {
        const el = createComponent();
        await flushPromises();
        expect(
            el.shadowRoot.querySelectorAll('lightning-input').length
        ).toBeGreaterThanOrEqual(2);
    });

    it('loads its own status on connect (self-wiring)', async () => {
        getSettings.mockResolvedValue(ACTIVE_SETTINGS);
        const el = createComponent();
        await flushPromises();

        expect(getSettings).toHaveBeenCalled();
        const labels = badgeLabels(el.shadowRoot);
        expect(labels).toEqual(['Active', 'Active']);
        expect(findButton(el.shadowRoot, 'Stop Job Sweeper')).toBeTruthy();
        expect(findButton(el.shadowRoot, 'Stop Integrity Check')).toBeTruthy();
    });

    it('lazy-tab scenario: component mounted late still shows correct state', async () => {
        // Simulate: settings already exist in the org, the Operations tab
        // renders long after the app shell loaded. Nobody pushes settings
        // into the component — it must load them itself.
        getSettings.mockResolvedValue(ACTIVE_SETTINGS);
        await flushPromises(); // time passes before the tab activates

        const el = createComponent(); // tab finally renders
        await flushPromises();

        const labels = badgeLabels(el.shadowRoot);
        expect(labels).toEqual(['Active', 'Active']);
        // Interval input reflects loaded settings
        const inputs = el.shadowRoot.querySelectorAll('lightning-input');
        expect(inputs[0].value).toBe(10);
        expect(inputs[1].value).toBe(4);
    });

    it('shows inline error when self-load fails', async () => {
        getSettings.mockRejectedValue({ body: { message: 'no access' } });
        const el = createComponent();
        await flushPromises();

        const errorBox = el.shadowRoot.querySelector(
            '[data-testid="background-jobs-error"]'
        );
        expect(errorBox).not.toBeNull();
        expect(errorBox.textContent).toContain('no access');
    });

    it('internal loading is authoritative over pushed initSettings', async () => {
        getSettings.mockResolvedValue(ACTIVE_SETTINGS);
        const el = createComponent();
        await flushPromises(); // internal load completes

        // A stale parent snapshot arrives late — must be ignored
        el.initSettings(INACTIVE_SETTINGS);
        await flushPromises();

        expect(badgeLabels(el.shadowRoot)).toEqual(['Active', 'Active']);
    });

    it('initSettings still applies before internal load resolves (backward compat)', async () => {
        // Internal load never resolves in this test
        getSettings.mockReturnValue(new Promise(() => {}));
        const el = createComponent();
        el.initSettings(ACTIVE_SETTINGS);
        await flushPromises();

        expect(badgeLabels(el.shadowRoot)).toEqual(['Active', 'Active']);
    });

    it('Start Job Sweeper button starts sweeper', async () => {
        startSweeper.mockResolvedValue(undefined);
        const el = createComponent();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);

        const btn = findButton(el.shadowRoot, 'Start Job Sweeper');
        btn.click();
        await flushPromises();

        expect(startSweeper).toHaveBeenCalled();
        expect(th).toHaveBeenCalled();
    });

    it('Sweeper button shows error on failure', async () => {
        startSweeper.mockRejectedValue({ message: 'fail' });
        const el = createComponent();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);

        findButton(el.shadowRoot, 'Start Job Sweeper').click();
        await flushPromises();

        expect(th).toHaveBeenCalled();
    });

    it('After starting sweeper, Stop button appears', async () => {
        startSweeper.mockResolvedValue(undefined);
        const el = createComponent();
        await flushPromises();

        findButton(el.shadowRoot, 'Start Job Sweeper').click();
        await flushPromises();

        const stopBtn = findButton(el.shadowRoot, 'Stop Job Sweeper');
        expect(stopBtn).not.toBeUndefined();
    });

    it('Stop Job Sweeper button stops sweeper', async () => {
        startSweeper.mockResolvedValue(undefined);
        stopSweeper.mockResolvedValue(undefined);
        const el = createComponent();
        await flushPromises();

        // Start first
        findButton(el.shadowRoot, 'Start Job Sweeper').click();
        await flushPromises();

        // Now stop
        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        findButton(el.shadowRoot, 'Stop Job Sweeper').click();
        await flushPromises();

        expect(stopSweeper).toHaveBeenCalled();
        expect(th).toHaveBeenCalled();
    });

    it('Start Integrity Check button starts check', async () => {
        startIntegrityCheck.mockResolvedValue(undefined);
        const el = createComponent();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);

        findButton(el.shadowRoot, 'Start Integrity Check').click();
        await flushPromises();

        expect(startIntegrityCheck).toHaveBeenCalled();
        expect(th).toHaveBeenCalled();
    });

    it('Integrity Check button shows error on failure', async () => {
        startIntegrityCheck.mockRejectedValue({ body: { message: 'fail' } });
        const el = createComponent();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);

        findButton(el.shadowRoot, 'Start Integrity Check').click();
        await flushPromises();

        expect(th).toHaveBeenCalled();
    });

    it('Stop Integrity Check button stops check', async () => {
        startIntegrityCheck.mockResolvedValue(undefined);
        stopIntegrityCheck.mockResolvedValue(undefined);
        const el = createComponent();
        await flushPromises();

        findButton(el.shadowRoot, 'Start Integrity Check').click();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);
        findButton(el.shadowRoot, 'Stop Integrity Check').click();
        await flushPromises();

        expect(stopIntegrityCheck).toHaveBeenCalled();
        expect(th).toHaveBeenCalled();
    });

    // ── Prototype tests ──

    it('initSettings sets values when status not yet loaded', () => {
        const ctx = {
            _statusLoaded: false,
            sweeperActive: false,
            pollIntervalMinutes: 5,
            integrityCheckActive: false,
            integrityCheckHour: 2,
            _applySettings: proto._applySettings
        };
        proto.initSettings.call(ctx, {
            sweeperActive: true,
            pollIntervalMinutes: 10,
            integrityCheckActive: true,
            integrityCheckHour: 4
        });
        expect(ctx.sweeperActive).toBe(true);
        expect(ctx.pollIntervalMinutes).toBe(10);
        expect(ctx.integrityCheckActive).toBe(true);
        expect(ctx.integrityCheckHour).toBe(4);
    });

    it('initSettings handles empty object', () => {
        const ctx = {
            _statusLoaded: false,
            sweeperActive: false,
            pollIntervalMinutes: 5,
            integrityCheckActive: false,
            integrityCheckHour: 2,
            _applySettings: proto._applySettings
        };
        proto.initSettings.call(ctx, {});
        expect(ctx.sweeperActive).toBe(false);
        expect(ctx.integrityCheckHour).toBe(2);
    });

    it('initSettings handles integrityCheckHour of 0', () => {
        const ctx = {
            _statusLoaded: false,
            integrityCheckHour: 2,
            _applySettings: proto._applySettings
        };
        proto.initSettings.call(ctx, { integrityCheckHour: 0 });
        expect(ctx.integrityCheckHour).toBe(0);
    });

    it('handlePollIntervalChange updates interval', () => {
        const ctx = { pollIntervalMinutes: 5 };
        proto.handlePollIntervalChange.call(ctx, { target: { value: '15' } });
        expect(ctx.pollIntervalMinutes).toBe(15);
    });

    it('handlePollIntervalChange keeps previous value on NaN', () => {
        const ctx = { pollIntervalMinutes: 5 };
        proto.handlePollIntervalChange.call(ctx, { target: { value: '' } });
        expect(ctx.pollIntervalMinutes).toBe(5);
    });

    it('handleIntegrityHourChange updates hour', () => {
        const ctx = { integrityCheckHour: 2 };
        proto.handleIntegrityHourChange.call(ctx, { detail: { value: '6' } });
        expect(ctx.integrityCheckHour).toBe(6);
    });

    it('handleIntegrityHourChange keeps previous value on NaN', () => {
        const ctx = { integrityCheckHour: 2 };
        proto.handleIntegrityHourChange.call(ctx, { detail: { value: 'x' } });
        expect(ctx.integrityCheckHour).toBe(2);
    });
});
