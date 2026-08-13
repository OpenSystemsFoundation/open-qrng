import { createElement } from '@lwc/engine-dom';
import QrngComplianceExport from 'c/qrngComplianceExport';
import exportComplianceEvidence from '@salesforce/apex/SetupController.exportComplianceEvidence';

jest.mock(
    '@salesforce/apex/SetupController.exportComplianceEvidence',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const proto = QrngComplianceExport.prototype;

describe('c-qrng-compliance-export', () => {
    let origCreateObjectURL;
    let origRevokeObjectURL;

    beforeEach(() => {
        origCreateObjectURL = URL.createObjectURL;
        origRevokeObjectURL = URL.revokeObjectURL;
        URL.createObjectURL = jest.fn().mockReturnValue('blob:mock');
        URL.revokeObjectURL = jest.fn();
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        URL.createObjectURL = origCreateObjectURL;
        URL.revokeObjectURL = origRevokeObjectURL;
    });

    function createComponent() {
        const el = createElement('c-qrng-compliance-export', {
            is: QrngComplianceExport
        });
        document.body.appendChild(el);
        return el;
    }

    it('renders combobox and date inputs', async () => {
        const el = createComponent();
        await flushPromises();
        expect(
            el.shadowRoot.querySelector('lightning-combobox')
        ).not.toBeNull();
        expect(
            el.shadowRoot.querySelectorAll('lightning-input').length
        ).toBeGreaterThanOrEqual(2);
    });

    it('renders export button', async () => {
        const el = createComponent();
        await flushPromises();
        expect(el.shadowRoot.querySelector('lightning-button')).not.toBeNull();
    });

    it('sets default dates on render', async () => {
        const el = createComponent();
        await flushPromises();
        const dateInputs = Array.from(
            el.shadowRoot.querySelectorAll('lightning-input')
        ).filter((i) => i.type === 'date');
        expect(dateInputs).toHaveLength(2);
        expect(dateInputs[0].value).toBeDefined();
        expect(dateInputs[1].value).toBeDefined();
    });

    it('Export button calls exportComplianceEvidence and triggers download', async () => {
        exportComplianceEvidence.mockResolvedValue('{"evidence":"data"}');
        const el = createComponent();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(exportComplianceEvidence).toHaveBeenCalled();
        expect(th).toHaveBeenCalled();
        expect(URL.createObjectURL).toHaveBeenCalled();
        expect(URL.revokeObjectURL).toHaveBeenCalled();
    });

    it('Export button shows error toast on failure', async () => {
        exportComplianceEvidence.mockRejectedValue({
            body: { message: 'err' }
        });
        const el = createComponent();
        await flushPromises();

        const th = jest.fn();
        el.addEventListener('lightning__showtoast', th);

        el.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(th).toHaveBeenCalled();
    });

    // ── Prototype tests ──

    it('connectedCallback sets default dates in local time (not UTC)', () => {
        const ctx = { startDate: null, endDate: null };
        proto.connectedCallback.call(ctx);
        const now = new Date();
        const localToday = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
        expect(ctx.endDate).toBe(localToday);
        expect(ctx.startDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    });

    it('handleFrameworkChange updates selectedFramework', () => {
        const ctx = { selectedFramework: 'ALL' };
        proto.handleFrameworkChange.call(ctx, {
            detail: { value: 'ISO_27001' }
        });
        expect(ctx.selectedFramework).toBe('ISO_27001');
    });

    it('handleStartDateChange updates startDate', () => {
        const ctx = { startDate: null };
        proto.handleStartDateChange.call(ctx, {
            target: { value: '2026-01-01' }
        });
        expect(ctx.startDate).toBe('2026-01-01');
    });

    it('handleEndDateChange updates endDate', () => {
        const ctx = { endDate: null };
        proto.handleEndDateChange.call(ctx, {
            target: { value: '2026-03-31' }
        });
        expect(ctx.endDate).toBe('2026-03-31');
    });

    it('handleExport shows warning when dates missing', async () => {
        const events = [];
        const ctx = {
            startDate: null,
            endDate: null,
            isExporting: false,
            selectedFramework: 'ALL',
            dispatchEvent: (e) => events.push(e)
        };
        await proto.handleExport.call(ctx);
        await flushPromises();
        expect(events.length).toBeGreaterThan(0);
        expect(exportComplianceEvidence).not.toHaveBeenCalled();
    });

    it('handleExport shows warning when only startDate missing', async () => {
        const events = [];
        const ctx = {
            startDate: null,
            endDate: '2026-03-31',
            isExporting: false,
            selectedFramework: 'ALL',
            dispatchEvent: (e) => events.push(e)
        };
        await proto.handleExport.call(ctx);
        expect(exportComplianceEvidence).not.toHaveBeenCalled();
    });

    it('downloadJson creates blob and triggers download', () => {
        const ctx = { startDate: '2026-01-01', endDate: '2026-03-31' };
        const mockClick = jest.fn();
        const orig = document.createElement.bind(document);
        jest.spyOn(document, 'createElement').mockImplementation((tag) => {
            const el = orig(tag);
            if (tag === 'a') el.click = mockClick;
            return el;
        });
        proto.downloadJson.call(ctx, '{}', 'ISO_27001');
        expect(mockClick).toHaveBeenCalled();
        expect(URL.createObjectURL).toHaveBeenCalled();
        expect(URL.revokeObjectURL).toHaveBeenCalled();
        document.createElement.mockRestore();
    });
});
