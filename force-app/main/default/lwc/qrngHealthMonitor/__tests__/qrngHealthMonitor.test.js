import { createElement } from '@lwc/engine-dom';
import QrngHealthMonitor from 'c/qrngHealthMonitor';
import getAllBackendHealth from '@salesforce/apex/SetupController.getAllBackendHealth';
import refreshAllBackendHealth from '@salesforce/apex/SetupController.refreshAllBackendHealth';
import verifyBackendQuantum from '@salesforce/apex/SetupController.verifyBackendQuantum';

jest.mock(
    '@salesforce/apex/SetupController.getAllBackendHealth',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.refreshAllBackendHealth',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SetupController.verifyBackendQuantum',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    'lightning/navigation',
    () => {
        const Navigate = Symbol('Navigate');
        const NavigationMixin = (Base) =>
            class extends Base {
                static [Navigate] = Navigate;
            };
        NavigationMixin.Navigate = Navigate;
        return { NavigationMixin };
    },
    { virtual: true }
);

// Mock ResizeObserver for child qrngJobMonitor
global.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
};

// Mock Canvas getContext for child components
HTMLCanvasElement.prototype.getContext = jest.fn().mockReturnValue({
    clearRect: jest.fn(),
    fillRect: jest.fn(),
    beginPath: jest.fn(),
    arc: jest.fn(),
    fill: jest.fn(),
    stroke: jest.fn(),
    moveTo: jest.fn(),
    lineTo: jest.fn(),
    fillText: jest.fn(),
    measureText: jest.fn().mockReturnValue({ width: 0 }),
    save: jest.fn(),
    restore: jest.fn(),
    translate: jest.fn(),
    rotate: jest.fn(),
    scale: jest.fn()
});

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/** Find a lightning-button by its label property */
function findButton(root, label) {
    return Array.from(root.querySelectorAll('lightning-button')).find(
        (b) => b.label === label
    );
}

const proto = QrngHealthMonitor.prototype;

const MOCK_BACKENDS = [
    {
        id: 'backend1',
        name: 'ibm_brisbane',
        status: 'online',
        qubits: 127,
        queueLength: 5,
        processorFamily: 'Heron',
        processorRevision: 'r2',
        avgT1: 250,
        avgT2: 150,
        gateError: 0.003,
        readoutError: 0.02,
        lastSynced: '2026-03-19',
        chshSValue: 2.72,
        chshVerifiedAt: '2026-03-18',
        quantumVerified: true,
        chshJobId: 'job123',
        recordId: 'rec001'
    },
    {
        id: 'backend2',
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
        lastSynced: null,
        chshSValue: null,
        chshVerifiedAt: null,
        quantumVerified: false,
        chshJobId: null,
        recordId: 'rec002'
    }
];

