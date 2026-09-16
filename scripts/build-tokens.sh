#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

# build-tokens.sh — the single entry point for the design-token build
# (spec `design-tokens`).
#
# Pipeline:
#   1. DTCG conformance check        design/validate-tokens.mjs
#   2. Style Dictionary build        design/style-dictionary.config.json
#                                    (design/tokens/**/*.json →
#                                     design/build/design_tokens.flat.json;
#                                     versions pinned via design/package-lock.json)
#   3. Dart artifact write           design/dart-artifact.mjs
#                                    (→ frontend-flutter/lib/design/gen/design_tokens.g.dart)
#   4. Temp-artifact cleanup         design/build/
#
# Output is byte-stable: no timestamps, tokens sorted by name, generator
# versions pinned by the committed lockfile. A second run without source
# changes produces no diff (CI drift gate relies on this).
#
# Usage:
#   bash scripts/build-tokens.sh                 # from anywhere
#   DESIGN_TOKENS_OUT_DIR=/tmp/gen bash scripts/build-tokens.sh
#                                                # regenerate into a
#                                                # throwaway directory
#                                                # (CI drift gate)
#
# Workflow when a token changes: edit the JSON → run this script → commit
# the JSON change together with the regenerated `lib/design/gen/` output.
# Hand edits to `frontend-flutter/lib/design/gen/` are forbidden.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DESIGN_DIR="${REPO_ROOT}/design"
TOKENS_DIR="${DESIGN_DIR}/tokens"
SD_CONFIG="${DESIGN_DIR}/style-dictionary.config.json"
SD_BUILD_DIR="${DESIGN_DIR}/build"
SD_BIN="${DESIGN_DIR}/node_modules/.bin/style-dictionary"
SD_PACKAGE_VERSION="5.5.3" # pinned in design/package.json + package-lock.json

fail() {
  echo "build-tokens: ERROR: $*" >&2
  exit 1
}

command -v npm >/dev/null 2>&1 \
  || fail "npm not found on PATH (Node toolchain required; see design/package.json)"
command -v node >/dev/null 2>&1 || fail "node not found on PATH"

[[ -d "${TOKENS_DIR}" ]] || fail "token source not found: ${TOKENS_DIR}"

# All build steps run from the repo root: Style Dictionary resolves the
# config's `source`/`buildPath` relative to the CWD, and the config pins
# root-relative paths (design/tokens/… → frontend-flutter/…).
cd "${REPO_ROOT}"

# 0. Pinned Node toolchain (CI-hardening: no 'latest', no unpinned network
#    fetch at build time beyond npm restoring the committed lockfile).
if [[ ! -x "${DESIGN_DIR}/node_modules/.bin/style-dictionary" ]]; then
  echo "build-tokens: node_modules missing — restoring from committed lockfile (npm ci)"
  npm --prefix "${DESIGN_DIR}" ci --no-audit --no-fund --silent
fi
echo "build-tokens: using style-dictionary (pinned ${SD_PACKAGE_VERSION} via design/package-lock.json)"

# 1. DTCG conformance check ($-prefixes, resolvable aliases, hex colors).
node "${DESIGN_DIR}/validate-tokens.mjs"

# 2. Style Dictionary build (deterministic; timestamps are not part of the
#    JSON intermediate, and the Dart artifact adds none).
"${SD_BIN}" build --config "${SD_CONFIG}" 2>/dev/null

# 3. Final Dart artifact (respects $DESIGN_TOKENS_OUT_DIR, default
#    frontend-flutter/lib/design/gen/).
node "${DESIGN_DIR}/dart-artifact.mjs"

# 4. Temp-artifact cleanup.
rm -rf "${SD_BUILD_DIR}"

echo "build-tokens: done. Commit the regenerated output together with any"
echo "              design/tokens/ JSON change (drift gate: regenerating must"
echo "              produce a byte-identical tree to the committed one)."
