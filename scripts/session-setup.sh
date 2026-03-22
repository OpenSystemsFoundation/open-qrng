#!/bin/bash
# QuantumFair — Claude Code Session Setup
#
# This script runs on every session start (new or resumed) in both
# local CLI and Claude Code on the web environments.
#
# It authenticates the Salesforce DevHub, creates/reuses a scratch org,
# deploys the project, assigns permission sets, and persists the org
# credentials as environment variables for the session.
#
# Required environment variables (set in Claude Code web environment settings):
#   SFDX_AUTH_URL  — DevHub SFDX auth URL (sfdx://...) for scratch org creation
#
# Optional environment variables:
#   SF_SCRATCH_ALIAS  — Scratch org alias (default: qrng-dev)
#   SF_SCRATCH_DAYS   — Scratch org duration in days (default: 7)
#   SKIP_SF_SETUP     — Set to "true" to skip Salesforce setup entirely

set -euo pipefail

# ── Skip if requested ─────────────────────────────────────────
if [ "${SKIP_SF_SETUP:-}" = "true" ]; then
    echo "SKIP_SF_SETUP=true — skipping Salesforce setup"
    exit 0
fi

# ── Install dependencies ──────────────────────────────────────
echo "=== Installing npm dependencies ==="
cd "$CLAUDE_PROJECT_DIR"
npm install --prefer-offline --no-audit 2>/dev/null || npm install

# ── Persist shared env vars ───────────────────────────────────
SCRATCH_ALIAS="${SF_SCRATCH_ALIAS:-qrng-dev}"
SCRATCH_DAYS="${SF_SCRATCH_DAYS:-7}"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export SF_SCRATCH_ALIAS=\"$SCRATCH_ALIAS\"" >> "$CLAUDE_ENV_FILE"
fi

# ── Check for Salesforce CLI ──────────────────────────────────
if ! command -v sf &>/dev/null; then
    echo "Salesforce CLI (sf) not found — installing..."
    npm install -g @salesforce/cli 2>/dev/null || {
        echo "WARNING: Could not install Salesforce CLI. Skipping org setup."
        exit 0
    }
fi

# ── Authenticate DevHub ───────────────────────────────────────
if [ -z "${SFDX_AUTH_URL:-}" ]; then
    echo "No SFDX_AUTH_URL set — skipping DevHub auth and scratch org setup."
    echo "Set SFDX_AUTH_URL in your Claude Code web environment variables"
    echo "to enable automatic scratch org provisioning."
    exit 0
fi

echo "=== Authenticating DevHub ==="
echo "$SFDX_AUTH_URL" > /tmp/sfdx_auth.txt
sf org login sfdx-url \
    --sfdx-url-file /tmp/sfdx_auth.txt \
    --alias devhub \
    --set-default-dev-hub 2>/dev/null || {
    echo "WARNING: DevHub auth failed. Check SFDX_AUTH_URL."
    rm -f /tmp/sfdx_auth.txt
    exit 0
}
rm -f /tmp/sfdx_auth.txt
echo "DevHub authenticated successfully."

# ── Create or reuse scratch org ───────────────────────────────
echo "=== Setting up scratch org ($SCRATCH_ALIAS) ==="

# Check if scratch org already exists and is active
ORG_STATUS=$(sf org display --target-org "$SCRATCH_ALIAS" --json 2>/dev/null | \
    node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);console.log(j.result?.connectedStatus||'NotFound')}catch{console.log('NotFound')}})" \
    2>/dev/null || echo "NotFound")

if [ "$ORG_STATUS" = "Connected" ] || [ "$ORG_STATUS" = "Active" ]; then
    echo "Scratch org '$SCRATCH_ALIAS' already exists and is active."
else
    echo "Creating new scratch org '$SCRATCH_ALIAS' (${SCRATCH_DAYS} days)..."
    sf org create scratch \
        --definition-file config/project-scratch-def.json \
        --alias "$SCRATCH_ALIAS" \
        --set-default \
        --duration-days "$SCRATCH_DAYS" \
        --wait 10 || {
        echo "WARNING: Scratch org creation failed. You may need to create it manually."
        exit 0
    }
    echo "Scratch org created."
fi

# ── Deploy source ─────────────────────────────────────────────
echo "=== Deploying source to scratch org ==="
sf project deploy start \
    --target-org "$SCRATCH_ALIAS" \
    --ignore-conflicts \
    --wait 10 || {
    echo "WARNING: Deploy failed. Check for metadata errors."
}

# ── Assign permission sets ────────────────────────────────────
echo "=== Assigning permission sets ==="
sf org assign permset \
    --name QuantumFair_Admin \
    --target-org "$SCRATCH_ALIAS" 2>/dev/null || true
sf org assign permset \
    --name QuantumFair_User \
    --target-org "$SCRATCH_ALIAS" 2>/dev/null || true
echo "Permission sets assigned."

# ── Get org info for session ──────────────────────────────────
INSTANCE_URL=$(sf org display --target-org "$SCRATCH_ALIAS" --json 2>/dev/null | \
    node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);console.log(j.result?.instanceUrl||'')}catch{console.log('')}})" \
    2>/dev/null || echo "")

ACCESS_TOKEN=$(sf org display --target-org "$SCRATCH_ALIAS" --json 2>/dev/null | \
    node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);console.log(j.result?.accessToken||'')}catch{console.log('')}})" \
    2>/dev/null || echo "")

# ── Persist org credentials as env vars ───────────────────────
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export SF_SCRATCH_ALIAS=\"$SCRATCH_ALIAS\"" >> "$CLAUDE_ENV_FILE"
    if [ -n "$INSTANCE_URL" ]; then
        echo "export SF_INSTANCE_URL=\"$INSTANCE_URL\"" >> "$CLAUDE_ENV_FILE"
    fi
    if [ -n "$ACCESS_TOKEN" ]; then
        echo "export SF_ACCESS_TOKEN=\"$ACCESS_TOKEN\"" >> "$CLAUDE_ENV_FILE"
    fi
fi

# ── Print session summary ─────────────────────────────────────
echo ""
echo "=========================================="
echo "  QuantumFair Dev Environment Ready"
echo "=========================================="
echo "  Scratch Org:  $SCRATCH_ALIAS"
[ -n "$INSTANCE_URL" ] && echo "  Instance URL: $INSTANCE_URL"
echo "  App URL:      <instance>/lightning/n/OpenSF__QuantumFair"
echo ""
echo "  Commands:"
echo "    npm run test:unit          — Jest tests"
echo "    npm run lint               — ESLint"
echo "    sf apex run test           — Apex tests"
echo "    npm run test:e2e           — Playwright E2E"
echo "=========================================="

exit 0
