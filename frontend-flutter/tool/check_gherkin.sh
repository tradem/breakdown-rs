#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)
#
# Static CI gate for the Gherkin critical-scenario discipline
# (features-spec/README.md, tasks 5.1/5.2). Enforces:
#   1. The three designated critical .feature files exist.
#   2. Each critical scope is also tagged @pending (i.e. not promoted into the
#      on-device pass before its screen lands).
#   3. The runner config excludes @pending (tagExpression "not @pending").
#   4. The discipline doc exists (review challenge rule + CI checklist).
#
# It does NOT run the suite on device — that is tool/run_gherkin.sh, executed
# against a device/emulator.
set -euo pipefail
cd "$(dirname "$0")/.."

root="$(pwd)"
features_dir="$root/features-spec"
config="$root/integration_test/gherkin/configuration.dart"
readme="$features_dir/README.md"

fail() {
  echo "::error file=$1::$2"
  exit 1
}

critical_files=(
  "soll_ist_report.feature"
  "continuity_photo_capture.feature"
  "costume_assignment.feature"
)

echo "Gherkin discipline check"

for f in "${critical_files[@]}"; do
  path="$features_dir/$f"
  [ -f "$path" ] || fail "$path" "Critical scope .feature missing: $f"
  grep -q '@critical' "$path" || fail "$path" "$f is not tagged @critical"
  grep -q '@pending' "$path" || fail "$path" "$f is @critical but not @pending (do not promote into the on-device pass before its screen lands)"
  echo "  ok: $f (@critical + @pending)"
done

[ -f "$config" ] || fail "$config" "Gherkin runner config missing"
grep -q "not @pending" "$config" || fail "$config" "Runner config must exclude @pending (tagExpression: 'not @pending')"
echo "  ok: runner config excludes @pending"

[ -f "$readme" ] || fail "$readme" "features-spec/README.md missing (documents the review challenge rule + CI checklist, tasks 5.1/5.2)"
echo "  ok: discipline doc present ($readme)"

echo "Gherkin discipline check passed."
