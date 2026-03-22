#!/usr/bin/env node
/**
 * Headless Salesforce scratch org login via Playwright.
 *
 * Flow:
 *   1. Authenticate the SF CLI to a Dev Hub (if not already authenticated)
 *   2. Create a scratch org
 *   3. Generate a login URL for the scratch org
 *   4. Open the scratch org in a headless browser and capture the session
 *
 * Usage:
 *   # Interactive Dev Hub login (opens browser for OAuth):
 *   node scripts/playwright/scratch-org-login.mjs
 *
 *   # With existing Dev Hub alias:
 *   node scripts/playwright/scratch-org-login.mjs --devhub MyDevHub
 *
 *   # Skip scratch org creation (reuse existing):
 *   node scripts/playwright/scratch-org-login.mjs --alias my-scratch --skip-create
 *
 *   # With JWT auth (CI-friendly, fully headless):
 *   node scripts/playwright/scratch-org-login.mjs \
 *     --client-id <connected-app-id> \
 *     --jwt-key-file /path/to/server.key \
 *     --devhub-username admin@devhub.org
 *
 * Environment variables (alternative to flags):
 *   SF_DEVHUB_USERNAME  — Dev Hub username for JWT auth
 *   SF_CLIENT_ID        — Connected App consumer key
 *   SF_JWT_KEY_FILE     — Path to JWT private key
 */

