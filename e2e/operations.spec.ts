import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Operations Tab - Background Jobs & Health', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
        await qf.switchTab('operations');
    });

    test.describe('Job Sweeper', () => {
        test('shows inactive status by default', async () => {
            await expect(qf.sweeperStatus).toContainText('Inactive');
        });

        test('shows Start Sweeper button', async () => {
            await expect(qf.startSweeperBtn).toBeVisible();
            await expect(qf.startSweeperBtn).toContainText(
                'Start Sweeper'
            );
        });

        test('poll interval input is editable when inactive', async () => {
            await expect(qf.pollIntervalInput).toBeEnabled();
        });

        test('starting sweeper changes status to Active', async () => {
            await qf.startSweeperBtn.click();
            await expect(qf.sweeperStatus).toContainText('Active');
        });

        test('starting sweeper disables poll interval input', async () => {
            await qf.startSweeperBtn.click();
            await expect(qf.pollIntervalInput).toBeDisabled();
        });

        test('starting sweeper changes button to Stop', async () => {
            await qf.startSweeperBtn.click();
            await expect(qf.startSweeperBtn).toContainText(
                'Stop Sweeper'
            );
        });

        test('stopping sweeper returns to inactive', async () => {
            await qf.startSweeperBtn.click();
            await qf.startSweeperBtn.click();
            await expect(qf.sweeperStatus).toContainText('Inactive');
            await expect(qf.pollIntervalInput).toBeEnabled();
        });

        test('poll interval has correct min/max', async () => {
            await expect(qf.pollIntervalInput).toHaveAttribute('min', '1');
            await expect(qf.pollIntervalInput).toHaveAttribute(
                'max',
                '60'
            );
        });
    });

    test.describe('Integrity Verification', () => {
        test('shows inactive status by default', async () => {
            await expect(qf.integrityStatus).toContainText('Inactive');
        });

        test('starting integrity check changes status', async () => {
            await qf.startIntegrityBtn.click();
            await expect(qf.integrityStatus).toContainText('Active');
        });

        test('starting integrity check disables hour input', async () => {
            await qf.startIntegrityBtn.click();
            await expect(qf.integrityHourInput).toBeDisabled();
        });

        test('integrity hour has correct range', async () => {
            await expect(qf.integrityHourInput).toHaveAttribute(
                'min',
                '0'
            );
            await expect(qf.integrityHourInput).toHaveAttribute(
                'max',
                '23'
            );
        });

        test('toggle integrity check on and off', async () => {
            await qf.startIntegrityBtn.click();
            await expect(qf.integrityStatus).toContainText('Active');
            await qf.startIntegrityBtn.click();
            await expect(qf.integrityStatus).toContainText('Inactive');
        });
    });

    test.describe('Health Monitor', () => {
        test('renders health table', async () => {
            await expect(qf.healthTable).toBeVisible();
        });

        test('shows backend health rows', async () => {
            const rowCount = await qf.healthRows.count();
            expect(rowCount).toBeGreaterThan(0);
        });

        test('shows Refresh Backend Health button', async () => {
            await expect(qf.refreshHealthBtn).toBeVisible();
        });

        test('shows Verify All Backends button', async () => {
            await expect(qf.verifyAllBtn).toBeVisible();
        });

        test('health rows contain backend names', async () => {
            await expect(qf.healthRows.first()).toContainText(
                'ibm_brisbane'
            );
        });

        test('shows fidelity scores', async () => {
            await expect(qf.healthRows.first()).toContainText('96.2%');
        });

        test('shows online status badge', async () => {
            const statusBadge =
                qf.healthRows.first().locator('.badge-success');
            await expect(statusBadge).toContainText('online');
        });

        test('shows S-value for verified backends', async () => {
            const svalueLink = qf.page.locator(
                '[data-testid="svalue-link"]'
            );
            await expect(svalueLink.first()).toContainText('2.74');
        });

        test('shows individual Verify buttons', async () => {
            const verifyBtns = qf.page.locator(
                '[data-testid="verify-backend-btn"]'
            );
            const count = await verifyBtns.count();
            expect(count).toBeGreaterThanOrEqual(2);
        });
    });
});
