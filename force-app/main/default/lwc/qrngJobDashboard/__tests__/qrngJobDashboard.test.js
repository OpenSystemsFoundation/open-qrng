import { createElement } from '@lwc/engine-dom';
import QrngJobDashboard from 'c/qrngJobDashboard';
import getRecentJobs from '@salesforce/apex/SetupController.getRecentJobs';
import {
    subscribeToQuantumEvents,
    unsubscribeFromQuantumEvents
} from 'c/qrngEventSubscription';

jest.mock(
    '@salesforce/apex/SetupController.getRecentJobs',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
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

jest.mock(
    'c/qrngEventSubscription',
    () => ({
        subscribeToQuantumEvents: jest
            .fn()
            .mockReturnValue({ complete: null, failed: null }),
        unsubscribeFromQuantumEvents: jest.fn()
    }),
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

const proto = QrngJobDashboard.prototype;

const MOCK_JOBS = [
    {
        id: 'j1',
        name: 'QRNG-001',
        externalJobId: 'ext-1',
        backend: 'ibm_brisbane',
        status: 'Completed',
        jobType: 'QRNG',
        useBellTest: false,
        shots: 1024,
        numQubits: 2,
        purpose: 'Test',
        submittedAt: '2026-03-19T10:00:00Z',
        completedAt: '2026-03-19T10:05:00Z',
        executionTimeMs: 300000,
        qpuTimeSeconds: 1.5,
        requestedByName: 'Admin',
        errorMessage: null
    },
    {
        id: 'j2',
        name: 'QRNG-002',
        externalJobId: null,
        backend: null,
        status: 'Running',
        jobType: 'QRNG',
        useBellTest: false,
        shots: 2048,
        numQubits: 4,
        purpose: null,
        submittedAt: '2026-03-19T11:00:00Z',
        completedAt: null,
        executionTimeMs: null,
        qpuTimeSeconds: null,
        requestedByName: null,
        errorMessage: null
    },
    {
        id: 'j3',
        name: 'CHSH-001',
        externalJobId: 'ext-3',
        backend: 'ibm_kyoto',
        status: 'Failed',
        jobType: 'CHSH Verification',
        useBellTest: true,
        shots: 4096,
        numQubits: 2,
        purpose: 'Bell',
        submittedAt: '2026-03-18T10:00:00Z',
        completedAt: '2026-03-18T10:01:00Z',
        executionTimeMs: 500,
        qpuTimeSeconds: 0.5,
        requestedByName: 'Admin',
        errorMessage: 'Error'
    },
    {
        id: 'j4',
        name: 'QRNG-003',
        externalJobId: 'ext-4',
        backend: 'ibm_brisbane',
        status: 'Queued',
        jobType: 'QRNG',
        useBellTest: false,
        shots: 1024,
        numQubits: 2,
        purpose: 'Queued',
        submittedAt: '2026-03-19T12:00:00Z',
        completedAt: null,
        executionTimeMs: null,
        qpuTimeSeconds: null,
        requestedByName: 'User',
        errorMessage: null
    },
    {
        id: 'j5',
        name: 'QRNG-004',
        externalJobId: 'ext-5',
        backend: 'ibm_brisbane',
        status: 'Submitted',
        jobType: 'QRNG',
        useBellTest: false,
        shots: 1024,
        numQubits: 2,
        purpose: 'Sub',
        submittedAt: '2026-03-19T13:00:00Z',
        completedAt: null,
        executionTimeMs: null,
        qpuTimeSeconds: null,
        requestedByName: 'User',
        errorMessage: null
    }
];

describe('c-qrng-job-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent() {
        const element = createElement('c-qrng-job-dashboard', {
            is: QrngJobDashboard
        });
        document.body.appendChild(element);
        return element;
    }

    it('renders empty state when no jobs', async () => {
        const element = createComponent();
        getRecentJobs.emit([]);
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('.slds-text-color_weak')
        ).not.toBeNull();
    });

    it('renders job table when jobs exist', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();
        expect(element.shadowRoot.querySelector('table')).not.toBeNull();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(5);
    });

    it('displays stat counts', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();
        const stats = element.shadowRoot.querySelectorAll('.stat-value');
        expect(stats).toHaveLength(4);
        const vals = Array.from(stats).map((e) => e.textContent.trim());
        expect(vals).toContain('5');
        expect(vals).toContain('3');
    });

    it('renders combobox filter', async () => {
        const element = createComponent();
        await flushPromises();
        expect(
            element.shadowRoot.querySelector('lightning-combobox')
        ).not.toBeNull();
    });

    it('subscribes to events on connect', () => {
        createComponent();
        expect(subscribeToQuantumEvents).toHaveBeenCalled();
    });

    it('unsubscribes on disconnect', () => {
        const el = createComponent();
        document.body.removeChild(el);
        expect(unsubscribeFromQuantumEvents).toHaveBeenCalled();
    });

    it('Refresh button calls refreshApex', async () => {
        const { refreshApex } = require('@salesforce/apex');
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();

        const btn = findButton(element.shadowRoot, 'Refresh');
        btn.click();
        await flushPromises();
        expect(refreshApex).toHaveBeenCalled();
    });

    it('refreshJobs public API works', async () => {
        const { refreshApex } = require('@salesforce/apex');
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();
        element.refreshJobs();
        expect(refreshApex).toHaveBeenCalled();
    });

    it('filter change to Failed shows 1 job', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();

        const cb = element.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'Failed' } })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(1);
    });

    it('filter change to ACTIVE shows 3 jobs', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();

        const cb = element.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'ACTIVE' } })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(3);
    });

    it('filter change to QRNG shows 4 jobs', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();

        const cb = element.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'QRNG' } })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(4);
    });

    it('filter change to CHSH Verification shows 1 job', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();

        const cb = element.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: 'CHSH Verification' }
            })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(1);
    });

    it('filter change to Completed shows 1 job', async () => {
        const element = createComponent();
        getRecentJobs.emit(MOCK_JOBS);
        await flushPromises();

        const cb = element.shadowRoot.querySelector('lightning-combobox');
        cb.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'Completed' } })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelectorAll('tbody tr')).toHaveLength(1);
    });

    // ── Prototype tests ──

    it('formatMs formats correctly', () => {
        expect(proto.formatMs(500)).toBe('500 ms');
        expect(proto.formatMs(1500)).toBe('1.5 s');
        expect(proto.formatMs(null)).toBe('\u2014');
    });

    it('formatQpuTime formats correctly', () => {
        expect(proto.formatQpuTime(0.5)).toBe('500 ms');
        expect(proto.formatQpuTime(1.5)).toBe('1.50 s');
        expect(proto.formatQpuTime(null)).toBe('\u2014');
    });
});
