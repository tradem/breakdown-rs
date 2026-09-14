#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# publish-release.sh — create/attach the GitHub Release (idempotent)
# (OpenSpec change `add-android-release-workflow`, task 3.5; spec
# `flutter-release-artifacts` "Alpha and Beta Pre-Releases").
#
# Behavior:
#   * tags with `-alpha.N` / `-beta.N` suffix → GitHub PRE-release;
#     stable tags → full release (one workflow, one boolean).
#   * release notes list the APK per ABI with an installation hint.
#   * idempotent on re-run: if the release exists, artifacts are re-uploaded
#     with `--clobber` (no duplicate artifacts); otherwise the release is
#     created with all artifacts attached.
#
# Usage:
#   publish-release.sh                 # publish against env GitHub context
#   publish-release.sh --dry-run       # print the actions, change nothing
#
# Environment:
#   VERSION_NAME       required — pubspec build-name (release tag = v<name>)
#   VERSION_FULL       required — full pubspec version (`X.Y.Z[-pre.N]+N`)
#   GH_TOKEN           required (except --dry-run) — the release token
#   GITHUB_REPOSITORY  required (except --dry-run) — `owner/repo`
#   dist/ breakdown-*  required — staged artifacts (stage-artifacts.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/release -> frontend-flutter
FLUTTER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$FLUTTER_DIR"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "Unknown argument: $arg (supported: --dry-run)"; exit 1 ;;
  esac
done

VERSION_NAME="${VERSION_NAME:?VERSION_NAME is required (the pubspec build-name)}"
VERSION_FULL="${VERSION_FULL:?VERSION_FULL is required (the full pubspec version)}"
RELEASE_TAG="v$VERSION_NAME"

if [ "$DRY_RUN" -ne 1 ]; then
  GH_TOKEN="${GH_TOKEN:?GH_TOKEN is required for publishing}"
  GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required for publishing}"
fi

prerelease=""
case "$VERSION_NAME" in
  *-alpha.*|*-beta.*) prerelease="true" ;;
esac

notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
{
  echo "## Breakdown $VERSION_NAME"
  echo
  echo "Install the APK for YOUR device architecture (most modern"
  echo "devices: **arm64-v8a**):"
  echo
  echo "- \`breakdown-$VERSION_NAME-arm64-v8a.apk\` — arm64-v8a (modern phones/tablets)"
  echo "- \`breakdown-$VERSION_NAME-armeabi-v7a.apk\` — armeabi-v7a (older devices)"
  echo "- \`breakdown-$VERSION_NAME-x86_64.apk\` — x86_64 (emulators, x86 devices)"
  echo "- \`breakdown-$VERSION_NAME.aab\` — Play-Store bundle (for the future Play channel)"
  echo
  echo "Sideloading: enable \"Install unknown apps\" for your file"
  echo "manager/browser, then install the downloaded APK directly —"
  echo "no store account required. A later install with the same"
  echo "project key updates in place (no uninstall needed)."
  echo
  echo "Version: \`$VERSION_FULL\` (pubspec.yaml is the single version source; tags are \`v<build-name>\`)."
} > "$notes"

# Exact artifact contract (stage-artifacts.sh output): the four files are
# bound to VERSION_NAME so a stale dist/ from another version can never be
# attached (a broad glob would happily publish foreign/old artifacts).
artifacts=(
  "dist/breakdown-$VERSION_NAME-arm64-v8a.apk"
  "dist/breakdown-$VERSION_NAME-armeabi-v7a.apk"
  "dist/breakdown-$VERSION_NAME-x86_64.apk"
  "dist/breakdown-$VERSION_NAME.aab"
)
for f in "${artifacts[@]}"; do
  [ -f "$f" ] || { echo "::error::Expected artifact $f is missing — run stage-artifacts.sh for $VERSION_NAME first (stale dist/ from another version is not publishable)."; exit 1; }
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] release tag:      $RELEASE_TAG"
  echo "[dry-run] pre-release:      $prerelease"
  echo "[dry-run] artifacts:        ${artifacts[*]}"
  echo "[dry-run] would create (or --clobber re-upload to) the GitHub Release"
  if gh release view "$RELEASE_TAG" --repo "${GITHUB_REPOSITORY:-<unset>}" >/dev/null 2>&1; then
    echo "[dry-run] (release currently exists — re-run would go the --clobber path)"
  else
    echo "[dry-run] (release currently does NOT exist — re-run would create it)"
  fi
  exit 0
fi

if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "::notice::Release '$RELEASE_TAG' already exists — re-uploading artifacts (idempotent re-run, --clobber replaces files; no duplicates are created)."
  gh release upload "$RELEASE_TAG" "${artifacts[@]}" \
    --clobber --repo "$GITHUB_REPOSITORY"
else
  gh_release_args=("$RELEASE_TAG" "${artifacts[@]}" --title "Breakdown $VERSION_NAME"
    --notes-file "$notes" --repo "$GITHUB_REPOSITORY")
  if [ "$prerelease" = "true" ]; then
    gh_release_args+=(--prerelease)
  fi
  gh release create "${gh_release_args[@]}"
fi
echo "::notice::Release '$RELEASE_TAG' published with $(ls dist/breakdown-* | wc -l) artifact(s)."
