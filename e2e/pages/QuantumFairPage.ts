import { type Page, type Locator, expect } from '@playwright/test';

/**
 * Page Object Model for the QuantumFair app.
 * Works against both the mock HTML fixture and a real Salesforce org.
 */
export class QuantumFairPage {
    readonly page: Page;

    // App container
    readonly app: Locator;

    // Tabs
    readonly tabDashboard: Locator;
    readonly tabJobs: Locator;
    readonly tabSetup: Locator;
    readonly tabOperations: Locator;
    readonly tabCompliance: Locator;

    // Panels
    readonly panelDashboard: Locator;
    readonly panelJobs: Locator;
    readonly panelSetup: Locator;
    readonly panelOperations: Locator;
    readonly panelCompliance: Locator;

    // Dashboard - Request Form
    readonly backendSelect: Locator;
    readonly qubitsInput: Locator;
    readonly shotsInput: Locator;
    readonly purposeInput: Locator;
    readonly submitBtn: Locator;
    readonly circuitCanvas: Locator;
    readonly qubitsHint: Locator;
    readonly shotsHint: Locator;
    readonly backendInfo: Locator;
    readonly storageBar: Locator;
    readonly storageFill: Locator;

    // Dashboard - Job Monitor
    readonly jobMonitors: Locator;
    readonly jobStatusBadge: Locator;
    readonly jobProgress: Locator;
    readonly dismissBtn: Locator;

    // Jobs Tab
    readonly jobDashboard: Locator;
    readonly refreshJobsBtn: Locator;
    readonly jobFilter: Locator;
    readonly jobsTable: Locator;
    readonly jobRows: Locator;

    // Setup Tab
    readonly apiKeyInput: Locator;
    readonly saveKeyBtn: Locator;
    readonly apiKeyConfigured: Locator;
    readonly testConnectionBtn: Locator;
    readonly changeKeyBtn: Locator;
    readonly connectionBadge: Locator;
    readonly crnInput: Locator;
    readonly autoDetectBtn: Locator;
    readonly settingsBackendSelect: Locator;
    readonly settingsShotsInput: Locator;
    readonly complianceEmailInput: Locator;
    readonly saveSettingsBtn: Locator;

    // Operations Tab
    readonly sweeperStatus: Locator;
    readonly startSweeperBtn: Locator;
    readonly pollIntervalInput: Locator;
    readonly integrityStatus: Locator;
    readonly startIntegrityBtn: Locator;
    readonly integrityHourInput: Locator;
    readonly refreshHealthBtn: Locator;
    readonly verifyAllBtn: Locator;
    readonly healthTable: Locator;
    readonly healthRows: Locator;

    // Compliance Tab
    readonly auditTimeline: Locator;
    readonly auditItems: Locator;
    readonly certLinks: Locator;
    readonly frameworkSelect: Locator;
    readonly startDateInput: Locator;
    readonly endDateInput: Locator;
    readonly exportBtn: Locator;

    // Certificate Modal
    readonly certModal: Locator;
    readonly closeModalBtn: Locator;
    readonly certStatusBadge: Locator;
    readonly visualHash: Locator;
    readonly verifyIntegrityBtn: Locator;
    readonly validationResults: Locator;

    // Toast
    readonly toast: Locator;

