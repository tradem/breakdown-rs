#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Guard test for `scripts/release/publish-release.sh`'s release-body
# resolution (the Flutter counterpart of `backend/scripts/tests/release-notes-test.sh`,
# ADR-020 D9 / issue #953).
#
# The rule: a published body comes from a REVIEWED source, never from
# generated notes. `v0.3.0` was published with hand-written notes (title,
# highlights, artifact list, version line) while `publish-release.sh` kept
# emitting a mechanical list — two artifacts for one release, one of them
# unreviewed. The script now prefers `RELEASE-NOTES/v<VERSION_NAME>.md`, so
# three promises must hold:
#
#   1. **The curated file wins, verbatim** (minus its SPDX/co-author HTML
#      comment header): nothing is prepended, appended or reformatted — in
#      particular NOT the mechanical artifact list.
#   2. **Without a curated file the mechanical body is unchanged**: the four
#      ABI-named artifacts and the `Version:` line carrying the full pubspec
#      version, so every alpha/beta build stays installable.
#   3. **The pre-release boolean still derives from the tag name** — a curated
#      body must not cost the alpha/beta channel its pre-release flag.
#
# Daemon-free: bash + coreutils + a `mktemp -d` fixture, with a fake `gh` on
# PATH. No network, no token, no artifacts to sign.
#
# Usage: bash scripts/release/tests/publish-release-notes-test.sh

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
SCRIPT="${RELEASE_DIR}/publish-release.sh"
[ -f "$SCRIPT" ] || { printf 'missing script: %s\n' "$SCRIPT" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/publish-release-notes-test.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

FAILURES=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}
contains() { grep -qF -- "$2" <<<"$1"; }
excludes() { ! grep -qF -- "$2" <<<"$1"; }
equals() { [ "$1" = "$2" ]; }

# --- fake `gh`: never touches the network ---------------------------------
# `gh release view` answers "no such release" (exit 1) so the script takes the
# create path; `gh release create` records its argv and copies the body it was
# handed out of `--notes-file` — the file the script deletes on exit.
BIN="${WORK}/bin"
mkdir -p "$BIN"
cat > "${BIN}/gh" <<'FAKE_GH'
#!/usr/bin/env bash
if [ "${1:-}" = "release" ] && [ "${2:-}" = "view" ]; then
  exit 1
fi
if [ "${1:-}" = "release" ] && [ "${2:-}" = "create" ]; then
  printf '%s\n' "$*" > "${CAPTURE_ARGS:?CAPTURE_ARGS is required}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --notes-file) cp "${2:?}" "${CAPTURE_NOTES:?CAPTURE_NOTES is required}"; shift 2 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
exit 1
FAKE_GH
chmod +x "${BIN}/gh"

# --- a scratch Flutter project: the script resolves dist/ and the notes dir
# relative to its own `scripts/release/` location, so the fixture must mirror
# that layout (`<project>/scripts/release/publish-release.sh`).
make_project() { # <version-name> <fixture-label> -> prints the project dir
  local name="$1" label="$2"
  local project="${WORK}/${label}"
  mkdir -p "${project}/scripts/release" "${project}/dist" "${project}/RELEASE-NOTES"
  cp "$SCRIPT" "${project}/scripts/release/publish-release.sh"
  local abi
  for abi in arm64-v8a armeabi-v7a x86_64; do
    : > "${project}/dist/breakdown-${name}-${abi}.apk"
  done
  : > "${project}/dist/breakdown-${name}.aab"
  printf '%s\n' "$project"
}

run_publish() { # <project> <version-name> <version-full>
  local project="$1" name="$2" full="$3"
  (
    cd "$project"
    PATH="${BIN}:${PATH}"
    export PATH
    GH_TOKEN=dummy
    GITHUB_REPOSITORY=acme/widget
    CAPTURE_ARGS="${project}/gh-args.txt"
    CAPTURE_NOTES="${project}/body.md"
    VERSION_NAME="$name"
    VERSION_FULL="$full"
    export GH_TOKEN GITHUB_REPOSITORY CAPTURE_ARGS CAPTURE_NOTES VERSION_NAME VERSION_FULL
    bash scripts/release/publish-release.sh >"${project}/stdout.txt" 2>&1
  )
}

# 1. the curated file wins, verbatim ---------------------------------------
stable="$(make_project 0.4.0 curated-stable)"
cat > "${stable}/RELEASE-NOTES/v0.4.0.md" <<'CURATED'
<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: someone (somewhere) -->

## Breakdown 0.4.0

CURATED-MARKER: the owner's reviewed prose, not a generated list.

Version: `0.4.0+155`.
CURATED
run_publish "$stable" "0.4.0" "0.4.0+155"
body="$(cat "${stable}/body.md")"
check "curated body is used verbatim (marker present)" contains "$body" "CURATED-MARKER:"
check "curated body carries no mechanical artifact list" excludes "$body" "Install the APK for YOUR device architecture"
check "curated body has no preamble (first line is the owner's own heading)" \
  equals "$(head -n 1 "${stable}/body.md")" "## Breakdown 0.4.0"
check "curated body drops the SPDX/co-author comment header" excludes "$body" "SPDX-License-Identifier"
check "the curated path is announced" contains "$(cat "${stable}/stdout.txt")" "v0.4.0.md (curated, used verbatim)"

# 2. without a curated file the mechanical body is unchanged ---------------
fallback="$(make_project 0.4.0 no-curated)"
run_publish "$fallback" "0.4.0" "0.4.0+155"
mech="$(cat "${fallback}/body.md")"
check "fallback body keeps the title line" contains "$mech" "## Breakdown 0.4.0"
check "fallback body lists every ABI-named artifact" contains "$mech" "breakdown-0.4.0-arm64-v8a.apk"
check "fallback body carries the full pubspec version" contains "$mech" "Version: \`0.4.0+155\`"
check "the mechanical path is announced as such" \
  contains "$(cat "${fallback}/stdout.txt")" "mechanical artifact list"

# 3. the pre-release boolean still derives from the tag name ---------------
prerelease="$(make_project 0.4.1-beta.1 beta-nofile)"
run_publish "$prerelease" "0.4.1-beta.1" "0.4.1-beta.1+156"
check "a beta tag still creates a pre-release" contains "$(cat "${prerelease}/gh-args.txt")" "--prerelease"
check "a stable tag does not" excludes "$(cat "${stable}/gh-args.txt")" "--prerelease"

# A curated file must not cost a beta build its pre-release flag.
curated_beta="$(make_project 0.4.1-beta.2 beta-curated)"
printf '## Breakdown 0.4.1-beta.2\n\nCURATED-BETA\n' > "${curated_beta}/RELEASE-NOTES/v0.4.1-beta.2.md"
run_publish "$curated_beta" "0.4.1-beta.2" "0.4.1-beta.2+157"
check "a curated beta body keeps the pre-release flag" contains "$(cat "${curated_beta}/gh-args.txt")" "--prerelease"

printf '\n'
if [ "$FAILURES" -ne 0 ]; then
  printf 'FAILED: %d check(s)\n' "$FAILURES"
  exit 1
fi
printf 'All publish-release notes checks passed.\n'
