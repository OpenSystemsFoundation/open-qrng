import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Cross-Tab Integration Flows', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
    });

    test('full job submission flow: submit → monitor → jobs tab', async ({
        page
    }) => {
        // 1. Submit a job from Dashboard
        await qf.submitJob({
            backend: 'ibm_brisbane',
            qubits: 16,
            shots: 2048,
            purpose: 'E2E integration test'
        });
        await expect(qf.jobMonitors).toBeVisible();

        // 2. Wait for completion
        await page.waitForTimeout(3500);
        await expect(qf.jobStatusBadge).toContainText('Completed');

        // 3. Switch to Jobs tab and verify dashboard
        await qf.switchTab('jobs');
        await expect(qf.jobDashboard).toBeVisible();
    });

    test('setup flow: configure key → verify connection → save settings', async () => {
        // 1. Go to Setup
        await qf.switchTab('setup');

        // 2. Enter API key
        await qf.apiKeyInput.fill('my-test-quantum-key');
        await qf.saveKeyBtn.click();
        await qf.waitForToast('API Key Saved');

        // 3. Verify configured state
        await expect(qf.apiKeyConfigured).toBeVisible();
        await expect(qf.connectionBadge).toBeVisible();

        // 4. Save settings
        await qf.settingsShotsInput.fill('4096');
        await qf.complianceEmailInput.fill('compliance@test.com');
        await qf.saveSettingsBtn.click();
        await qf.waitForToast('Settings saved');
    });

    test('operations flow: start sweeper → check health → verify backend', async () => {
        await qf.switchTab('operations');

        // 1. Start sweeper
        await qf.startSweeperBtn.click();
        await expect(qf.sweeperStatus).toContainText('Active');

        // 2. Health table is visible
        await expect(qf.healthTable).toBeVisible();
        const rows = await qf.healthRows.count();
        expect(rows).toBeGreaterThan(0);

        // 3. Stop sweeper
        await qf.startSweeperBtn.click();
        await expect(qf.sweeperStatus).toContainText('Inactive');
    });

    test('compliance flow: view audit → open certificate → verify → export', async () => {
        await qf.switchTab('compliance');

        // 1. Audit trail is visible
        await expect(qf.auditTimeline).toBeVisible();

        // 2. Open certificate modal
        await qf.openCertificateModal(0);
        await expect(qf.certStatusBadge).toBeVisible();

        // 3. Verify integrity
        await qf.verifyIntegrityBtn.click();
        await expect(qf.verifyIntegrityBtn).toBeEnabled({
            timeout: 5000
        });

        // 4. Close modal
        await qf.closeCertificateModal();

        // 5. Export evidence
        await qf.exportBtn.click();
        await qf.waitForToast('Evidence exported');
    });

    test('navigating away and back preserves tab content', async () => {
        // Submit a job on dashboard
        await qf.submitBtn.click();
        await expect(qf.jobMonitors).toBeVisible();

        // Go to setup and back
        await qf.switchTab('setup');
        await expect(qf.panelSetup).toBeVisible();

        await qf.switchTab('dashboard');
        // Job monitors should still be visible
        await expect(qf.jobMonitors).toBeVisible();
    });

    test('full app walkthrough without errors', async ({ page }) => {
        // Dashboard
        await expect(qf.submitBtn).toBeVisible();

        // Jobs
        await qf.switchTab('jobs');
        await expect(qf.jobsTable).toBeVisible();

        // Setup
        await qf.switchTab('setup');
        await expect(qf.apiKeyInput).toBeVisible();

        // Operations
        await qf.switchTab('operations');
        await expect(qf.healthTable).toBeVisible();

        // Compliance
        await qf.switchTab('compliance');
        await expect(qf.auditTimeline).toBeVisible();

        // No console errors
        const errors: string[] = [];
        page.on('pageerror', (err) => errors.push(err.message));
        await qf.switchTab('dashboard');
        expect(errors).toHaveLength(0);
    });
});