describe('c-qrng-health-monitor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent() {
        const element = createElement('c-qrng-health-monitor', {
            is: QrngHealthMonitor
        });
        document.body.appendChild(element);
        return element;
    }

    it('calls getAllBackendHealth on connectedCallback', async () => {
        getAllBackendHealth.mockResolvedValue(MOCK_BACKENDS);
        createComponent();
        await flushPromises();
        expect(getAllBackendHealth).toHaveBeenCalled();
    });

    it('renders backend health table when data loads', async () => {
        getAllBackendHealth.mockResolvedValue(MOCK_BACKENDS);
        const element = createComponent();
        await flushPromises();
        expect(element.shadowRoot.querySelector('table')).not.toBeNull();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(2);
    });

    it('renders empty state when no backends', async () => {
        getAllBackendHealth.mockResolvedValue([]);
        const element = createComponent();
        await flushPromises();
        expect(element.shadowRoot.querySelector('table')).toBeNull();
    });

    it('handles getAllBackendHealth error gracefully', async () => {
        const spy = jest.spyOn(console, 'warn').mockImplementation(() => {});
        getAllBackendHealth.mockRejectedValue(new Error('err'));
        createComponent();
        await flushPromises();
        expect(spy).toHaveBeenCalled();
        spy.mockRestore();
    });

    it('Refresh button triggers refresh and shows toast', async () => {
        getAllBackendHealth.mockResolvedValue([]);
        refreshAllBackendHealth.mockResolvedValue(MOCK_BACKENDS);
        const element = createComponent();
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const refreshBtn = findButton(
            element.shadowRoot,
            'Refresh Backend Health'
        );
        refreshBtn.click();
        await flushPromises();

        expect(refreshAllBackendHealth).toHaveBeenCalled();
        expect(toastHandler).toHaveBeenCalled();
    });

    it('Refresh button shows error toast on failure', async () => {
        getAllBackendHealth.mockResolvedValue([]);
        refreshAllBackendHealth.mockRejectedValue({
            body: { message: 'API Error' }
        });
        const element = createComponent();
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const refreshBtn = findButton(
            element.shadowRoot,
            'Refresh Backend Health'
        );
        refreshBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
    });

    it('Verify All button submits jobs for online backends', async () => {
        getAllBackendHealth.mockResolvedValue(MOCK_BACKENDS);
        verifyBackendQuantum.mockResolvedValue('verify-job');
        const element = createComponent();
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const verifyAllBtn = findButton(
            element.shadowRoot,
            'Verify All Backends'
        );
        verifyAllBtn.click();
        await flushPromises();

        expect(verifyBackendQuantum).toHaveBeenCalledTimes(1);
        expect(toastHandler).toHaveBeenCalled();
    });

    it('Verify All shows warning when no online backends', async () => {
        getAllBackendHealth.mockResolvedValue([{ ...MOCK_BACKENDS[1] }]);
        const element = createComponent();
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const verifyAllBtn = findButton(
            element.shadowRoot,
            'Verify All Backends'
        );
        verifyAllBtn.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
    });

    it('individual Verify button submits verification job', async () => {
        getAllBackendHealth.mockResolvedValue(MOCK_BACKENDS);
        verifyBackendQuantum.mockResolvedValue('verify-job-123');
        const element = createComponent();
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const verifyBtns = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).filter((b) => b.label === 'Verify');
        expect(verifyBtns.length).toBeGreaterThan(0);
        verifyBtns[0].click();
        await flushPromises();

        expect(verifyBackendQuantum).toHaveBeenCalled();
        expect(toastHandler).toHaveBeenCalled();
    });

    it('loadBackendHealth can be called as public API', async () => {
        getAllBackendHealth.mockResolvedValue(MOCK_BACKENDS);
        const element = createComponent();
        await flushPromises();

        getAllBackendHealth.mockClear();
        getAllBackendHealth.mockResolvedValue([]);
        element.loadBackendHealth();
        await flushPromises();
        expect(getAllBackendHealth).toHaveBeenCalledTimes(1);
    });

    // ── Prototype-based tests for pure utility methods ──

    it('mapBackendHealth maps online backend', () => {
        const mapped = proto.mapBackendHealth([MOCK_BACKENDS[0]]);
        expect(mapped[0].name).toBe('ibm_brisbane');
        expect(mapped[0].statusClass).toBe('slds-text-color_success');
        expect(mapped[0].verificationBadge).toBe('Verified');
        expect(mapped[0].hasVerifyJob).toBe(true);
        expect(mapped[0].processor).toContain('Heron');
    });

    it('mapBackendHealth maps offline/unverified backend', () => {
        const mapped = proto.mapBackendHealth([MOCK_BACKENDS[1]]);
        expect(mapped[0].statusClass).toBe('slds-text-color_error');
        expect(mapped[0].verificationBadge).toBe('Unverified');
        expect(mapped[0].hasVerifyJob).toBe(false);
    });

    it('mapBackendHealth handles failed verification', () => {
        const mapped = proto.mapBackendHealth([
            {
                id: '2',
                name: 'b2',
                status: 'online',
                quantumVerified: false,
                chshSValue: 1.5
            }
        ]);
        expect(mapped[0].verificationBadge).toBe('Failed');
    });

    it('computeFidelityScore tiers', () => {
        expect(
            proto.computeFidelityScore({
                gateError: 0.001,
                readoutError: 0.005,
                avgT1: 300,
                avgT2: 200
            }).tier
        ).toBe('excellent');
        expect(
            proto.computeFidelityScore({
                gateError: 0.9,
                readoutError: 0.9,
                avgT1: 20,
                avgT2: 10
            }).tier
        ).toBe('poor');
        expect(proto.computeFidelityScore({}).tier).toBe('none');
        const partial = proto.computeFidelityScore({ gateError: 0.01 });
        expect(partial.breakdown).toContain('Gate:');
    });

    it('formatTime formats various values', () => {
        expect(proto.formatTime(250)).toBe('250.0 us');
        expect(proto.formatTime(1500)).toBe('1.5 ms');
        expect(proto.formatTime(null)).toBe('\u2014');
        expect(proto.formatTime(undefined)).toBe('\u2014');
        expect(proto.formatTime('abc')).toBe('\u2014');
    });

    it('formatPercent formats various values', () => {
        expect(proto.formatPercent(0.003)).toBe('0.300%');
        expect(proto.formatPercent(null)).toBe('\u2014');
        expect(proto.formatPercent(undefined)).toBe('\u2014');
        expect(proto.formatPercent('abc')).toBe('\u2014');
    });

    it('reduceErrors handles different formats', () => {
        expect(proto.reduceErrors('plain')).toBe('plain');
        expect(proto.reduceErrors({ body: { message: 'body' } })).toBe('body');
        expect(proto.reduceErrors({ message: 'msg' })).toBe('msg');
        expect(proto.reduceErrors({ code: 500 })).toBe('{"code":500}');
    });
});
