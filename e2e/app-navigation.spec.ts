import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('App Navigation & Layout', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
    });

    test('renders app container with title', async () => {
        await expect(qf.app).toBeVisible();
        await expect(qf.app).toContainText('QuantumFair');
    });

    test('renders all 5 tabs', async () => {
        await expect(qf.tabDashboard).toBeVisible();
        await expect(qf.tabJobs).toBeVisible();
        await expect(qf.tabSetup).toBeVisible();
        await expect(qf.tabOperations).toBeVisible();
        await expect(qf.tabCompliance).toBeVisible();
    });

    test('Dashboard tab is active by default', async () => {
        await expect(qf.tabDashboard).toHaveAttribute(
            'aria-selected',
            'true'
        );
        await expect(qf.panelDashboard).toBeVisible();
    });

    test('switching to Jobs tab shows job dashboard', async () => {
        await qf.switchTab('jobs');
        await expect(qf.tabJobs).toHaveAttribute(
            'aria-selected',
            'true'
        );
        await expect(qf.panelJobs).toBeVisible();
        await expect(qf.panelDashboard).not.toBeVisible();
    });

    test('switching to Setup tab shows setup panel', async () => {
        await qf.switchTab('setup');
        await expect(qf.panelSetup).toBeVisible();
    });

    test('switching to Operations tab shows operations panel', async () => {
        await qf.switchTab('operations');
        await expect(qf.panelOperations).toBeVisible();
    });

    test('switching to Compliance tab shows compliance panel', async () => {
        await qf.switchTab('compliance');
        await expect(qf.panelCompliance).toBeVisible();
    });

    test('can navigate through all tabs sequentially', async () => {
        const tabs = [
            'jobs',
            'setup',
            'operations',
            'compliance',
            'dashboard'
        ] as const;
        for (const tab of tabs) {
            await qf.switchTab(tab);
        }
        await expect(qf.panelDashboard).toBeVisible();
    });

    test('only one tab panel is visible at a time', async ({ page }) => {
        await qf.switchTab('setup');
        const visiblePanels = await page
            .locator('.tab-content.active')
            .count();
        expect(visiblePanels).toBe(1);
    });
});
