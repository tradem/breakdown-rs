#!/usr/bin/env sh
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4-flash (opencode-go)

# One-shot renderer for the Garage TOML config (ADR-019 / issue #156).
#
# `dxflrs/garage` is a bare static binary: it does not interpolate env vars in
# its config file and the image has no shell to generate it. This script runs
# inside the `garage-config` compose one-shot (alpine, digest-pinned) and
# renders `/config/config.toml` from the $GARAGE_* env vars into the shared
# `garage_config` volume (gitleaks-clean — values come from compose env).

set -eu

mkdir -p /config
cat > /config/config.toml <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
block_size = 1048576
replication_factor = 1
rpc_bind_addr = "0.0.0.0:3901"
rpc_public_addr = "garage:3901"
rpc_secret = "$GARAGE_RPC_SECRET"
[s3_api]
s3_region = "garage"
api_bind_addr = "0.0.0.0:3900"
root_domain = ".s3.garage.localhost"
[admin]
api_bind_addr = "0.0.0.0:3902"
admin_token = "$GARAGE_ADMIN_TOKEN"
metrics_token = "$GARAGE_METRICS_TOKEN"
EOF
chmod 644 /config/config.toml
# Fail loudly if the render silently produced nothing (e.g. env missing).
grep -q "admin_token" /config/config.toml
