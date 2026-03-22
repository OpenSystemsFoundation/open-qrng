import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Compliance Tab - Audit Trail & Export', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
        await qf.switchTab('compliance');
    });

    test.describe('Audit Trail', () => {
        test('renders audit trail section', async () => {
            await expect(qf.auditTimeline).toBeVisible();
        });

        test('shows audit items', async () => {
            const count = await qf.auditItems.count();
            expect(count).toBeGreaterThan(0);
        });

        test('audit items have certificate links', async () => {
            const count = await qf.certLinks.count();
            expect(count).toBeGreaterThan(0);
        });

        test('shows Quantum Certified badges', async () => {
            const certBadges = qf.page.locator(
                '[data-testid="cert-badge"]'
            );
            await expect(certBadges.first()).toContainText(
                'Quantum Certified'
            );
        });

        test('shows Tampered badge for compromised certificates', async () => {
            const badges = qf.page.locator(
                '[data-testid="cert-badge"]'
            );
            let foundTampered = false;
            const count = await badges.count();
            for (let i = 0; i < count; i++) {
                const text = await badges.nth(i).textContent();
                if (text?.includes('Tampered')) {
                    foundTampered = true;
                    break;
                }
            }
            expect(foundTampered).toBe(true);
        });

        test('clicking certificate opens modal', async () => {
            await qf.openCertificateModal(0);
            await expect(qf.certModal).toBeVisible();
        });

        test('certificate modal shows status badge', async () => {
            await qf.openCertificateModal(0);
            await expect(qf.certStatusBadge).toBeVisible();
        });

        test('certificate modal shows visual hash canvas', async () => {
            await qf.openCertificateModal(0);
            await expect(qf.visualHash).toBeVisible();
        });

        test('certificate modal shows job details', async () => {
            await qf.openCertificateModal(0);
            await expect(
                qf.page.locator('[data-testid="cert-job-id"]')
            ).toBeVisible();
            await expect(
                qf.page.locator('[data-testid="cert-backend"]')
            ).toBeVisible();
            await expect(
                qf.page.locator('[data-testid="cert-purpose"]')
            ).toBeVisible();
        });

        test('certificate modal shows integrity hashes', async () => {
            await qf.openCertificateModal(0);
            await expect(
                qf.page.locator('[data-testid="hash-raw"]')
            ).toBeVisible();
            await expect(
                qf.page.locator('[data-testid="hash-debiased"]')
            ).toBeVisible();
            await expect(
                qf.page.locator('[data-testid="hash-assignment"]')
            ).toBeVisible();
        });

        test('certificate modal shows validation results', async () => {
            await qf.openCertificateModal(0);
            await expect(qf.validationResults).toBeVisible();
            await expect(qf.validationResults).toContainText('Frequency');
            await expect(qf.validationResults).toContainText('Runs Test');
            await expect(qf.validationResults).toContainText(
                'Chi-Squared'
            );
        });

        test('Verify Integrity button works', async () => {
            await qf.openCertificateModal(0);
            await qf.verifyIntegrityBtn.click();
            // Button should show "Verifying..." state
            await expect(qf.verifyIntegrityBtn).toBeDisabled();
            // Wait for verification to complete
            await expect(qf.verifyIntegrityBtn).toBeEnabled({
                timeout: 5000
            });
        });

        test('closing modal hides it', async () => {
            await qf.openCertificateModal(0);
            await qf.closeCertificateModal();
            await expect(qf.certModal).not.toBeVisible();
        });

        test('clicking backdrop closes modal', async () => {
            await qf.openCertificateModal(0);
            // Click the overlay (backdrop) area
            await qf.certModal.click({ position: { x: 5, y: 5 } });
            await expect(qf.certModal).not.toBeVisible();
        });
    });

    test.describe('Compliance Export', () => {
        test('renders framework select', async () => {
            await expect(qf.frameworkSelect).toBeVisible();
        });

        test('framework select has all options', async () => {
            const options = qf.frameworkSelect.locator('option');
            await expect(options).toHaveCount(6);
        });

        test('renders date inputs with defaults', async () => {
            await expect(qf.startDateInput).toBeVisible();
            await expect(qf.endDateInput).toBeVisible();
            // Should have default values
            const startVal = await qf.startDateInput.inputValue();
            const endVal = await qf.endDateInput.inputValue();
            expect(startVal).toBeTruthy();
            expect(endVal).toBeTruthy();
        });

        test('export button is visible', async () => {
            await expect(qf.exportBtn).toBeVisible();
            await expect(qf.exportBtn).toContainText('Export Evidence');
        });

        test('exporting with valid dates shows success', async () => {
            await qf.exportBtn.click();
            await qf.waitForToast('Evidence exported');
        });

        test('can select different frameworks', async () => {
            const frameworks = [
                'ISO_27001',
                'SOC_2',
                'NIST_800_90B',
                'GDPR',
                'EIDAS'
            ];
            for (const fw of frameworks) {
                await qf.frameworkSelect.selectOption(fw);
                await expect(qf.frameworkSelect).toHaveValue(fw);
            }
        });

        test('can change date range', async () => {
            await qf.startDateInput.fill('2026-01-01');
            await qf.endDateInput.fill('2026-03-31');
            await expect(qf.startDateInput).toHaveValue('2026-01-01');
            await expect(qf.endDateInput).toHaveValue('2026-03-31');
        });

        test('exporting without dates shows error', async ({ page }) => {
            await qf.startDateInput.fill('');
            await qf.endDateInput.fill('');
            await qf.exportBtn.click();
            await qf.waitForToast('Please select');
        });
    });
});
