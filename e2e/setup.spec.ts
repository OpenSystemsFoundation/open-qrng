import { test, expect } from '@playwright/test';
import { QuantumFairPage } from './pages/QuantumFairPage';

test.describe('Setup Tab - Connection & Settings', () => {
    let qf: QuantumFairPage;

    test.beforeEach(async ({ page }) => {
        qf = new QuantumFairPage(page);
        await qf.goto();
        await qf.switchTab('setup');
    });

    test('renders setup panel', async () => {
        await expect(
            qf.page.locator('[data-testid="setup-panel"]')
        ).toBeVisible();
    });

    test.describe('API Key Entry', () => {
        test('shows API key input field', async () => {
            await expect(qf.apiKeyInput).toBeVisible();
            await expect(qf.apiKeyInput).toHaveAttribute(
                'type',
                'password'
            );
        });

        test('shows Save Key button', async () => {
            await expect(qf.saveKeyBtn).toBeVisible();
        });

        test('saving empty key shows error toast', async () => {
            await qf.saveKeyBtn.click();
            await qf.waitForToast('Please enter');
        });

        test('saving valid key transitions to configured state', async () => {
            await qf.apiKeyInput.fill('test-api-key-12345');
            await qf.saveKeyBtn.click();
            await qf.waitForToast('API Key Saved');
            await expect(qf.apiKeyConfigured).toBeVisible();
        });

        test('configured state shows connection badge', async () => {
            await qf.apiKeyInput.fill('test-api-key-12345');
            await qf.saveKeyBtn.click();
            await expect(qf.connectionBadge).toBeVisible();
        });

        test('Change button returns to API key entry', async () => {
            await qf.apiKeyInput.fill('test-api-key-12345');
            await qf.saveKeyBtn.click();
            await qf.changeKeyBtn.click();
            await expect(qf.apiKeyInput).toBeVisible();
        });
    });

    test.describe('Connection Testing', () => {
        test.beforeEach(async () => {
            // Configure API key first
            await qf.apiKeyInput.fill('test-api-key-12345');
            await qf.saveKeyBtn.click();
        });

        test('Test Connection button is visible', async () => {
            await expect(qf.testConnectionBtn).toBeVisible();
        });

        test('CRN input is visible', async () => {
            await expect(qf.crnInput).toBeVisible();
        });

        test('Auto-detect button is visible', async () => {
            await expect(qf.autoDetectBtn).toBeVisible();
        });

        test('can enter CRN manually', async () => {
            const crn =
                'crn:v1:bluemix:public:quantum-computing:us-east:a/123:456::';
            await qf.crnInput.fill(crn);
            await expect(qf.crnInput).toHaveValue(crn);
        });
    });

    test.describe('Settings Panel', () => {
        test('renders backend select', async () => {
            await expect(qf.settingsBackendSelect).toBeVisible();
        });

        test('renders shots input with default value', async () => {
            await expect(qf.settingsShotsInput).toBeVisible();
            await expect(qf.settingsShotsInput).toHaveValue('1024');
        });

        test('renders compliance email input', async () => {
            await expect(qf.complianceEmailInput).toBeVisible();
        });

        test('Save Settings button is visible', async () => {
            await expect(qf.saveSettingsBtn).toBeVisible();
        });

        test('saving settings shows success toast', async () => {
            await qf.saveSettingsBtn.click();
            await qf.waitForToast('Settings saved');
        });

        test('can change default shots value', async () => {
            await qf.settingsShotsInput.fill('2048');
            await expect(qf.settingsShotsInput).toHaveValue('2048');
        });

        test('can enter compliance email', async () => {
            await qf.complianceEmailInput.fill('admin@example.com');
            await expect(qf.complianceEmailInput).toHaveValue(
                'admin@example.com'
            );
        });
    });

    test.describe('Usage Stats', () => {
        test('shows total jobs stat', async () => {
            await expect(
                qf.page.locator('[data-testid="stat-total-jobs"]')
            ).toContainText('42');
        });

        test('shows completed jobs stat', async () => {
            await expect(
                qf.page.locator('[data-testid="stat-completed-jobs"]')
            ).toContainText('38');
        });

        test('shows certificates stat', async () => {
            await expect(
                qf.page.locator('[data-testid="stat-certificates"]')
            ).toContainText('35');
        });
    });
});
