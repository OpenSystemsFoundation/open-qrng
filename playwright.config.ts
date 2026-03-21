import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright E2E configuration for QuantumFair (open-qrng).
 *
 * These tests run against a Salesforce scratch org with the package deployed.
 * The base URL and auth are configured via environment variables:
 *   - SF_LOGIN_URL: Salesforce login URL (e.g. https://test.salesforce.com)
 *   - SF_INSTANCE_URL: Scratch org instance URL
 *   - SF_ACCESS_TOKEN: OAuth access token for the scratch org
 *   - SF_APP_PAGE: Lightning app page path (default: /lightning/n/OpenSF__QuantumFair)
 *
 * For local development without a scratch org, tests use mock mode
 * which renders static HTML fixtures that mirror the LWC structure.
 */
export default defineConfig({
    testDir: './e2e',
    fullyParallel: true,
    forbidOnly: !!process.env.CI,
    retries: process.env.CI ? 2 : 0,
    workers: process.env.CI ? 1 : undefined,
    reporter: process.env.CI
        ? [
              ['html', { open: 'never', outputFolder: 'playwright-report' }],
              ['json', { outputFile: 'playwright-report/results.json' }],
              ['github']
          ]
        : [['html', { open: 'on-failure' }]],
    timeout: 120_000,
    expect: {
        timeout: 15_000
    },
    use: {
        baseURL:
            process.env.SF_INSTANCE_URL || 'http://localhost:3000',
        trace: 'on-first-retry',
        screenshot: 'only-on-failure',
        video: 'retain-on-failure',
        actionTimeout: 10_000
    },
    projects: [
        {
            name: 'chromium',
            use: { ...devices['Desktop Chrome'] }
        },
        {
            name: 'firefox',
            use: { ...devices['Desktop Firefox'] }
        },
        {
            name: 'mobile-chrome',
            use: { ...devices['Pixel 5'] }
        }
    ],
    /* Local dev server for mock mode */
    webServer: process.env.SF_INSTANCE_URL
        ? undefined
        : {
              command: 'npx serve e2e/fixtures -l 3000 -s',
              port: 3000,
              reuseExistingServer: !process.env.CI
          }
});
