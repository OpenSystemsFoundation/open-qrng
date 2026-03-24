import { LightningElement, api, wire, track } from 'lwc';
import getAssignments from '@salesforce/apex/SetupController.getAssignments';

const COLUMNS = [
    {
        label: '#',
        fieldName: 'Assignment_Index__c',
        type: 'number',
        fixedWidth: 60
    },
    { label: 'Assignment', fieldName: 'Name', type: 'text' },
    { label: 'Record ID', fieldName: 'Assigned_Record_ID__c', type: 'text' },
    { label: 'Assigned To', fieldName: 'Assigned_To_ID__c', type: 'text' },
    { label: 'Random Value', fieldName: 'Random_Value__c', type: 'text' }
];

export default class QrngAssignmentTable extends LightningElement {
    @api jobId;
    @track assignments = [];
    @track isLoading = true;
    columns = COLUMNS;

    @wire(getAssignments, { jobId: '$jobId' })
    wiredAssignments({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.assignments = data;
        } else if (error) {
            console.error('Error loading assignments:', error);
        }
    }

    get hasAssignments() {
        return this.assignments && this.assignments.length > 0;
    }
}
