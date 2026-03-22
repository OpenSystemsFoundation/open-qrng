import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Request Form - Job Submission', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
    });

    test('renders all form fields', async () => {
        await expect(qf.backendSelect).toBeVisible();
        await expect(qf.qubitsInput).toBeVisible();
        await expect(qf.shotsInput).toBeVisible();
        await expect(qf.purposeInput).toBeVisible();
        await expect(qf.submitBtn).toBeVisible();
    });

    test('renders circuit canvas', async () => {
        await expect(qf.circuitCanvas).toBeVisible();
    });

    test('has correct default values', async () => {
        await expect(qf.qubitsInput).toHaveValue('8');
        await expect(qf.shotsInput).toHaveValue('1024');
    });

    test('backend select has least busy as first option', async () => {
        const firstOption = qf.backendSelect.locator('option').first();
        await expect(firstOption).toHaveText('Least Busy');
        await expect(firstOption).toHaveAttribute(
            'value',
            '__least_busy__'
        );
    });

    test('shows backend info when specific backend selected', async () => {
        await expect(qf.backendInfo).not.toBeVisible();
        await qf.backendSelect.selectOption('ibm_brisbane');
        await expect(qf.backendInfo).toBeVisible();
    });

    test('hides backend info when Least Busy selected', async () => {
        await qf.backendSelect.selectOption('ibm_brisbane');
        await expect(qf.backendInfo).toBeVisible();
        await qf.backendSelect.selectOption('__least_busy__');
        await expect(qf.backendInfo).not.toBeVisible();
    });

    test('updates random bits calculation when qubits change', async () => {
        await qf.qubitsInput.fill('16');
        await qf.qubitsInput.dispatchEvent('input');
        await expect(qf.qubitsHint).toContainText('16,384');
    });

    test('updates random bits calculation when shots change', async () => {
        await qf.shotsInput.fill('2048');
        await qf.shotsInput.dispatchEvent('input');
        await expect(qf.qubitsHint).toContainText('16,384');
    });

    test('storage bar updates on large values', async () => {
        await qf.qubitsInput.fill('127');
        await qf.qubitsInput.dispatchEvent('input');
        await qf.shotsInput.fill('8192');
        await qf.shotsInput.dispatchEvent('input');
        // Should show higher storage utilization
        const fillWidth = await qf.storageFill.evaluate(
            (el) => el.style.width
        );
        expect(parseFloat(fillWidth)).toBeGreaterThan(12);
    });

    test('submitting job shows job monitor', async () => {
        await qf.submitJob({ purpose: 'E2E test job' });
        await expect(qf.jobMonitors).toBeVisible();
    });

    test('submitting job shows success toast', async () => {
        await qf.submitBtn.click();
        await qf.waitForToast('Job submitted');
    });

    test('job monitor shows progress indicator', async () => {
        await qf.submitBtn.click();
        await expect(qf.jobMonitors).toBeVisible();
        await expect(qf.jobProgress).toBeVisible();
    });

    test('job status transitions from Running to Completed', async ({
        page
    }) => {
        await qf.submitBtn.click();
        await expect(qf.jobStatusBadge).toContainText('Running');
        // Wait for simulated completion (3 seconds in fixture)
        await page.waitForTimeout(3500);
        await expect(qf.jobStatusBadge).toContainText('Completed');
    });

    test('can dismiss completed job monitor', async ({ page }) => {
        await qf.submitBtn.click();
        await expect(qf.jobMonitors).toBeVisible();
        await qf.dismissBtn.click();
        await expect(qf.jobMonitors).not.toBeVisible();
    });

    test('purpose field accepts long text', async () => {
        const longText =
            'Quarterly randomized assignment for team leads across all departments for fair distribution of on-call duties during Q2 2026.';
        await qf.purposeInput.fill(longText);
        await expect(qf.purposeInput).toHaveValue(longText);
    });

    test('qubits input respects min/max constraints', async () => {
        await expect(qf.qubitsInput).toHaveAttribute('min', '1');
        await expect(qf.qubitsInput).toHaveAttribute('max', '127');
    });

    test('shots input respects min/max constraints', async () => {
        await expect(qf.shotsInput).toHaveAttribute('min', '100');
        await expect(qf.shotsInput).toHaveAttribute('max', '8192');
    });

    test('submit button text is correct', async () => {
        await expect(qf.submitBtn).toContainText(
            'Generate Quantum Random Numbers'
        );
    });
});
