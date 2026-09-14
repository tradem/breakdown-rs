#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# check-build-config.sh — build-time guard for the prod OIDC configuration
# (OpenSpec change `add-android-release-workflow`; the prod entrypoint
# fails closed at startup without OIDC_ISS / OIDC_CLIENT_ID /
# OIDC_REDIRECT_URI — lib/app.dart bootstrap guards, ADR-010/ADR-018).
#
# Fails the build EARLY (instead of shipping a binary that dies on its
# fatal-config screen) when required secrets are missing.
#
# Environment:
#   OIDC_ISS        required — prod IdP issuer URL
#   OIDC_CLIENT_ID  required — prod native-app client registration id
#   (OIDC_AUDIENCE is optional at build time: it is validated by the
#   backend at runtime, not by the client bootstrap.)
set -euo pipefail

for var in OIDC_ISS OIDC_CLIENT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "::error::$var is not set on the 'Release' environment — a prod build without it fails closed at startup. Provision the environment secrets (docs/release-signing-key-custody.md)."
    exit 1
  fi
done
echo "::notice::Prod OIDC build configuration present (OIDC_ISS, OIDC_CLIENT_ID)."
