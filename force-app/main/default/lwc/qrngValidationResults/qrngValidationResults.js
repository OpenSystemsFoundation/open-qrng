import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getValidationResults from '@salesforce/apex/SetupController.getValidationResults';
import runValidationTests from '@salesforce/apex/SetupController.runValidationTests';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const CRITICAL_TESTS = [
    {
        key: 'frequencyTest',
        label: 'Frequency (Monobit)',
        description: 'Proportion of 0s vs 1s within 2σ of 50%',
        category: 'critical'
    },
    {
        key: 'runsTest',
        label: 'Runs Test',
        description: 'Consecutive identical bits follow random distribution',
        category: 'critical'
    },
    {
        key: 'chiSquaredTest',
        label: 'Chi-Squared',
        description: 'Uniformity of 4-bit blocks',
        category: 'critical'
    }
];

const EXTENDED_TESTS = [
    {
        key: 'minEntropyTest',
        label: 'Min-Entropy (SP 800-90B)',
        description:
            'Most Common Value entropy estimate ≥ 0.9 bits per bit (NIST SP 800-90B §6.3.1)',
        category: 'extended'
    },
    {
        key: 'repetitionCountTest',
        label: 'Repetition Count (SP 800-90B)',
        description:
            'No excessive consecutive identical bits (NIST SP 800-90B §4.4.1)',
        category: 'extended'
    },
    {
        key: 'adaptiveProportionTest',
        label: 'Adaptive Proportion (SP 800-90B)',
        description:
            'Bit proportion within window stays within bounds (NIST SP 800-90B §4.4.2)',
        category: 'extended'
    },
    {
        key: 'approximateEntropyTest',
        label: 'Approximate Entropy',
        description: 'Detects repetition patterns in overlapping m-bit blocks',
        category: 'extended'
    },
    {
        key: 'serialTest',
        label: 'Serial Test',
        description: 'Uniformity of overlapping 3-bit patterns',
        category: 'extended'
    },
    {
        key: 'cumulativeSumsTest',
        label: 'Cumulative Sums (CUSUM)',
        description: 'Detects drift or trends in the bitstring',
        category: 'extended'
    },
    {
        key: 'longestRunOfOnesTest',
        label: 'Longest Run of Ones',
        description: 'Consecutive 1s consistent with random sequence',
        category: 'extended'
    }
];

const BELL_TESTS = [
    {
        key: 'bellTestPassed',
        label: 'CHSH Bell Test (S > 2)',
        description: 'Proves quantum origin via Bell inequality violation',
        category: 'bell'
    }
];

export default class QrngValidationResults extends LightningElement {
    @api recordId;
    @track isRunning = false;
    _wiredResult;
    _results;

    @wire(getValidationResults, { jobId: '$recordId' })
    wiredResults(result) {
        this._wiredResult = result;
        if (result.data) {
            this._results = result.data;
        }
    }

    get hasResults() {
        return (
            this._results &&
            Object.keys(this._results).length > 0 &&
            // Exclude results that only contain jobType metadata
            (this._results.passed != null || this._results.chshSValue != null)
        );
    }

    @track showCircuitModal = false;

    get isVerifyJob() {
        return this._results?.jobType === 'CHSH Verification';
    }

    get circuitQubits() {
        // CHSH uses pairs; numPairs * 2 qubits, default 8
        const pairs = this._results?.numPairs;
        return pairs ? pairs * 2 : 8;
    }

    handleViewCircuit() {
        this.showCircuitModal = true;
    }

    handleCloseCircuit() {
        this.showCircuitModal = false;
    }

    get showCriticalTests() {
        return !this.isVerifyJob;
    }

    get showExtendedTests() {
        return !this.isVerifyJob;
    }

    get validationResultsJson() {
        return this._results ? JSON.stringify(this._results) : '';
    }

    get circuitQasm() {
        return this._results?.circuitQasm || '';
    }

    get hasCircuit() {
        return !!this.circuitQasm;
    }

    get cardTitle() {
        return this.isVerifyJob
            ? 'Quantum Verification Results'
            : 'Randomness Validation';
    }

    get hasExtendedResults() {
        return (
            this._results?.extendedTestsCompleted === true ||
            this._results?.allTestsCompleted === true
        );
    }

    get hasBellResults() {
        return this._results?.chshSValue != null;
    }

    get chshSValue() {
        const val = this._results?.chshSValue;
        return val != null ? Number(val).toFixed(3) : null;
    }

    get bitCount() {
        return this._results?.bitCount || 0;
    }

    get onesProportion() {
        const p = this._results?.onesProportion;
        return p != null ? (Number(p) * 100).toFixed(2) + '%' : '—';
    }

    get overallPassed() {
        return this._results?.passed === true;
    }

    get extendedPassed() {
        return this._results?.extendedPassed === true;
    }

    get overallStatusClass() {
        if (!this.hasResults) return '';
        return this.overallPassed
            ? 'slds-theme_success slds-badge'
            : 'slds-theme_error slds-badge';
    }

    get overallStatusLabel() {
        if (!this.hasResults) return 'No Results';
        return this.overallPassed ? 'PASSED' : 'FAILED';
    }

    get lastRunTimestamp() {
        return (
            this._results?.manualRunTimestamp ||
            this._results?.extendedTestsTimestamp ||
            null
        );
    }

    get criticalTests() {
        return this._buildTestList(CRITICAL_TESTS);
    }

    get extendedTests() {
        return this._buildTestList(EXTENDED_TESTS);
    }

    get bellTests() {
        if (!this.hasBellResults) return [];
        return this._buildTestList(BELL_TESTS);
    }

    _buildTestList(testDefs) {
        return testDefs.map((t) => {
            const result = this._results ? this._results[t.key] : undefined;
            const passed = result === true;
            const failed = result === false;
            const pending = result === undefined || result === null;
            return {
                ...t,
                passed,
                failed,
                pending,
                iconName: pending
                    ? 'utility:clock'
                    : passed
                      ? 'utility:success'
                      : 'utility:error',
                iconVariant: pending ? '' : passed ? 'success' : 'error',
                badgeClass:
                    'test-result-badge ' +
                    (pending
                        ? 'test-pending'
                        : passed
                          ? 'test-pass'
                          : 'test-fail')
            };
        });
    }

    async handleRunTests() {
        this.isRunning = true;
        try {
            await runValidationTests({ jobId: this.recordId });
            await refreshApex(this._wiredResult);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Complete',
                    message: 'All randomness tests have been executed.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Failed',
                    message:
                        error?.body?.message ||
                        error?.message ||
                        'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isRunning = false;
        }
    }

    @api
    async refresh() {
        await refreshApex(this._wiredResult);
    }
}
