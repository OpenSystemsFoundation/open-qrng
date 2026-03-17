import { createElement } from 'lwc';
import QrngJobMonitor from 'c/qrngJobMonitor';
import getJobDetails from '@salesforce/apex/QRNGSetupController.getJobDetails';
import { subscribe, onError } from 'lightning/empApi';

// Wire adapter for @wire-decorated property
jest.mock(
    '@salesforce/apex/QRNGSetupController.getJobDetails',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

// Imperative Apex mock
jest.mock(
    '@salesforce/apex/QRNGSetupController.getCertificateByJobId',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// refreshApex mock
jest.mock(
    '@salesforce/apex',
    () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
    { virtual: true }
);

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_JOB_RUNNING = {
    Id: '001xx000003DGb1',
    Name: 'QJ-0001',
    IBM_Job_ID__c: 'job123',
    Backend__c: 'ibm_kingston',
    Status__c: 'Running',
    Num_Qubits__c: 8,
    Shots__c: 1024
};

describe('c-qrng-job-monitor', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-job-monitor', {
            is: QrngJobMonitor
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('renders "No active job" message when no jobId and no wire data', async () => {
        const element = createComponent();

        // Do not emit wire data so job stays undefined
        await flushPromises();

        const message = element.shadowRoot.querySelector(
            '.slds-text-body_regular'
        );
        expect(message).not.toBeNull();
        expect(message.textContent).toContain('No active job');
    });

    it('renders job details when wire returns data', async () => {
        const element = createComponent({
            jobId: '001xx000003DGb1'
        });

        getJobDetails.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const details = element.shadowRoot.querySelectorAll(
            '.slds-dl_horizontal__detail'
        );
        const detailValues = Array.from(details).map((d) => d.textContent);
        expect(detailValues).toContain('QJ-0001');
        expect(detailValues).toContain('ibm_kingston');
    });

    it('shows progress indicator with correct current step', async () => {
        const element = createComponent({
            jobId: '001xx000003DGb1'
        });

        getJobDetails.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const progressIndicator = element.shadowRoot.querySelector(
            'lightning-progress-indicator'
        );
        expect(progressIndicator).not.toBeNull();
        expect(progressIndicator.currentStep).toBe('Running');

        const steps = element.shadowRoot.querySelectorAll(
            'lightning-progress-step'
        );
        expect(steps).toHaveLength(4);
    });

    it('subscribes to Platform Event channels on connectedCallback', async () => {
        createComponent({ jobId: '001xx000003DGb1' });
        await flushPromises();

        expect(subscribe).toHaveBeenCalledTimes(2);
        expect(subscribe.mock.calls[0][0]).toBe(
            '/event/OpenSF__QRNG_Complete__e'
        );
        expect(subscribe.mock.calls[1][0]).toBe(
            '/event/OpenSF__QRNG_Failed__e'
        );
        expect(onError).toHaveBeenCalledTimes(1);
    });

    it('shows spinner when job is in progress (status = Running)', async () => {
        const element = createComponent({
            jobId: '001xx000003DGb1'
        });

        getJobDetails.emit(MOCK_JOB_RUNNING);
        await flushPromises();

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
    });
});
