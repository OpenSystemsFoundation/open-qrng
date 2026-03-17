import { createElement } from 'lwc';
import QrngAssignmentTable from 'c/qrngAssignmentTable';

jest.mock(
    '@salesforce/apex/QRNGSetupController.getAssignments',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

import getAssignments from '@salesforce/apex/QRNGSetupController.getAssignments';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_ASSIGNMENTS = [
    {
        Id: 'a02xx000001',
        Name: 'ASSIGN-0001',
        Assignment_Index__c: 0,
        Assigned_Record_ID__c: '001xx000001',
        Assigned_To_ID__c: '005xx000001',
        Random_Value__c: '0110'
    },
    {
        Id: 'a02xx000002',
        Name: 'ASSIGN-0002',
        Assignment_Index__c: 1,
        Assigned_Record_ID__c: '001xx000002',
        Assigned_To_ID__c: '005xx000002',
        Random_Value__c: '1001'
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

        getAssignments.emit([]);
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

        getAssignments.emit(MOCK_ASSIGNMENTS);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable).not.toBeNull();
    });

    it('has correct columns (5 columns: #, Assignment, Record ID, Assigned To, Random Value)', async () => {
        const element = createComponent({ jobId: 'job_abc123' });

        getAssignments.emit(MOCK_ASSIGNMENTS);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable.columns).toHaveLength(5);
        expect(datatable.columns[0].label).toBe('#');
        expect(datatable.columns[1].label).toBe('Assignment');
        expect(datatable.columns[2].label).toBe('Record ID');
        expect(datatable.columns[3].label).toBe('Assigned To');
        expect(datatable.columns[4].label).toBe('Random Value');
    });

    it('passes correct data to datatable', async () => {
        const element = createComponent({ jobId: 'job_abc123' });

        getAssignments.emit(MOCK_ASSIGNMENTS);
        await flushPromises();

        const datatable = element.shadowRoot.querySelector(
            'lightning-datatable'
        );
        expect(datatable.data).toEqual(MOCK_ASSIGNMENTS);
        expect(datatable.data).toHaveLength(2);
        expect(datatable.keyField).toBe('Id');
    });
});
