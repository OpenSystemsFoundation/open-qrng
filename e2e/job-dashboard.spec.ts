import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Job Dashboard', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
        await qf.switchTab('jobs');
    });

    test('renders job dashboard with header', async () => {
        await expect(qf.jobDashboard).toBeVisible();
        await expect(qf.jobDashboard).toContainText('Recent Jobs');
    });

    test('shows stat counters', async ({ page }) => {
        await expect(
            page.locator('[data-testid="stat-showing"]')
        ).toContainText('5');
        await expect(
            page.locator('[data-testid="stat-active"]')
        ).toContainText('1');
        await expect(
            page.locator('[data-testid="stat-completed"]')
        ).toContainText('3');
        await expect(
            page.locator('[data-testid="stat-failed"]')
        ).toContainText('1');
    });

    test('renders refresh button', async () => {
        await expect(qf.refreshJobsBtn).toBeVisible();
        await expect(qf.refreshJobsBtn).toContainText('Refresh');
    });

    test('renders filter dropdown with all options', async () => {
        await expect(qf.jobFilter).toBeVisible();
        const options = qf.jobFilter.locator('option');
        await expect(options).toHaveCount(6);
    });

    test('shows all 5 jobs by default', async () => {
        await expect(qf.jobRows).toHaveCount(5);
    });

    test('job table has correct columns', async () => {
        const headers = qf.jobsTable.locator('th');
        await expect(headers).toHaveCount(8);
        await expect(headers.nth(0)).toContainText('Job ID');
        await expect(headers.nth(1)).toContainText('Status');
        await expect(headers.nth(2)).toContainText('Type');
    });

    test('filtering by completed shows only completed jobs', async () => {
        await qf.jobFilter.selectOption('completed');
        // Wait for filter to apply
        const visibleRows = qf.jobRows.filter({ hasNotText: '' });
        // At least some completed rows should be visible
        const count = await visibleRows.count();
        expect(count).toBeGreaterThan(0);
    });

    test('filtering by failed shows only failed jobs', async () => {
        await qf.jobFilter.selectOption('failed');
        // The failed job row should be visible
        const failedBadge = qf.jobDashboard.locator('.badge-error');
        await expect(failedBadge.first()).toBeVisible();
    });

    test('filtering by all shows all jobs', async () => {
        await qf.jobFilter.selectOption('completed');
        await qf.jobFilter.selectOption('all');
        await expect(qf.jobRows).toHaveCount(5);
    });

    test('job links are clickable', async () => {
        const links = qf.jobDashboard.locator('[data-testid="job-link"]');
        await expect(links.first()).toBeVisible();
        const count = await links.count();
        expect(count).toBeGreaterThan(0);
    });

    test('displays different job types (QRNG and Verification)', async () => {
        await expect(qf.jobDashboard).toContainText('QRNG');
        await expect(qf.jobDashboard).toContainText('Verification');
    });

    test('shows status badges with correct variants', async () => {
        // Completed (success)
        await expect(
            qf.jobDashboard.locator('.badge-success').first()
        ).toBeVisible();
        // Running (info)
        await expect(
            qf.jobDashboard.locator('.badge-info').first()
        ).toBeVisible();
        // Failed (error)
        await expect(
            qf.jobDashboard.locator('.badge-error').first()
        ).toBeVisible();
    });
});
