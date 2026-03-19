import { createElement } from '@lwc/engine-dom';
import QrngValidationResults from 'c/qrngValidationResults';
import getValidationResults from '@salesforce/apex/QRNGSetupController.getValidationResults';
import runValidationTests from '@salesforce/apex/QRNGSetupController.runValidationTests';

jest.mock(
    '@salesforce/apex/QRNGSetupController.getValidationResults',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/QRNGSetupController.runValidationTests',
    () => ({ default: jest.fn() }),
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

describe('c-qrng-validation-results', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
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
});
