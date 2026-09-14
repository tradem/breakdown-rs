#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: omen-alpha (opencode-go)

#
# version-gate.sh — release version-consistency gate
# (OpenSpec change `add-android-release-workflow`, task 3.2; spec
# `flutter-release-artifacts` "Version Consistency Gate").
#
# Enforces, before ANY build/publish happens:
#   1. pubspec.yaml version format: `X.Y.Z[-alpha.N|-beta.N]+N`
#      (the unified tag/pubspec format; ADR-033 D1/D5).
#   2. tag <-> pubspec build-name equality: the release tag MUST be
#      `v<build-name>` (pubspec.yaml is the single version source).
#   3. strictly monotonic versionCode across ALL previous `v*` release
#      tags (requires a full-history checkout: fetch-depth: 0).
#
# Environment:
#   TAG_NAME        required — the pushed release tag (e.g. v1.2.0-alpha.1)
#   GITHUB_OUTPUT   optional — when set (GitHub Actions), the script writes
#                   `version_name` / `version_full` outputs; locally it just
#                   prints and validates.
#
# Exit: 0 = gate passed, 1 = gate failed (with ::error:: annotation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# .../frontend-flutter/scripts/release -> frontend-flutter -> monorepo root.
# FLUTTER_DIR is overridable for tests (scratch repos), never in CI.
FLUTTER_DIR="${FLUTTER_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$(dirname "$FLUTTER_DIR")"
PUBSPEC="$FLUTTER_DIR/pubspec.yaml"

TAG="${TAG_NAME:?TAG_NAME is required (e.g. 'v1.2.0-alpha.1')}"
[ -f "$PUBSPEC" ] || { echo "::error::pubspec.yaml not found at $PUBSPEC"; exit 1; }

# The tag MUST carry the literal 'v' prefix — '${TAG#v}' alone would also
# accept an unprefixed tag that happens to equal the build-name.
if ! [[ "$TAG" == v* ]]; then
  echo "::error::Release tag '$TAG' is missing the required 'v' prefix. Tags are 'v<build-name>'."
  exit 1
fi

version="$(sed -n 's/^version: *//p' "$PUBSPEC" | head -n 1 | tr -d '[:space:]')"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)\.[0-9]+)?\+[0-9]+$ ]]; then
  echo "::error::frontend-flutter/pubspec.yaml version must be 'X.Y.Z[-alpha.N|-beta.N]+N' (ADR-033 D1, unified release format), got '$version'."
  exit 1
fi

build_name="${version%%+*}"
build_number="${version##*+}"
if [ "${TAG#v}" != "$build_name" ]; then
  echo "::error::Release tag '$TAG' disagrees with pubspec build-name '$build_name'. The tag MUST be 'v<build-name>' (pubspec.yaml is the single version source). Fix the tag or the pubspec version and re-tag."
  exit 1
fi

# Monotonic versionCode across all OTHER release tags that PRECEDE the
# current one: the current build number must be strictly greater than every
# previous one. Tags newer than $TAG (e.g. when re-running an older release
# after newer ones exist) are EXCLUDED via merge-base ancestry — otherwise
# an idempotent re-publication of an old tag would fail against newer build
# numbers. Tags without a parsable `+<int>` suffix are skipped (not a
# failure — they may be legacy).
# NOTE: `git show <tag>:<path>` requires a repo-relative path — FLUTTER_DIR
# (absolute) is stripped of the REPO_ROOT prefix for git.
rel_pubspec="${PUBSPEC#"$REPO_ROOT"/}"
prev_max=0
while IFS= read -r tag; do
  [ "$tag" = "$TAG" ] && continue
  # only tags on the current tag's ancestry (earlier releases)
  git merge-base --is-ancestor "$tag" "$TAG" 2>/dev/null || continue
  pv="$(git show "$tag":"$rel_pubspec" 2>/dev/null \
    | sed -n 's/^version: *//p' | head -n 1 | tr -d '[:space:]' \
    | sed -n 's/^.*+\([0-9][0-9]*\)$/\1/p')"
  if [ -n "$pv" ] && [ "$pv" -gt "$prev_max" ]; then
    prev_max="$pv"
  fi
done < <(git tag -l 'v*')

if [ "$build_number" -le "$prev_max" ]; then
  echo "::error::versionCode $build_number is not strictly greater than the highest previous release versionCode ($prev_max). Bump the pubspec build number."
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version_name=$build_name"
    echo "version_full=$version"
  } >> "$GITHUB_OUTPUT"
fi
echo "::notice::Version gate OK: tag '$TAG' == pubspec build-name '$build_name', versionCode $build_number > $prev_max."
