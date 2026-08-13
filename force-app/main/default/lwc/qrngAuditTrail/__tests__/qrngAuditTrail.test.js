import { createElement } from '@lwc/engine-dom';
import QrngAuditTrail from 'c/qrngAuditTrail';

jest.mock(
    '@salesforce/apex/SetupController.getAuditTrailDTO',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

import getAuditTrailDTO from '@salesforce/apex/SetupController.getAuditTrailDTO';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

const MOCK_AUDIT_DATA = [
    {
        recordId: 'a01xx000001',
        name: 'CERT-0001',
        externalJobId: 'job_abc123',
        backend: 'test_backend',
        status: 'Certified',
        purpose: 'Lead assignment',
        chshSValue: null,
        tampered: false,
        createdDate: '2026-03-17T10:00:00.000Z'
    },
    {
        recordId: 'a01xx000002',
        name: 'CERT-0002',
        externalJobId: 'job_def456',
        backend: 'test_backend',
        status: 'Failed',
        purpose: 'Audit sampling',
        chshSValue: 2.5,
        tampered: false,
        createdDate: '2026-03-16T09:00:00.000Z'
    }
];

describe('c-qrng-audit-trail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent() {
        const element = createElement('c-qrng-audit-trail', {
            is: QrngAuditTrail
        });
        document.body.appendChild(element);
        return element;
    }

    it('shows empty state message when wire returns empty array', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit([]);
        await flushPromises();

        const emptyMsg = element.shadowRoot.querySelector(
            '.slds-text-color_weak'
        );
        expect(emptyMsg).not.toBeNull();
        expect(emptyMsg.textContent).toContain(
            'No fairness certificates have been issued yet'
        );
    });

    it('renders timeline items when wire returns data', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        const timelineItems =
            element.shadowRoot.querySelectorAll('.timeline-item');
        expect(timelineItems).toHaveLength(2);
    });

    it('computes iconName as standard:task2 for Certified, standard:incident for Failed', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        const icons = element.shadowRoot.querySelectorAll('lightning-icon');
        // First cert is Certified -> standard:task2
        expect(icons[0].iconName).toBe('standard:task2');
        // Second cert is Failed -> standard:incident
        expect(icons[1].iconName).toBe('standard:incident');
    });

    it('computes badgeClass with slds-theme_success for Certified', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        const badges = element.shadowRoot.querySelectorAll('lightning-badge');
        // First cert is Certified
        expect(badges[0].className).toContain('slds-theme_success');
        // Second cert is Failed
        expect(badges[1].className).toContain('slds-theme_error');
    });

    it('computes isQuantumCertified as true when CHSH > 2.0', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        // Second cert has chshSValue = 2.5, so it should show Quantum Certified
        const quantumBadges =
            element.shadowRoot.querySelectorAll('.quantum-badge');
        expect(quantumBadges).toHaveLength(1);
        expect(quantumBadges[0].textContent).toBe('Quantum Certified');
    });

    it('click on cert name sets selectedCertId (opens modal)', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        const certLink = element.shadowRoot.querySelector(
            'button[data-id="a01xx000001"]'
        );
        expect(certLink).not.toBeNull();

        certLink.click();
        await flushPromises();

        // Modal should now be visible
        const modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal).not.toBeNull();

        // Embedded certificate component should receive the selectedCertId
        const certComponent = element.shadowRoot.querySelector(
            'c-qrng-fairness-certificate'
        );
        expect(certComponent).not.toBeNull();
        expect(certComponent.certificateId).toBe('a01xx000001');
    });

    it('closeCertDetail clears selectedCertId', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        // Open modal
        const certLink = element.shadowRoot.querySelector(
            'button[data-id="a01xx000001"]'
        );
        certLink.click();
        await flushPromises();

        let modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal).not.toBeNull();

        // Close modal via close button
        const closeBtn = element.shadowRoot.querySelector('.slds-modal__close');
        closeBtn.click();
        await flushPromises();

        modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal).toBeNull();
    });

    it('modal has dialog semantics, assistive text, and Escape closes it', async () => {
        const element = createComponent();

        getAuditTrailDTO.emit(MOCK_AUDIT_DATA);
        await flushPromises();

        element.shadowRoot
            .querySelector('button[data-id="a01xx000001"]')
            .click();
        await flushPromises();

        const modal = element.shadowRoot.querySelector('.slds-modal');
        expect(modal.getAttribute('role')).toBe('dialog');
        expect(modal.getAttribute('aria-modal')).toBe('true');
        expect(modal.getAttribute('aria-labelledby')).toBeTruthy();

        const heading = element.shadowRoot.querySelector(
            '.slds-modal__header h2'
        );
        expect(heading).not.toBeNull();
        expect(heading.getAttribute('id')).toBeTruthy();

        // Close button carries assistive text
        const closeBtn = element.shadowRoot.querySelector('[data-modal-close]');
        const assistive = closeBtn.querySelector('.slds-assistive-text');
        expect(assistive).not.toBeNull();
        expect(assistive.textContent).toContain('Close');

        // Focus moved to the close button on open
        expect(element.shadowRoot.activeElement).toBe(closeBtn);

        // Escape closes the modal
        modal.dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
        );
        await flushPromises();
        expect(element.shadowRoot.querySelector('.slds-modal')).toBeNull();
    });

    it('renders inline error state when the wire errors (not console-only)', async () => {
        const element = createComponent();

        getAuditTrailDTO.error({ message: 'trail unavailable' });
        await flushPromises();

        const errorBox = element.shadowRoot.querySelector(
            '[data-testid="audit-trail-error"]'
        );
        expect(errorBox).not.toBeNull();
        expect(errorBox.textContent).toContain('trail unavailable');
    });
});
