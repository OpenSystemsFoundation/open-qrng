import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAuditTrailDTO from '@salesforce/apex/SetupController.getAuditTrailDTO';
import {
    subscribeToQuantumEvents,
    unsubscribeFromQuantumEvents
} from 'c/qrngEventSubscription';
import { reduceErrors } from 'c/qrngUtils';

export default class QrngAuditTrail extends LightningElement {
    @track certificates = [];
    @track selectedCertId = null;
    @track loadError;

    _wiredResult;
    _eventSub;
    _modalFocused = false;

    connectedCallback() {
        this._eventSub = subscribeToQuantumEvents(() => {
            refreshApex(this._wiredResult);
        }, null);
    }

    disconnectedCallback() {
        unsubscribeFromQuantumEvents(this._eventSub);
    }

    renderedCallback() {
        // Move focus to the close button when the detail modal opens
        if (this.selectedCertId && !this._modalFocused) {
            const closeBtn = this.template.querySelector('[data-modal-close]');
            if (closeBtn) {
                this._modalFocused = true;
                closeBtn.focus();
            }
        }
    }

    @wire(getAuditTrailDTO)
    wiredTrail(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data) {
            this.loadError = undefined;
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
            this.loadError = reduceErrors(error);
        }
    }

    get hasCertificates() {
        return this.certificates && this.certificates.length > 0;
    }

    handleCertClick(event) {
        this.selectedCertId = event.currentTarget.dataset.id;
        this._modalFocused = false;
    }

    closeCertDetail() {
        this.selectedCertId = null;
        this._modalFocused = false;
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.closeCertDetail();
        }
    }
}
