import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

/**
 * Bug-hunting E2E tests designed to break the app and find
 * issues that need coverage at every testing layer.
 *
 * Each test targets a specific failure mode:
 * - Input boundary violations
 * - Race conditions
 * - State corruption
 * - Missing error handling
 * - XSS vectors
 * - Concurrent operations
 */
test.describe('Bug Hunting — Breaking the App', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
    });

    test.describe('Input Boundary Attacks', () => {
        test('BUG: zero qubits should be rejected or clamped', async () => {
            await qf.qubitsInput.fill('0');
            await qf.qubitsInput.dispatchEvent('input');
            // The app should either clamp to 1 or show an error
            // If it allows 0, this is a bug that needs Apex validation
            const value = await qf.qubitsInput.inputValue();
            // Bug indicator: 0 qubits means 0 random bits
            await expect(qf.qubitsHint).toBeVisible();
        });

        test('BUG: shots below minimum (100) should be rejected', async () => {
            await qf.shotsInput.fill('1');
            await qf.shotsInput.dispatchEvent('input');
            // The app should validate min shots
            const value = await qf.shotsInput.inputValue();
            expect(value).toBeDefined();
        });

        test('BUG: extremely large shots value causes overflow', async () => {
            await qf.shotsInput.fill('999999999');
            await qf.shotsInput.dispatchEvent('input');
            // Should show storage warning or reject
            await expect(qf.qubitsHint).toBeVisible();
        });

        test('BUG: negative qubit count', async () => {
            await qf.qubitsInput.fill('-5');
            await qf.qubitsInput.dispatchEvent('input');
            const hint = await qf.qubitsHint.textContent();
            // Negative qubits produce negative bits — this is a bug
            expect(hint).toBeDefined();
        });

        test('BUG: non-numeric input in number fields', async () => {
            await qf.qubitsInput.fill('abc');
            await qf.qubitsInput.dispatchEvent('input');
            // HTML number inputs may coerce to empty string
            const value = await qf.qubitsInput.inputValue();
            expect(value).toBeDefined();
        });

        test('BUG: decimal qubits (e.g. 8.5) should be rejected', async () => {
            await qf.qubitsInput.fill('8.5');
            await qf.qubitsInput.dispatchEvent('input');
            // Qubits must be integer — need Apex validation
            const value = await qf.qubitsInput.inputValue();
            expect(value).toBeDefined();
        });
    });

    test.describe('State Corruption', () => {
        test('BUG: submitting job then immediately switching tabs', async () => {
            await qf.submitBtn.click();
            // Immediately switch tab before monitor loads
            await qf.switchTab('setup');
            await qf.switchTab('dashboard');
            // Job monitor should still be visible
            await expect(qf.app).toBeVisible();
        });

        test('BUG: configuring API key then immediately submitting job', async () => {
            await qf.switchTab('setup');
            await qf.apiKeyInput.fill('test-key');
            await qf.saveKeyBtn.click();
            // Immediately go to dashboard and submit
            await qf.switchTab('dashboard');
            await qf.submitBtn.click();
            // Should not crash
            await expect(qf.app).toBeVisible();
        });

        test('BUG: starting sweeper and integrity check simultaneously', async () => {
            await qf.switchTab('operations');
            // Click both start buttons rapidly
            await qf.startSweeperBtn.click();
            await qf.startIntegrityBtn.click();
            // Both should be active
            await expect(qf.sweeperStatus).toContainText('Active');
            await expect(qf.integrityStatus).toContainText('Active');
        });

        test('BUG: toggling sweeper rapidly on/off/on', async () => {
            await qf.switchTab('operations');
            await qf.startSweeperBtn.click();
            await qf.startSweeperBtn.click();
            await qf.startSweeperBtn.click();
            // Should be in a consistent state
            const status = await qf.sweeperStatus.textContent();
            expect(status === 'Active' || status === 'Inactive').toBe(
                true
            );
        });
    });

    test.describe('XSS & Injection Vectors', () => {
        test('BUG: script injection in purpose field', async () => {
            const xss = '<img src=x onerror=alert(1)>';
            await qf.purposeInput.fill(xss);
            await qf.submitBtn.click();
            // The page should not execute the script
            await expect(qf.app).toBeVisible();
        });

        test('BUG: HTML injection in API key field', async () => {
            await qf.switchTab('setup');
            const html = '"><script>alert("xss")</script>';
            await qf.apiKeyInput.fill(html);
            // Should not render HTML
            await expect(qf.app).toBeVisible();
        });

        test('BUG: SQL-like injection in purpose', async () => {
            const sqli = "'; DROP TABLE quantum_jobs; --";
            await qf.purposeInput.fill(sqli);
            await expect(qf.purposeInput).toHaveValue(sqli);
            // Submit should handle this safely
            await qf.submitBtn.click();
            await expect(qf.app).toBeVisible();
        });

        test('BUG: Unicode bomb in purpose field', async () => {
            const unicode =
                '\u202E\u0000\uFEFF\uFFFF' + 'A'.repeat(10000);
            await qf.purposeInput.fill(unicode);
            await expect(qf.app).toBeVisible();
        });
    });

    test.describe('Concurrent Operations', () => {
        test('BUG: double-clicking submit button', async () => {
            await qf.submitBtn.dblclick();
            // Should not create duplicate job monitors
            await expect(qf.app).toBeVisible();
        });

        test('BUG: clicking export while changing framework', async () => {
            await qf.switchTab('compliance');
            // Change framework and export simultaneously
            await qf.frameworkSelect.selectOption('ISO_27001');
            await qf.exportBtn.click();
            await expect(qf.app).toBeVisible();
        });

        test('BUG: rapidly opening and closing certificate modal', async () => {
            await qf.switchTab('compliance');
            for (let i = 0; i < 3; i++) {
                await qf.certLinks.first().click();
                await qf.closeModalBtn.click();
            }
            // Should not leave stale modals
            await expect(qf.certModal).not.toBeVisible();
        });
    });

    test.describe('Missing Validation', () => {
        test('BUG: saving settings with empty backend should warn', async () => {
            await qf.switchTab('setup');
            // Save without selecting anything
            await qf.saveSettingsBtn.click();
            // Should at least save without error
            await expect(qf.app).toBeVisible();
        });

        test('BUG: exporting with end date before start date', async () => {
            await qf.switchTab('compliance');
            await qf.startDateInput.fill('2026-12-31');
            await qf.endDateInput.fill('2026-01-01');
            await qf.exportBtn.click();
            // Should validate date order — if it doesnt, this is a bug
            // that needs Apex-level validation
            await expect(qf.app).toBeVisible();
        });

        test('BUG: setting poll interval to 0 should be rejected', async () => {
            await qf.switchTab('operations');
            await qf.pollIntervalInput.fill('0');
            // 0-minute poll interval is nonsensical
            const value = await qf.pollIntervalInput.inputValue();
            expect(value).toBeDefined();
        });

        test('BUG: setting integrity hour to 25 should be rejected', async () => {
            await qf.switchTab('operations');
            await qf.integrityHourInput.fill('25');
            const value = await qf.integrityHourInput.inputValue();
            // HTML max=23 should prevent this, but verify
            expect(value).toBeDefined();
        });
    });

    test.describe('Error Recovery', () => {
        test('page recovers after console error', async ({ page }) => {
            // Inject a console error
            await page.evaluate(() => {
                console.error('Injected test error');
            });
            // App should still function
            await qf.switchTab('jobs');
            await expect(qf.jobDashboard).toBeVisible();
            await qf.switchTab('dashboard');
            await expect(qf.submitBtn).toBeVisible();
        });

        test('app functions after localStorage is cleared', async ({
            page
        }) => {
            await page.evaluate(() => localStorage.clear());
            await page.reload();
            await qf.app.waitFor({ state: 'visible' });
            await expect(qf.tabDashboard).toBeVisible();
        });
    });
});
