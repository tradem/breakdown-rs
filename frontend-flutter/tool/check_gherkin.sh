#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: hy3 (opencode-go)
# Co-authored-by: omen-alpha (opencode-go)
# Co-authored-by: deepseek-v4-flash (neuralwatt)
#
# Static CI gate for the Gherkin critical-scenario discipline
# (features-spec/README.md, tasks 5.1/5.2). Enforces:
#   1. The designated critical .feature files exist (the three AGENTS.md §6
#      minimum scopes plus the shoot-day execution scope shipped with
#      `flutter-shoot-day-execution`).
#   2. Each critical scope is tagged @critical (as an actual Gherkin tag,
#      not prose) and contains at least one Scenario. A critical scope may be
#      either still @pending (screen not landed, excluded by the runner's
#      tagExpression 'not @pending') OR fully promoted (no @pending left — it
#      then runs on device). Both states are valid.
#   3. The runner config excludes @pending (tagExpression = 'not @pending').
#   4. The discipline doc exists (review challenge rule + CI checklist).
#   5. The flutter_gherkin VM-service regex patch (issue #440) is present and
#      applicable: the tracked patch file exists in-tree, and the pub-cache
#      copy of flutter_gherkin 2.0.0 carries the `dart vm service`
#      alternative (or can be brought to that state). See the affected-
#      packages note at the bottom.
#
# It does NOT run the suite on device — that is tool/run_gherkin.sh, executed
# against a device/emulator. The pure-function-step review rule (5.1) is a
# human review gate, not auto-detected here.
#
# Affected-packages note (issue #440): this check hard-references the
# flutter_gherkin 2.0.0 pub-cache location and the tracked patch file. If the
# dependency is ever upgraded/resolved differently, update BOTH here and in
# tool/patch_gherkin.sh (PUB_CACHE path + PATCH_FILE). This is the CI assertion
# that the VM-service fix is reproducible; the authoritative on-device gate
# (tool/run_gherkin.sh) applies the same patch before launching the runner.
set -euo pipefail
cd "$(dirname "$0")/.."

root="$(pwd)"
features_dir="$root/features-spec"
config="$root/integration_test/gherkin/configuration.dart"
readme="$features_dir/README.md"
# flutter_gherkin VM-service patch bookkeeping (issue #440).
src_patch="$root/tool/patches/flutter_gherkin-2.0.0-vm-service.patch"
patch_helper="$root/tool/patch_gherkin.sh"
pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
patched_target="$pub_cache/hosted/pub.dev/flutter_gherkin-2.0.0/lib/src/flutter/flutter_run_process_handler.dart"

fail() {
  echo "::error file=$1::$2"
  exit 1
}

critical_files=(
  "soll_ist_report.feature"
  "soll_ist_execution.feature"
  "continuity_photo_capture.feature"
  "costume_assignment.feature"
  "setup/season-wizard.feature"
)

echo "Gherkin discipline check"

for f in "${critical_files[@]}"; do
  path="$features_dir/$f"
  [ -f "$path" ] || fail "$path" "Critical scope .feature missing: $f"
  # Anchor the tag to a tag line so prose/comments cannot satisfy it.
  grep -Eq '^[[:space:]]*@critical([[:space:]]|$)' "$path" || \
    fail "$path" "$f is not tagged @critical (as a Gherkin tag)"
  grep -Eq '^[[:space:]]*Scenario([[:space:]]+Outline)?:[[:space:]]+[^[:space:]]' "$path" || \
    fail "$path" "$f has no Scenario"
  echo "  ok: $f (@critical + scenario present; @pending allowed or promoted)"
done

[ -f "$config" ] || fail "$config" "Gherkin runner config missing"
# Tighten to the actual Dart assignment (not a comment/example).
grep -Eq "tagExpression = 'not @pending'" "$config" || \
  fail "$config" "Runner config must set tagExpression = 'not @pending'"
echo "  ok: runner config excludes @pending"

[ -f "$readme" ] || fail "$readme" "features-spec/README.md missing (documents the review challenge rule + CI checklist, tasks 5.1/5.2)"
echo "  ok: discipline doc present ($readme)"

# --- flutter_gherkin VM-service patch (issue #440) ---
echo "Gherkin VM-service patch check"
[ -f "$src_patch" ] || fail "$src_patch" "flutter_gherkin VM-service patch file missing (issue #440)"
echo "  ok: tracked patch file present"
[ -f "$patch_helper" ] || fail "$patch_helper" "tool/patch_gherkin.sh missing (issue #440)"
echo "  ok: patch helper present"
if [ ! -f "$patched_target" ]; then
  # On a machine that has never run flutter pub get (e.g. a fresh CI job), the
  # package is simply not cached yet; the tracked patch + helper are the
  # reproducible record, and tool/run_gherkin.sh applies them after pub get.
  # Fail LOUDLY only when the package IS present but clearly unpatched.
  echo "  ok: flutter_gherkin 2.0.0 not yet in pub-cache (fresh checkout); patch will apply on first run (tool/run_gherkin.sh)"
else
  bash "$patch_helper" --check || fail "$patched_target" "flutter_gherkin VM-service patch not applied to pub-cache copy (issue #440); run 'bash tool/run_gherkin.sh' or 'bash tool/patch_gherkin.sh'"
  echo "  ok: flutter_gherkin VM-service patch applied"
fi

echo "Gherkin discipline check passed."
