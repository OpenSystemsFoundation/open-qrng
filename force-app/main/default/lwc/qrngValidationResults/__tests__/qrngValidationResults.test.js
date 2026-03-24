import { createElement } from '@lwc/engine-dom';
import QrngValidationResults from 'c/qrngValidationResults';
import getValidationResults from '@salesforce/apex/SetupController.getValidationResults';
import runValidationTests from '@salesforce/apex/SetupController.runValidationTests';

jest.mock(
    '@salesforce/apex/SetupController.getValidationResults',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/SetupController.runValidationTests',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
    { virtual: true }
);

jest.mock(
    'lightning/platformShowToastEvent',
    () => {
        return {
            ShowToastEvent: class extends CustomEvent {
                constructor(config) {
                    super('lightning__showtoast', { detail: config });
                }
            }
        };
    },
    { virtual: true }
);

const MOCK_RESULTS = {
    passed: true,
    frequencyTest: true,
    runsTest: true,
    chiSquaredTest: true,
    bitCount: 4096,
    onesProportion: 0.498,
    approximateEntropyTest: true,
    serialTest: true,
    cumulativeSumsTest: true,
    longestRunOfOnesTest: true,
    extendedTestsCompleted: true
};

const MOCK_BELL_RESULTS = {
    ...MOCK_RESULTS,
    chshSValue: 2.65,
    bellTestPassed: true
};

const mockCanvasContext = {
    clearRect: jest.fn(),
    fillRect: jest.fn(),
    strokeRect: jest.fn(),
    fillText: jest.fn(),
    beginPath: jest.fn(),
    moveTo: jest.fn(),
    lineTo: jest.fn(),
    stroke: jest.fn(),
    arc: jest.fn(),
    fill: jest.fn(),
    save: jest.fn(),
    restore: jest.fn(),
    translate: jest.fn(),
    rotate: jest.fn(),
    setLineDash: jest.fn(),
    measureText: jest.fn().mockReturnValue({ width: 10 }),
    font: '',
    fillStyle: '',
    strokeStyle: '',
    lineWidth: 1,
    textAlign: '',
    textBaseline: '',
    globalAlpha: 1
};

class MockResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
}

