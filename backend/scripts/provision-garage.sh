#!/usr/bin/env bash
set -euo pipefail

# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors

# Provision the Garage S3-compatible object store for costume-photo storage.
#
# This script:
#   1. Waits for Garage to be healthy (admin endpoint).
#   2. Creates a layout configuration.
#   3. Creates an access key.
#   4. Creates the costume-photos bucket.
#   5. Grants the key read/write permissions on the bucket.
#
# Prerequisites:
#   - `garage` CLI binary (installed as part of the Garage image).
#   - Garage container is reachable at $GARAGE_ENDPOINT.
#   - $GARAGE_ADMIN_TOKEN is set.
#
# Usage (from the host after `docker compose up -d`):
#   GARAGE_ADMIN_TOKEN=garage_admin_dev \
#   GARAGE_ENDPOINT=http://localhost:3900 \
#   ./scripts/provision-garage.sh
#
# Or as a one-shot container (docker-compose init pattern):
#   docker compose run --rm garage-provisioner

GARAGE_ENDPOINT="${GARAGE_ENDPOINT:-http://garage:3900}"
GARAGE_ADMIN_TOKEN="${GARAGE_ADMIN_TOKEN:?GARAGE_ADMIN_TOKEN is required}"
GARAGE_BUCKET="${GARAGE_BUCKET:-costume-photos}"

# Garage CLI alias that targets the right endpoint.
garage() {
    command garage \
        -h "$GARAGE_ENDPOINT" \
        -t "$GARAGE_ADMIN_TOKEN" \
        "$@"
}

echo "Waiting for Garage to be ready..."
until garage status >/dev/null 2>&1; do
    echo "  ... still waiting for Garage"
    sleep 2
done
echo "Garage is ready."

echo "Configuring Garage layout..."
# In a single-node dev setup, we assign all storage to one node.
garage layout assign -z dc1 -c 1G "$(hostname)" 2>/dev/null || true
garage layout show 2>/dev/null
garage layout apply --version 1 2>/dev/null || true
echo "Layout configured."

echo "Creating access key..."
KEY_OUTPUT=$(garage key new --name "breakdown-api" 2>&1)
echo "$KEY_OUTPUT"

# Parse the key ID and secret key from output.
ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep -oP 'Key ID:\s+\K\S+' || true)
SECRET_KEY=$(echo "$KEY_OUTPUT" | grep -oP 'Secret key:\s+\K\S+' || true)

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo "Warning: Could not parse new key output. Trying existing key..."
    # If the key already exists, retrieve it.
    KEY_OUTPUT=$(garage key info breakdown-api 2>&1)
    ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep -oP 'Key ID:\s+\K\S+' || echo "")
    SECRET_KEY=$(echo "$KEY_OUTPUT" | grep -oP 'Secret key:\s+\K\S+' || echo "")
fi

echo "Creating bucket '${GARAGE_BUCKET}'..."
garage bucket create "$GARAGE_BUCKET" 2>/dev/null || true
echo "Allowing key to access bucket..."
garage bucket allow \
    --read \
    --write \
    --owner \
    "$GARAGE_BUCKET" \
    --key "$ACCESS_KEY" 2>/dev/null || true

echo ""
echo "=============================================="
echo "Garage provisioning complete."
echo ""
echo "Export these env vars for the API binary:"
echo "  export S3_ENDPOINT=${GARAGE_ENDPOINT}"
echo "  export S3_ACCESS_KEY=${ACCESS_KEY}"
echo "  export S3_SECRET_KEY=${SECRET_KEY}"
echo "  export S3_BUCKET=${GARAGE_BUCKET}"
echo "=============================================="
