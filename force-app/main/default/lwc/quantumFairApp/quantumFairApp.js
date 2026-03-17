import { LightningElement, track } from 'lwc';

export default class QuantumFairApp extends LightningElement {
    @track activeJobId;
    @track activeCertificateId;

    handleJobSubmitted(event) {
        this.activeJobId = event.detail.jobId;
    }

    handleJobComplete(event) {
        this.activeCertificateId = event.detail.certificateId;
    }
}
