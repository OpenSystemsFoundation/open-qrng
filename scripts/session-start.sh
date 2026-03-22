#!/bin/bash
# Claude Code Web — SessionStart hook
# Installs required tooling and authenticates Salesforce on session start.

set -euo pipefail

echo "[session-start] Setting up QuantumFair dev environment..."

# ---------------------------------------------------------------------------
# 1. Salesforce CLI (sf)
# ---------------------------------------------------------------------------
if ! command -v sf &>/dev/null; then
  echo "[session-start] Installing Salesforce CLI..."
  npm install -g @salesforce/cli
else
  echo "[session-start] Salesforce CLI already installed: $(sf --version)"
fi

# ---------------------------------------------------------------------------
# 2. GitHub CLI (gh)
# ---------------------------------------------------------------------------
if ! command -v gh &>/dev/null; then
  echo "[session-start] Installing GitHub CLI..."
  apt-get update -qq && apt-get install -y -qq gh
else
  echo "[session-start] GitHub CLI already installed: $(gh --version | head -1)"
fi

# ---------------------------------------------------------------------------
# 3. Playwright + Chromium (headless browser for scratch org login)
# ---------------------------------------------------------------------------
if ! npx playwright --version &>/dev/null 2>&1; then
  echo "[session-start] Installing Playwright globally..."
  npm install -g playwright
fi

if [ ! -d "$HOME/.cache/ms-playwright" ] || [ -z "$(ls -A "$HOME/.cache/ms-playwright" 2>/dev/null)" ]; then
  echo "[session-start] Installing Chromium for Playwright..."
  npx playwright install --with-deps chromium
else
  echo "[session-start] Playwright Chromium already installed."
fi

# ---------------------------------------------------------------------------
# 4. DNS check bypass (required in sandboxed environments)
# ---------------------------------------------------------------------------
export SFDX_DISABLE_DNS_CHECK=true
echo "[session-start] SFDX_DISABLE_DNS_CHECK=true"

# ---------------------------------------------------------------------------
# 5. Authenticate Dev Hub from SFDX_AUTH_URL if available
# ---------------------------------------------------------------------------
if [ -n "${SFDX_AUTH_URL:-}" ]; then
  echo "[session-start] Authenticating Dev Hub via SFDX_AUTH_URL..."
  echo "$SFDX_AUTH_URL" | sf org login sfdx-url \
    --sfdx-url-stdin \
    --set-default \
    --set-default-dev-hub \
    --alias DevHub 2>&1 || echo "[session-start] WARNING: Dev Hub auth failed"
  echo "[session-start] Dev Hub authenticated."
else
  echo "[session-start] No SFDX_AUTH_URL found — skipping Dev Hub auth."
  echo "[session-start] Set SFDX_AUTH_URL env var to enable automatic authentication."
fi

# ---------------------------------------------------------------------------
# 6. npm install (project dependencies including local Playwright)
# ---------------------------------------------------------------------------
if [ ! -d "node_modules" ]; then
  echo "[session-start] Installing npm dependencies..."
  npm install
else
  echo "[session-start] node_modules already present."
fi

echo "[session-start] Setup complete."