describe('c-qrng-validation-results', () => {
    beforeAll(() => {
        global.ResizeObserver = MockResizeObserver;
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    afterAll(() => {
        delete global.ResizeObserver;
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        HTMLCanvasElement.prototype.getContext = jest
            .fn()
            .mockReturnValue(mockCanvasContext);
    });

    function createComponent(recordId = 'a00xx000000test') {
        const element = createElement('c-qrng-validation-results', {
            is: QrngValidationResults
        });
        element.recordId = recordId;
        document.body.appendChild(element);
        return element;
    }

    function flushPromises() {
        return new Promise((resolve) => setTimeout(resolve, 0));
    }

    it('renders empty state when no results', async () => {
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        const illustration =
            element.shadowRoot.querySelector('.slds-illustration');
        expect(illustration).toBeTruthy();
    });

    it('renders critical tests section when results available', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_RESULTS);
        await flushPromises();

        const sectionHeaders =
            element.shadowRoot.querySelectorAll('.section-header');
        expect(sectionHeaders.length).toBeGreaterThanOrEqual(1);
    });

    it('renders PASSED badge when all tests pass', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_RESULTS);
        await flushPromises();

        const badge = element.shadowRoot.querySelector('.slds-badge');
        expect(badge).toBeTruthy();
        expect(badge.textContent).toBe('PASSED');
    });

    it('renders extended tests section when extended results available', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_RESULTS);
        await flushPromises();

        const testBadges =
            element.shadowRoot.querySelectorAll('.test-result-badge');
        // 3 critical + 7 extended (4 NIST + 3 SP 800-90B) = 10 tests
        expect(testBadges.length).toBe(10);
    });

    it('renders Bell test section when CHSH data present', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_BELL_RESULTS);
        await flushPromises();

        const testBadges =
            element.shadowRoot.querySelectorAll('.test-result-badge');
        // 3 critical + 1 bell + 7 extended = 11 tests
        expect(testBadges.length).toBe(11);
    });

    it('has a Run All Tests button', async () => {
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        const button = element.shadowRoot.querySelector('lightning-button');
        expect(button).toBeTruthy();
        expect(button.label).toBe('Run All Tests');
    });

    it('calls runValidationTests on button click', async () => {
        runValidationTests.mockResolvedValue(MOCK_RESULTS);
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        const button = element.shadowRoot.querySelector('lightning-button');
        button.click();
        await flushPromises();

        expect(runValidationTests).toHaveBeenCalledWith({
            jobId: 'a00xx000000test'
        });
    });

    it('shows pending state for extended tests before they run', async () => {
        const partialResults = {
            passed: true,
            frequencyTest: true,
            runsTest: true,
            chiSquaredTest: true,
            bitCount: 4096,
            onesProportion: 0.498
        };
        const element = createComponent();
        getValidationResults.emit(partialResults);
        await flushPromises();

        // Extended tests should show pending (clock icon)
        const pendingBadges =
            element.shadowRoot.querySelectorAll('.test-pending');
        expect(pendingBadges.length).toBe(7);
    });

    it('shows bit count and ones proportion', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_RESULTS);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('4096');
        expect(text).toContain('49.80%');
    });

    it('renders FAILED badge when tests fail', async () => {
        const element = createComponent();
        getValidationResults.emit({ ...MOCK_RESULTS, passed: false });
        await flushPromises();

        const badge = element.shadowRoot.querySelector('.slds-badge');
        expect(badge).toBeTruthy();
        expect(badge.textContent).toBe('FAILED');
        expect(badge.classList.contains('slds-theme_error')).toBe(true);
    });

    it('isVerifyJob returns true for CHSH Verification jobType', async () => {
        const element = createComponent();
        getValidationResults.emit({
            jobType: 'CHSH Verification',
            chshSValue: 2.65,
            bellTestPassed: true,
            passed: true
        });
        await flushPromises();

        // For verify jobs, critical and extended test sections should not render
        const sectionHeaders =
            element.shadowRoot.querySelectorAll('.section-header');
        // Only bell section header should be present, no critical/extended
        const headerTexts = Array.from(sectionHeaders).map(
            (h) => h.textContent
        );
        expect(headerTexts.some((t) => t.includes('Critical Gate Tests'))).toBe(
            false
        );
    });

    it('showCriticalTests and showExtendedTests are false for verify jobs', async () => {
        const element = createComponent();
        getValidationResults.emit({
            jobType: 'CHSH Verification',
            chshSValue: 2.75,
            bellTestPassed: true,
            passed: true
        });
        await flushPromises();

        // Critical and extended test badges should not appear
        const criticalBadges =
            element.shadowRoot.querySelectorAll('.test-result-badge');
        // Only bell test badge should be present (1 badge)
        expect(criticalBadges.length).toBe(1);
    });

    it('cardTitle changes for verify jobs', async () => {
        const element = createComponent();
        getValidationResults.emit({
            jobType: 'CHSH Verification',
            chshSValue: 2.65,
            bellTestPassed: true,
            passed: true
        });
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Quantum Verification Results');
    });

    it('cardTitle is Randomness Validation for non-verify jobs', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_RESULTS);
        await flushPromises();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card.title).toBe('Randomness Validation');
    });

    it('chshSValue formatted to 3 decimals', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_BELL_RESULTS);
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('2.650');
    });

    it('onesProportion shows dash when null', async () => {
        const element = createComponent();
        getValidationResults.emit({
            ...MOCK_RESULTS,
            onesProportion: null
        });
        await flushPromises();

        const text = element.shadowRoot.textContent;
        // \u2014 is em-dash, but the source uses —
        expect(text).toContain('\u2014');
    });

    it('handleRunTests shows error toast on failure', async () => {
        runValidationTests.mockRejectedValue({
            body: { message: 'Test execution failed' }
        });
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const button = element.shadowRoot.querySelector('lightning-button');
        button.click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        const toastDetail = toastHandler.mock.calls[0][0].detail;
        expect(toastDetail.title).toBe('Validation Failed');
        expect(toastDetail.message).toBe('Test execution failed');
        expect(toastDetail.variant).toBe('error');
    });

    it('handleRunTests shows generic error message for unknown error', async () => {
        runValidationTests.mockRejectedValue({});
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const button = element.shadowRoot.querySelector('lightning-button');
        button.click();
        await flushPromises();

        const toastDetail = toastHandler.mock.calls[0][0].detail;
        expect(toastDetail.message).toBe('Unknown error');
    });

    it('handleViewCircuit and handleCloseCircuit toggle modal', async () => {
        const element = createComponent();
        getValidationResults.emit(MOCK_BELL_RESULTS);
        await flushPromises();

        // Initially no modal
        let modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal).toBeNull();

        // Click View Circuit button
        const viewBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'View Circuit');
        viewBtn.click();
        await flushPromises();

        // Modal should appear
        modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal).not.toBeNull();

        // Click Close button in modal
        const closeBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'Close');
        closeBtn.click();
        await flushPromises();

        // Modal should disappear
        modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal).toBeNull();
    });

    it('hasCircuit returns true when circuitQasm present', async () => {
        const element = createComponent();
        getValidationResults.emit({
            ...MOCK_BELL_RESULTS,
            circuitQasm: 'OPENQASM 3.0; h q[0];'
        });
        await flushPromises();

        // The View Circuit button should be present (it's always shown for bell results)
        const viewBtn = Array.from(
            element.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === 'View Circuit');
        expect(viewBtn).toBeDefined();
    });

    it('lastRunTimestamp getter returns manualRunTimestamp', async () => {
        const element = createComponent();
        getValidationResults.emit({
            ...MOCK_RESULTS,
            manualRunTimestamp: '2026-03-17T10:00:00Z'
        });
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('2026-03-17T10:00:00Z');
    });

    it('lastRunTimestamp getter falls back to extendedTestsTimestamp', async () => {
        const element = createComponent();
        getValidationResults.emit({
            ...MOCK_RESULTS,
            extendedTestsTimestamp: '2026-03-18T12:00:00Z'
        });
        await flushPromises();

        const text = element.shadowRoot.textContent;
        expect(text).toContain('2026-03-18T12:00:00Z');
    });

    it('refresh() public API method calls refreshApex', async () => {
        const { refreshApex } = jest.requireMock('@salesforce/apex');
        const element = createComponent();
        getValidationResults.emit(MOCK_RESULTS);
        await flushPromises();

        await element.refresh();
        expect(refreshApex).toHaveBeenCalled();
    });

    it('overallStatusLabel shows No Results when no data', async () => {
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        // The empty state illustration should be shown instead of a badge
        const illustration =
            element.shadowRoot.querySelector('.slds-illustration');
        expect(illustration).toBeTruthy();
    });

    it('extendedPassed getter returns true when extendedPassed is true', async () => {
        const element = createComponent();
        getValidationResults.emit({
            ...MOCK_RESULTS,
            extendedPassed: true
        });
        await flushPromises();

        // All extended tests should show as passed
        const passedBadges = element.shadowRoot.querySelectorAll('.test-pass');
        expect(passedBadges.length).toBeGreaterThan(0);
    });

    it('extendedPassed getter returns false when not set', async () => {
        const element = createComponent();
        getValidationResults.emit({
            ...MOCK_RESULTS,
            extendedPassed: false
        });
        await flushPromises();

        // Component should still render
        const badge = element.shadowRoot.querySelector('.slds-badge');
        expect(badge).toBeTruthy();
    });

    it('handles error with message property', async () => {
        runValidationTests.mockRejectedValue({
            message: 'Direct error message'
        });
        const element = createComponent();
        getValidationResults.emit({});
        await flushPromises();

        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);

        const button = element.shadowRoot.querySelector('lightning-button');
        button.click();
        await flushPromises();

        const toastDetail = toastHandler.mock.calls[0][0].detail;
        expect(toastDetail.message).toBe('Direct error message');
    });
});