import { chromium } from "playwright";
import { execSync, spawn } from "node:child_process";
import { parseArgs } from "node:util";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------
const { values: args } = parseArgs({
  options: {
    alias: { type: "string", default: "qrng-dev" },
    devhub: { type: "string", default: "" },
    "devhub-username": {
      type: "string",
      default: process.env.SF_DEVHUB_USERNAME || "",
    },
    "client-id": {
      type: "string",
      default: process.env.SF_CLIENT_ID || "",
    },
    "jwt-key-file": {
      type: "string",
      default: process.env.SF_JWT_KEY_FILE || "",
    },
    "scratch-def": {
      type: "string",
      default: "config/project-scratch-def.json",
    },
    "skip-create": { type: "boolean", default: false },
    headless: { type: "boolean", default: true },
    headed: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
  strict: false,
});

if (args.help) {
  console.log(`Usage: node scripts/playwright/scratch-org-login.mjs [options]

Options:
  --alias <name>          Scratch org alias (default: qrng-dev)
  --devhub <alias>        Dev Hub alias (if already authenticated)
  --devhub-username <u>   Dev Hub username for JWT auth
  --client-id <id>        Connected App consumer key for JWT
  --jwt-key-file <path>   Path to JWT private key file
  --scratch-def <path>    Scratch org definition file
  --skip-create           Skip scratch org creation; reuse --alias
  --headed                Show the browser (default: headless)
  --help                  Show this help message
`);
  process.exit(0);
}

const HEADLESS = args.headed ? false : args.headless;
const SCRATCH_ALIAS = args.alias;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function sf(cmd, opts = {}) {
  const full = `sf ${cmd}`;
  console.log(`  $ ${full}`);
  return execSync(full, {
    encoding: "utf-8",
    stdio: opts.silent ? "pipe" : ["inherit", "pipe", "pipe"],
    ...opts,
  }).trim();
}

function sfJson(cmd) {
  const raw = sf(`${cmd} --json`, { silent: true });
  return JSON.parse(raw);
}

function hasOrg(alias) {
  try {
    const result = sfJson(`org display -o ${alias}`);
    return result.status === 0;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Authenticate Dev Hub
// ---------------------------------------------------------------------------
async function authenticateDevHub() {
  console.log("\n🔑 Step 1: Authenticating Dev Hub...\n");

  // If a Dev Hub alias was provided and it's already authenticated, use it
  if (args.devhub) {
    try {
      sf(`org display -o ${args.devhub}`, { silent: true });
      console.log(`  Dev Hub "${args.devhub}" is already authenticated.`);
      return args.devhub;
    } catch {
      console.log(`  Dev Hub "${args.devhub}" not found, will authenticate...`);
    }
  }

  // JWT flow (fully headless, ideal for CI)
  if (args["devhub-username"] && args["client-id"] && args["jwt-key-file"]) {
    const keyFile = resolve(args["jwt-key-file"]);
    if (!existsSync(keyFile)) {
      throw new Error(`JWT key file not found: ${keyFile}`);
    }
    sf(
      `org login jwt ` +
        `--client-id ${args["client-id"]} ` +
        `--jwt-key-file "${keyFile}" ` +
        `--username ${args["devhub-username"]} ` +
        `--set-default-dev-hub ` +
        `--alias DevHub`
    );
    return "DevHub";
  }

  // Playwright-assisted OAuth login (headless browser automation)
  console.log("  Using Playwright to automate Dev Hub OAuth login...");
  console.log(
    "  NOTE: You will need to provide credentials interactively.\n"
  );

  // Start the SF CLI login flow and capture the auth URL
  const authUrl = await new Promise((resolveUrl, reject) => {
    const child = spawn("sf", ["org", "login", "web", "--json"], {
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (data) => {
      stdout += data.toString();
    });
    child.stderr.on("data", (data) => {
      stderr += data.toString();
      // SF CLI prints the login URL to stderr
      const match = stderr.match(
        /(https:\/\/login\.salesforce\.com\/[^\s]+)/
      );
      if (match) {
        resolveUrl(match[1]);
      }
    });

    child.on("close", (code) => {
      if (code !== 0 && !stdout.includes('"status": 0')) {
        reject(new Error(`sf org login web failed: ${stderr}`));
      }
    });

    // Timeout after 30s if we don't get a URL
    setTimeout(() => reject(new Error("Timed out waiting for login URL")), 30000);
  });

  console.log(`  Auth URL obtained: ${authUrl.slice(0, 60)}...`);

  // Use Playwright to navigate and complete OAuth
  const browser = await chromium.launch({ headless: HEADLESS });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    await page.goto(authUrl, { waitUntil: "networkidle" });

    // Wait for the Salesforce login form
    await page.waitForSelector("#username", { timeout: 15000 });

    // Prompt for credentials via stdin
    const username = await promptInput("  Dev Hub username: ");
    const password = await promptInput("  Dev Hub password: ");

    await page.fill("#username", username);
    await page.fill("#password", password);
    await page.click("#Login");

    // Handle possible MFA / approval screens
    try {
      // Wait for either the OAuth approval page or the redirect
      await page.waitForURL(
        (url) =>
          url.pathname.includes("/setup/secur/RemoteAccessAuthorizationPage") ||
          url.href.includes("localhost"),
        { timeout: 30000 }
      );

      // If it's the approval page, click Allow
      if (
        page
          .url()
          .includes("/setup/secur/RemoteAccessAuthorizationPage")
      ) {
        console.log("  Approving OAuth access...");
        await page.click("#oaapprove");
      }
    } catch {
      // May have redirected directly — that's fine
    }

    // Wait for the CLI to pick up the callback
    await page.waitForURL((url) => url.href.includes("localhost"), {
      timeout: 30000,
    });

    console.log("  OAuth login completed successfully.");
  } finally {
    await browser.close();
  }

  // Set as default Dev Hub
  try {
    sf("config set target-dev-hub=DevHub", { silent: true });
  } catch {
    // Non-critical
  }

  return "DevHub";
}

// ---------------------------------------------------------------------------
// Step 2 — Create Scratch Org
// ---------------------------------------------------------------------------
function createScratchOrg(devhubAlias) {
  console.log("\n📦 Step 2: Creating scratch org...\n");

  if (args["skip-create"]) {
    if (hasOrg(SCRATCH_ALIAS)) {
      console.log(
        `  Reusing existing scratch org "${SCRATCH_ALIAS}".`
      );
      return;
    }
    console.log(
      `  --skip-create specified but "${SCRATCH_ALIAS}" not found. Creating...`
    );
  }

  const defFile = resolve(args["scratch-def"]);
  if (!existsSync(defFile)) {
    throw new Error(`Scratch org definition not found: ${defFile}`);
  }

  sf(
    `org create scratch ` +
      `-f ${defFile} ` +
      `-a ${SCRATCH_ALIAS} ` +
      `-v ${devhubAlias} ` +
      `-d -y 7`
  );

  console.log(`  Scratch org "${SCRATCH_ALIAS}" created.`);
}

// ---------------------------------------------------------------------------
// Step 3 — Headless Login to Scratch Org
// ---------------------------------------------------------------------------
async function loginToScratchOrg() {
  console.log("\n🌐 Step 3: Logging in to scratch org via Playwright...\n");

  // Get the front-door login URL
  const result = sfJson(`org open -o ${SCRATCH_ALIAS} --url-only`);
  const loginUrl = result.result.url;
  console.log(`  Front-door URL: ${loginUrl.slice(0, 80)}...`);

  const browser = await chromium.launch({ headless: HEADLESS });
  const context = await browser.newContext();
  const page = await context.newPage();

  try {
    // Navigate to the front-door URL (auto-authenticates)
    await page.goto(loginUrl, { waitUntil: "networkidle" });

    // Verify we landed on a Salesforce page
    await page.waitForSelector(
      'body[class*="sfdcBody"], div.slds-global-header, #oneHeader',
      { timeout: 30000 }
    );

    const currentUrl = page.url();
    console.log(`  Logged in successfully.`);
    console.log(`  Current URL: ${currentUrl}`);

    // Extract session info from cookies
    const cookies = await context.cookies();
    const sidCookie = cookies.find((c) => c.name === "sid");

    if (sidCookie) {
      console.log(`  Session ID captured (sid cookie present).`);
    }

    // Take a screenshot as proof
    const screenshotPath = resolve("scripts/playwright/login-screenshot.png");
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.log(`  Screenshot saved: ${screenshotPath}`);

    return {
      url: currentUrl,
      cookies,
      sessionId: sidCookie?.value,
    };
  } finally {
    await browser.close();
  }
}

// ---------------------------------------------------------------------------
// Step 4 — Deploy and Configure
// ---------------------------------------------------------------------------
function deployAndConfigure() {
  console.log("\n🚀 Step 4: Deploying source and assigning permissions...\n");

  try {
    sf(`project deploy start -o ${SCRATCH_ALIAS}`);
    console.log("  Source deployed.");
  } catch (e) {
    console.warn("  Deploy failed (may be OK if nothing to deploy):", e.message);
  }

  try {
    sf(`org assign permset -n QuantumFair_Admin -o ${SCRATCH_ALIAS}`);
    sf(`org assign permset -n QuantumFair_User -o ${SCRATCH_ALIAS}`);
    console.log("  Permission sets assigned.");
  } catch (e) {
    console.warn("  Permission set assignment failed:", e.message);
  }
}

// ---------------------------------------------------------------------------
// Stdin prompt helper
// ---------------------------------------------------------------------------
function promptInput(question) {
  return new Promise((resolve) => {
    process.stdout.write(question);
    process.stdin.resume();
    process.stdin.setEncoding("utf-8");
    process.stdin.once("data", (data) => {
      process.stdin.pause();
      resolve(data.toString().trim());
    });
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log("╔══════════════════════════════════════════════════════╗");
  console.log("║  QuantumFair — Scratch Org Setup (Playwright)       ║");
  console.log("╚══════════════════════════════════════════════════════╝");

  try {
    const devhub = await authenticateDevHub();
    createScratchOrg(devhub);
    const session = await loginToScratchOrg();
    deployAndConfigure();

    console.log("\n✅ Done! Scratch org is ready.\n");
    console.log(`  Alias:      ${SCRATCH_ALIAS}`);
    console.log(`  Org URL:    ${session.url}`);
    console.log(`  Session:    ${session.sessionId ? "Active" : "N/A"}`);
    console.log(`\n  Open in browser:  sf org open -o ${SCRATCH_ALIAS}`);
    console.log("");
  } catch (err) {
    console.error(`\n❌ Error: ${err.message}\n`);
    process.exit(1);
  }
}

main();
