import { LightningElement, wire, track } from 'lwc';
import getAuditTrailDTO from '@salesforce/apex/QRNGSetupController.getAuditTrailDTO';

export default class QrngAuditTrail extends LightningElement {
    @track certificates = [];
    @track selectedCertId = null;

    @wire(getAuditTrailDTO)
    wiredTrail({ data, error }) {
        if (data) {
            this.certificates = data.map((cert) => ({
                ...cert,
                iconName: cert.tampered
                    ? 'standard:first_non_empty'
                    : cert.status === 'Certified'
                      ? 'standard:task2'
                      : 'standard:incident',
                badgeClass: cert.tampered
                    ? 'slds-badge slds-theme_warning'
                    : cert.status === 'Certified'
                      ? 'slds-badge slds-theme_success'
                      : 'slds-badge slds-theme_error',
                badgeLabel: cert.tampered ? 'Tampered' : cert.status,
                isQuantumCertified: cert.chshSValue && cert.chshSValue > 2.0
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
