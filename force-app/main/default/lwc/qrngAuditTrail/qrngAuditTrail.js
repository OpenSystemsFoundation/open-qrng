import { LightningElement, wire, track } from 'lwc';
import getAuditTrail from '@salesforce/apex/QRNGSetupController.getAuditTrail';

export default class QrngAuditTrail extends LightningElement {
    @track certificates = [];
    @track selectedCertId = null;

    @wire(getAuditTrail)
    wiredTrail({ data, error }) {
        if (data) {
            this.certificates = data.map((cert) => ({
                ...cert,
                iconName:
                    cert.Status__c === 'Certified'
                        ? 'standard:task2'
                        : 'standard:incident',
                badgeClass:
                    cert.Status__c === 'Certified'
                        ? 'slds-badge slds-theme_success'
                        : 'slds-badge slds-theme_error',
                isQuantumCertified:
                    cert.CHSH_S_Value__c && cert.CHSH_S_Value__c > 2.0
            }));
        } else if (error) {
            console.error('Error loading audit trail:', error);
        }
    }

    get hasCertificates() {
        return this.certificates && this.certificates.length > 0;
    }

    handleCertClick(event) {
        this.selectedCertId = event.currentTarget.dataset.id;
    }

    closeCertDetail() {
        this.selectedCertId = null;
    }
}
