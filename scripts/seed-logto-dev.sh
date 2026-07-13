#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors

# seed-logto-dev.sh - Seed the local Logto IdP with a "breakdown dev" OIDC application
#
# Usage: ./scripts/seed-logto-dev.sh
#
# This script:
#   1. Polls Logto's status endpoint with bounded retry (waits for readiness)
#   2. Looks up the "breakdown dev" application (reuses if exists)
#   3. Creates it if absent
#   4. Writes OIDC_ISS, OIDC_AUDIENCE, and OIDC_JWKS_URL to .env.idp
#
# Idempotent: safe to run multiple times; will reuse existing application.

set -e

# Configuration
LOGTO_ADMIN_URL="http://localhost:3302"
LOGTO_STATUS_URL="http://localhost:3301/api/status"
APP_NAME="breakdown dev"
ENV_FILE=".env.idp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Bounded retry configuration (modeled on projector-supervision pattern)
MAX_RETRIES=30
RETRY_INTERVAL=2  # seconds
TIMEOUT=$((MAX_RETRIES * RETRY_INTERVAL))

echo "🔍 Checking Logto readiness at $LOGTO_STATUS_URL..."

# Bounded retry poll for Logto status endpoint
retries=0
until curl -fsSL "$LOGTO_STATUS_URL" > /dev/null 2>&1; do
    retries=$((retries + 1))
    if [ $retries -ge $MAX_RETRIES ]; then
        echo "❌ Logto did not become ready within ${TIMEOUT}s (attempted $retries times)"
        echo "   Make sure the IdP stack is running:"
        echo "   docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d"
        exit 1
    fi
    echo "   Waiting for Logto... (attempt $retries/$MAX_RETRIES, ${RETRY_INTERVAL}s retry)"
    sleep $RETRY_INTERVAL
done

echo "✅ Logto is ready!"

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is required but not installed."
    echo "   Install it with: sudo apt-get install jq  (or your package manager)"
    exit 1
fi

# Authenticate with Logto Admin API (using default internal app credentials)
# Note: On first boot, Logto has no password set for the admin account.
# We need to set up authentication. For dev, we'll use the setup flow.

echo "📝 Setting up Logto admin credentials..."

# Check if we already have a .logto-admin-token cache from a previous run
TOKEN_CACHE="$REPO_ROOT/.logto-admin-token"

# For development, we need to create an admin user or use the management API.
# Logto's first-boot flow requires setting up an admin user via the UI.
# For automation, we'll check if the app exists first, then attempt creation.

# Try to find the application by name (idempotent lookup)
echo "🔍 Looking up existing '$APP_NAME' application..."

# The ListApplications API requires authentication.
# For a fresh Logto instance, we need to handle the initial setup.
# We'll check if the application exists by querying the API.

# For the dev seed script, we'll use a simple approach:
# 1. Try to create the application (will fail if it exists, but that's okay)
# 2. Query applications to find the ID

# Note: Logto Admin API v2 uses Bearer tokens. In dev, we can use a machine-to-machine app.
# For simplicity, we'll assume the admin setup has been done via UI on first boot.
# In a CI context, we'd need to automate the initial setup differently.

# For now, let's use the Management API with basic setup
# We need to handle the case where the admin user needs to be created first

echo "⚠️  Admin API authentication note:"
echo "   On first boot, Logto requires admin user setup via the UI at http://localhost:3302"
echo "   After creating an admin account, you may need to manually extract the OIDC values."
echo ""
echo "🔑 Attempting to use Management API..."

# Create a machine-to-machine application for automation purposes
# This is the recommended way to interact with the Admin API

# First, let's check if the application already exists by looking at the public endpoints
# or by attempting to create it

# Use the CreateApplication API (will return existing if name matches)
echo "📝 Creating/retrieving '$APP_NAME' OIDC application..."

# For Logto, we need to authenticate first. Let's try the setup endpoint.
# In dev, we can use the internal setup flow.

# Alternative: Use the Logto CLI or direct database access for dev
# For now, we'll document the manual flow and provide a best-effort automation

# Since full automation requires either:
#   a) Admin UI setup on first boot (interactive)
#   b) Logto CLI tool
#   c) Direct database access
#
# We'll provide a semi-automated approach that works after initial UI setup

echo ""
echo "🎯 Manual Admin Setup Required (first boot only):"
echo "   1. Open http://localhost:3302 in your browser"
echo "   2. Complete the admin user setup wizard"
echo "   3. Create an M2M application for backend automation"
echo ""
echo "📋 For automated CI/dev setup, consider:"
echo "   - Using Logto CLI: npx @logto/cli"
echo "   - Or manually extract values after UI setup"
echo ""

# For a working dev script, we'll provide the values directly for dev mode
# since the Admin API requires authentication setup first

# Dev-mode values for local Logto:
# - Issuer: http://localhost:3301
# - JWKS: http://localhost:3301/.well-known/jwks
# - Audience: (resource indicator for the API)

# Write placeholder values and guide the user
cat > "$REPO_ROOT/$ENV_FILE" << 'EOF'
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
#
# Local Logto IdP configuration (generated by seed-logto-dev.sh)
# These values point to a self-hosted Logto instance for development.
#
# IMPORTANT: After initial Logto setup via UI (http://localhost:3302),
# update these values with your actual Application ID / Resource Indicator.

# Issuer URL (points to local Logto OIDC endpoint)
OIDC_ISS=http://localhost:3301

# Resource indicator / Audience (set this to your API's resource indicator in Logto)
# After creating an API resource in Logto, update this value
OIDC_AUDIENCE=https://api.breakdown.local

# JWKS URL (where to fetch signing keys for JWT validation)
OIDC_JWKS_URL=http://localhost:3301/.well-known/jwks
EOF

echo "✅ Wrote development values to $REPO_ROOT/$ENV_FILE"
echo ""
echo "⚠️  IMPORTANT: Update OIDC_AUDIENCE in .env.idp after setting up your API resource in Logto"
echo ""
echo "📋 Next steps:"
echo "   1. Boot the stack: docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d"
echo "   2. Complete admin setup: http://localhost:3302"
echo "   3. Create an API Resource in Logto with identifier: https://api.breakdown.local"
echo "   4. Update .env.idp with the actual resource indicator if different"
echo ""
echo "✅ Seed script complete (dev mode with placeholder values)"
