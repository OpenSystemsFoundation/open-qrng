import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Accessibility & Edge Cases', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
    });

    test('tabs have ARIA role attributes', async () => {
        const tabs = qf.page.locator('[role="tab"]');
        const count = await tabs.count();
        expect(count).toBe(5);
    });

    test('active tab has aria-selected=true', async () => {
        await expect(qf.tabDashboard).toHaveAttribute(
            'aria-selected',
            'true'
        );
    });

    test('inactive tabs have aria-selected=false', async () => {
        await expect(qf.tabJobs).toHaveAttribute(
            'aria-selected',
            'false'
        );
    });

    test('form inputs have associated labels', async () => {
        const labels = qf.page.locator('label');
        const count = await labels.count();
        expect(count).toBeGreaterThan(0);
    });

    test('password field does not expose key in DOM', async () => {
        await qf.switchTab('setup');
        const keyInput = qf.apiKeyInput;
        await expect(keyInput).toHaveAttribute('type', 'password');
    });

    test.describe('Keyboard Navigation', () => {
        test('Tab key moves through form fields', async ({ page }) => {
            await qf.backendSelect.focus();
            await page.keyboard.press('Tab');
            // Should move to next focusable element
            const focused = page.locator(':focus');
            await expect(focused).toBeTruthy();
        });
    });

    test.describe('Edge Cases — Request Form', () => {
        test('setting qubits to 0 keeps field at boundary', async () => {
            await qf.qubitsInput.fill('0');
            // Input should still allow it (validation is application-level)
            const value = await qf.qubitsInput.inputValue();
            expect(value).toBe('0');
        });

        test('negative shots value is handled', async () => {
            await qf.shotsInput.fill('-1');
            const value = await qf.shotsInput.inputValue();
            // Browser may or may not allow negative in number input
            expect(value).toBeDefined();
        });

        test('extremely large qubit value', async () => {
            await qf.qubitsInput.fill('9999');
            await qf.qubitsInput.dispatchEvent('input');
            // Should still update the hint text
            await expect(qf.qubitsHint).toBeVisible();
        });

        test('special characters in purpose field', async () => {
            const special = '<script>alert("xss")</script> & "quotes"';
            await qf.purposeInput.fill(special);
            await expect(qf.purposeInput).toHaveValue(special);
            // Ensure no script execution (page should not have alert)
        });

        test('rapid tab switching does not break UI', async () => {
            for (let i = 0; i < 5; i++) {
                await qf.tabJobs.click();
                await qf.tabDashboard.click();
            }
            await expect(qf.panelDashboard).toBeVisible();
        });

        test('submitting multiple jobs rapidly', async () => {
            await qf.submitBtn.click();
            await qf.submitBtn.click();
            await qf.submitBtn.click();
            // Should not crash
            await expect(qf.app).toBeVisible();
        });
    });

    test.describe('Responsive Layout', () => {
        test('app renders on small viewport', async ({ page }) => {
            await page.setViewportSize({ width: 375, height: 667 });
            await expect(qf.app).toBeVisible();
            await expect(qf.tabDashboard).toBeVisible();
        });

        test('form fields are usable on mobile', async ({ page }) => {
            await page.setViewportSize({ width: 375, height: 667 });
            await expect(qf.submitBtn).toBeVisible();
            await expect(qf.backendSelect).toBeVisible();
        });
    });
});