    constructor(page: Page) {
        this.page = page;
        this.app = page.locator('[data-testid="quantum-fair-app"]');

        // Tabs
        this.tabDashboard = page.locator('[data-testid="tab-dashboard"]');
        this.tabJobs = page.locator('[data-testid="tab-jobs"]');
        this.tabSetup = page.locator('[data-testid="tab-setup"]');
        this.tabOperations = page.locator('[data-testid="tab-operations"]');
        this.tabCompliance = page.locator('[data-testid="tab-compliance"]');

        // Panels
        this.panelDashboard = page.locator('[data-testid="panel-dashboard"]');
        this.panelJobs = page.locator('[data-testid="panel-jobs"]');
        this.panelSetup = page.locator('[data-testid="panel-setup"]');
        this.panelOperations = page.locator(
            '[data-testid="panel-operations"]'
        );
        this.panelCompliance = page.locator(
            '[data-testid="panel-compliance"]'
        );

        // Dashboard - Request Form
        this.backendSelect = page.locator('[data-testid="backend-select"]');
        this.qubitsInput = page.locator('[data-testid="qubits-input"]');
        this.shotsInput = page.locator('[data-testid="shots-input"]');
        this.purposeInput = page.locator('[data-testid="purpose-input"]');
        this.submitBtn = page.locator('[data-testid="submit-btn"]');
        this.circuitCanvas = page.locator('[data-testid="circuit-canvas"]');
        this.qubitsHint = page.locator('[data-testid="qubits-hint"]');
        this.shotsHint = page.locator('[data-testid="shots-hint"]');
        this.backendInfo = page.locator('[data-testid="backend-info"]');
        this.storageBar = page.locator('[data-testid="storage-bar"]');
        this.storageFill = page.locator('[data-testid="storage-fill"]');

        // Dashboard - Job Monitor
        this.jobMonitors = page.locator('[data-testid="job-monitors"]');
        this.jobStatusBadge = page.locator(
            '[data-testid="job-status-badge"]'
        );
        this.jobProgress = page.locator('[data-testid="job-progress"]');
        this.dismissBtn = page.locator('[data-testid="dismiss-btn"]');

        // Jobs Tab
        this.jobDashboard = page.locator('[data-testid="job-dashboard"]');
        this.refreshJobsBtn = page.locator(
            '[data-testid="refresh-jobs-btn"]'
        );
        this.jobFilter = page.locator('[data-testid="job-filter"]');
        this.jobsTable = page.locator('[data-testid="jobs-table"]');
        this.jobRows = page.locator('[data-testid="job-row"]');

        // Setup Tab
        this.apiKeyInput = page.locator('[data-testid="api-key-input"]');
        this.saveKeyBtn = page.locator('[data-testid="save-key-btn"]');
        this.apiKeyConfigured = page.locator(
            '[data-testid="api-key-configured"]'
        );
        this.testConnectionBtn = page.locator(
            '[data-testid="test-connection-btn"]'
        );
        this.changeKeyBtn = page.locator('[data-testid="change-key-btn"]');
        this.connectionBadge = page.locator(
            '[data-testid="connection-badge"]'
        );
        this.crnInput = page.locator('[data-testid="crn-input"]');
        this.autoDetectBtn = page.locator(
            '[data-testid="auto-detect-btn"]'
        );
        this.settingsBackendSelect = page.locator(
            '[data-testid="settings-backend-select"]'
        );
        this.settingsShotsInput = page.locator(
            '[data-testid="settings-shots-input"]'
        );
        this.complianceEmailInput = page.locator(
            '[data-testid="compliance-email-input"]'
        );
        this.saveSettingsBtn = page.locator(
            '[data-testid="save-settings-btn"]'
        );

        // Operations Tab
        this.sweeperStatus = page.locator(
            '[data-testid="sweeper-status"]'
        );
        this.startSweeperBtn = page.locator(
            '[data-testid="start-sweeper-btn"]'
        );
        this.pollIntervalInput = page.locator(
            '[data-testid="poll-interval-input"]'
        );
        this.integrityStatus = page.locator(
            '[data-testid="integrity-status"]'
        );
        this.startIntegrityBtn = page.locator(
            '[data-testid="start-integrity-btn"]'
        );
        this.integrityHourInput = page.locator(
            '[data-testid="integrity-hour-input"]'
        );
        this.refreshHealthBtn = page.locator(
            '[data-testid="refresh-health-btn"]'
        );
        this.verifyAllBtn = page.locator('[data-testid="verify-all-btn"]');
        this.healthTable = page.locator('[data-testid="health-table"]');
        this.healthRows = page.locator('[data-testid="health-row"]');

        // Compliance Tab
        this.auditTimeline = page.locator(
            '[data-testid="audit-timeline"]'
        );
        this.auditItems = page.locator('[data-testid="audit-item"]');
        this.certLinks = page.locator('[data-testid="cert-link"]');
        this.frameworkSelect = page.locator(
            '[data-testid="framework-select"]'
        );
        this.startDateInput = page.locator(
            '[data-testid="start-date-input"]'
        );
        this.endDateInput = page.locator('[data-testid="end-date-input"]');
        this.exportBtn = page.locator('[data-testid="export-btn"]');

        // Certificate Modal
        this.certModal = page.locator('[data-testid="cert-modal"]');
        this.closeModalBtn = page.locator(
            '[data-testid="close-modal-btn"]'
        );
        this.certStatusBadge = page.locator(
            '[data-testid="cert-status-badge"]'
        );
        this.visualHash = page.locator('[data-testid="visual-hash"]');
        this.verifyIntegrityBtn = page.locator(
            '[data-testid="verify-integrity-btn"]'
        );
        this.validationResults = page.locator(
            '[data-testid="validation-results"]'
        );

        // Toast
        this.toast = page.locator('[data-testid="toast"]');
    }

    async goto() {
        await this.page.goto('/');
        await this.app.waitFor({ state: 'visible' });
    }

    async switchTab(
        tab: 'dashboard' | 'jobs' | 'setup' | 'operations' | 'compliance'
    ) {
        const tabLocator = {
            dashboard: this.tabDashboard,
            jobs: this.tabJobs,
            setup: this.tabSetup,
            operations: this.tabOperations,
            compliance: this.tabCompliance
        }[tab];
        await tabLocator.click();
        const panelLocator = {
            dashboard: this.panelDashboard,
            jobs: this.panelJobs,
            setup: this.panelSetup,
            operations: this.panelOperations,
            compliance: this.panelCompliance
        }[tab];
        await expect(panelLocator).toBeVisible();
    }

    async submitJob(options?: {
        backend?: string;
        qubits?: number;
        shots?: number;
        purpose?: string;
    }) {
        if (options?.backend) {
            await this.backendSelect.selectOption(options.backend);
        }
        if (options?.qubits) {
            await this.qubitsInput.fill(String(options.qubits));
        }
        if (options?.shots) {
            await this.shotsInput.fill(String(options.shots));
        }
        if (options?.purpose) {
            await this.purposeInput.fill(options.purpose);
        }
        await this.submitBtn.click();
    }

    async waitForToast(expectedText?: string) {
        await this.toast.first().waitFor({ state: 'visible' });
        if (expectedText) {
            await expect(this.toast.first()).toContainText(expectedText);
        }
    }

    async openCertificateModal(index: number = 0) {
        await this.certLinks.nth(index).click();
        await expect(this.certModal).toBeVisible();
    }

    async closeCertificateModal() {
        await this.closeModalBtn.click();
        await expect(this.certModal).not.toBeVisible();
    }
}
