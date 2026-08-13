import { createElement } from '@lwc/engine-dom';
import QrngAssignmentTable from 'c/qrngAssignmentTable';

jest.mock(
    '@salesforce/apex/SetupController.getAssignmentsDTO',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

import getAssignmentsDTO from '@salesforce/apex/SetupController.getAssignmentsDTO';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

// Namespace-free DTO shape returned by SetupController.getAssignmentsDTO
const MOCK_ASSIGNMENTS = [
    {
        name: 'ASSIGN-0001',
        index: 0,
        recordId: '001xx000001',
        assigneeId: '005xx000001',
        randomValue: '0110'
    },
    {
        name: 'ASSIGN-0002',
        index: 1,
        recordId: '001xx000002',
        assigneeId: '005xx000002',
        randomValue: '1001'
    }
];

describe('c-qrng-assignment-table', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent(props = {}) {
        const element = createElement('c-qrng-assignment-table', {
            is: QrngAssignmentTable
        });
        Object.assign(element, props);
        document.body.appendChild(element);
        return element;
    }

    it('shows "No assignments found" when wire returns empty array', async () => {
        const element = createComponent({ jobId: 'job_empty' });

        getAssignmentsDTO.emit([]);
        await flushPromises();

        const emptyMsg = element.shadowRoot.querySelector(
            '.slds-text-color_weak'
        );
        expect(emptyMsg).not.toBeNull();
        expect(emptyMsg.textContent).toContain(
            'No assignments found for this job'
        );
    });

    it('renders lightning-datatable when wire returns data', async () => {
        const element = createComponent({ jobId: 'job_abc123' });

        getAssignmentsDTO.emit(MOCK_ASSIGNMENTS);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
    });

    it('has correct columns keyed to DTO fields', async () => {
        const element = createComponent({ jobId: 'job_abc123' });

        getAssignmentsDTO.emit(MOCK_ASSIGNMENTS);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable.columns).toHaveLength(5);
        expect(datatable.columns[0].label).toBe('#');
        expect(datatable.columns[0].fieldName).toBe('index');
        expect(datatable.columns[1].label).toBe('Assignment');
        expect(datatable.columns[1].fieldName).toBe('name');
        expect(datatable.columns[2].label).toBe('Record ID');
        expect(datatable.columns[2].fieldName).toBe('recordId');
        expect(datatable.columns[3].label).toBe('Assigned To');
        expect(datatable.columns[3].fieldName).toBe('assigneeId');
        expect(datatable.columns[4].label).toBe('Random Value');
        expect(datatable.columns[4].fieldName).toBe('randomValue');
    });

    it('passes correct data to datatable', async () => {
        const element = createComponent({ jobId: 'job_abc123' });

        getAssignmentsDTO.emit(MOCK_ASSIGNMENTS);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable.data).toEqual(MOCK_ASSIGNMENTS);
        expect(datatable.data).toHaveLength(2);
        expect(datatable.keyField).toBe('index');
    });

    it('shows spinner only while the wire is in flight', async () => {
        const element = createComponent({ jobId: 'job_abc123' });
        await flushPromises();

        // In flight: neither data nor error yet
        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).not.toBeNull();

        getAssignmentsDTO.emit([]);
        await flushPromises();

        // Resolved: spinner gone, empty state shown
        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).toBeNull();
        expect(element.shadowRoot.textContent).toContain(
            'No assignments found'
        );
    });

    it('does not spin forever when no job id is provided', async () => {
        const element = createComponent();
        await flushPromises();

        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).toBeNull();
        expect(element.shadowRoot.textContent).toContain(
            'No assignments found'
        );
    });

    it('renders inline error state when the wire errors', async () => {
        const element = createComponent({ jobId: 'job_abc123' });

        getAssignmentsDTO.error({ message: 'Query failed' });
        await flushPromises();

        const errorBox = element.shadowRoot.querySelector(
            '[data-testid="assignment-table-error"]'
        );
        expect(errorBox).not.toBeNull();
        expect(errorBox.textContent).toContain('Query failed');
        expect(
            element.shadowRoot.querySelector('lightning-spinner')
        ).toBeNull();
        expect(
            element.shadowRoot.querySelector('lightning-datatable')
        ).toBeNull();
    });

    it('supports @api recordId as fallback job id', async () => {
        createComponent({ recordId: 'a03xxRECORD0001' });
        await flushPromises();

        expect(getAssignmentsDTO.getLastConfig()).toEqual({
            jobId: 'a03xxRECORD0001'
        });
    });

    it('jobId wins over recordId when both are set', async () => {
        createComponent({
            recordId: 'a03xxRECORD0001',
            jobId: 'a03xxJOBID00001'
        });
        await flushPromises();

        expect(getAssignmentsDTO.getLastConfig()).toEqual({
            jobId: 'a03xxJOBID00001'
        });
    });
});
