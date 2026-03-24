import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAuditTrailDTO from '@salesforce/apex/SetupController.getAuditTrailDTO';
import {
    subscribeToQuantumEvents,
    unsubscribeFromQuantumEvents
} from 'c/qrngEventSubscription';

export default class QrngAuditTrail extends LightningElement {
    @track certificates = [];
    @track selectedCertId = null;

    _wiredResult;
    _eventSub;

    connectedCallback() {
        this._eventSub = subscribeToQuantumEvents(() => {
            refreshApex(this._wiredResult);
        }, null);
    }

    disconnectedCallback() {
        unsubscribeFromQuantumEvents(this._eventSub);
    }

    @wire(getAuditTrailDTO)
    wiredTrail(result) {
        this._wiredResult = result;
        if (result.data) {
            this.certificates = result.data.map((cert) => ({
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
        } else if (result.error) {
            console.error('Error loading audit trail:', result.error);
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
