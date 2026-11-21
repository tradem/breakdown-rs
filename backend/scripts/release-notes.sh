#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Render the GitHub Release body of an `api-vX.Y.Z` image release, from the two
# reviewed sources (ADR-020 D9, docs/operations/release-runbook.md §3):
#
#   1. `backend/RELEASE-NOTES/<tag>.md` — the curated, reviewed prose file, used
#      **verbatim** when the release owner checked one in (upgrade guidance,
#      migration counts, artifact list — the `api-v0.14.0` structure).
#   2. otherwise the tag's `## [api-vX.Y.Z]` section of `backend/CHANGELOG.md`,
#      rendered under a mechanical preamble.
#
# Neither exists → exit 2. The fallback is *derived*, never generated.
#
# Why this exists: `api-v0.71.0` was published with `gh release create
# --generate-notes`, so its notes were a 223-line list of squash-merge titles
# while the curated, reviewed prose sat unread in `backend/CHANGELOG.md`. Two
# artifacts for one release, one of them unreviewed — they can only drift. The
# tag-push workflows (`.github/workflows/docs.yml`) call this script so no path
# can publish a commit list again.
#
#   ./scripts/release-notes.sh api-v0.71.0                 # to stdout
#   ./scripts/release-notes.sh api-v0.71.0 --out notes.md   # to a file
#   ./scripts/release-notes.sh api-v0.71.0 --previous api-v0.14.0
#
# Environment overrides (used by the guard test):
#   RELEASE_CHANGELOG         changelog to read (default: <backend>/CHANGELOG.md)
#   RELEASE_NOTES_DIR         curated notes dir (default: <backend>/RELEASE-NOTES)
#   RELEASE_REPO              owner/repo slug (default: $GITHUB_REPOSITORY, else origin remote)
#   RELEASE_BODY_CHAR_LIMIT   body budget (default: 120000 — GitHub caps a release body
#                            at 125000 characters; a 50-release cut like api-v0.71.0
#                            renders 142 KB, so it is truncated at a line boundary
#                            with a pointer to the changelog instead of failing the job)
#
# Exit codes: 0 rendered · 1 usage/derivation error · 2 the tag has no section
# (the cut was skipped — the caller must not publish auto-generated notes).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${BACKEND_DIR}/.." && pwd)"
CHANGELOG="${RELEASE_CHANGELOG:-${BACKEND_DIR}/CHANGELOG.md}"
NOTES_DIR="${RELEASE_NOTES_DIR:-${BACKEND_DIR}/RELEASE-NOTES}"
RELEASE_BODY_CHAR_LIMIT="${RELEASE_BODY_CHAR_LIMIT:-120000}"

usage() {
  # The whole leading comment block — no line range to drift out of sync.
  awk 'NR > 1 {
      if ($0 !~ /^#/) exit
      if ($0 ~ /^# (SPDX-License-Identifier:|Copyright |Co-authored-by:)/) next
      sub(/^# ?/, "")
      print
    }' "${BASH_SOURCE[0]}"
}

die() {
  printf 'release-notes: %s\n' "$1" >&2
  exit "${2:-1}"
}

tag=""
previous=""
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --previous) previous="${2:-}"; [[ -n $previous ]] || die "--previous needs a tag" 1; shift 2 ;;
    --out) out="${2:-}"; [[ -n $out ]] || die "--out needs a path" 1; shift 2 ;;
    -*) die "unknown option: $1" 1 ;;
    *) [[ -z $tag ]] || die "unexpected extra argument: $1" 1; tag="$1"; shift ;;
  esac
done

[[ -n $tag ]] || die "usage: release-notes.sh <api-vX.Y.Z> [--previous <tag>] [--out <file>]" 1
case "$tag" in
  api-v[0-9]*) ;;
  *) die "only api-vX.Y.Z image tags have a release body (got: ${tag})" 1 ;;
esac

curated="${NOTES_DIR}/${tag}.md"

# --- 1. the curated file is the body, verbatim ----------------------------
# Verbatim on purpose: the owner writes the release body (title, deploying
# block, upgrade guidance), and a script that decorates it would make the
# reviewed file differ from what readers see.
# The leading SPDX/co-author HTML comments are repo metadata, not body content —
# markdown hides them, but the release editor shows the raw text.
curated_body() {
  awk 'BEGIN { header = 1 }
    header && /^<!--.*-->$/ { next }
    header && /^[[:space:]]*$/ { next }
    { header = 0; print }' "$curated"
}

if [[ -f $curated ]]; then
  if [[ -n $out ]]; then
    curated_body > "$out"
    printf 'release-notes: %s (curated, %s lines)\n' "$curated" "$(wc -l < "$out")" >&2
  else
    curated_body
  fi
  exit 0
fi

[[ -r $CHANGELOG ]] || die "changelog not readable: ${CHANGELOG}" 1

# --- 2. otherwise the cut CHANGELOG section -------------------------------
# From `## [<tag>]` up to (excluding) the next `## [` heading.
section="$(
  awk -v tag="$tag" '
    index($0, "## [" tag "]") == 1 { inside = 1; next }
    inside && /^## \[/ { exit }
    inside { print }
  ' "$CHANGELOG"
)"
# `$( ... )` already dropped the trailing newlines; drop the leading blanks.
while [[ $section == $'\n'* ]]; do section="${section#$'\n'}"; done

if [[ -z $section ]]; then
  die "no release body for ${tag} — neither
         ${curated#"${REPO_DIR}/"}          (curated prose, preferred), nor
         ${CHANGELOG#"${REPO_DIR}/"}  ('## [${tag}]')
       Cut '## [Unreleased]' into a dated section (ADR-020 D9):
         ## [${tag}] – Released $(date +%Y-%m-%d)
       Publishing auto-generated commit lists instead is what this script
       exists to prevent." 2
fi

# --- owner/repo slug ------------------------------------------------------
slug="${RELEASE_REPO:-${GITHUB_REPOSITORY:-}}"
if [[ -z $slug ]]; then
  remote="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    git@*:*)      slug="${remote#*:}" ;;
    ssh://git@*)  slug="${remote#ssh://git@*/}" ;;
    https://*)    slug="${remote#https://*/}" ;;
    *)            die "cannot derive owner/repo from origin remote (${remote:-none}); set RELEASE_REPO=owner/repo" 1 ;;
  esac
  slug="${slug%.git}"
fi
[[ $slug == */* ]] || die "invalid owner/repo slug: ${slug}" 1

# The changelog's artifact bullet carries the repo's `<owner>/<repo>` placeholder
# (see the `api-v0.14.0` entry); the release body must name the real image.
section="${section//'<owner>/<repo>'/$slug}"

# --- previous image tag (for the diff link) ------------------------------
if [[ -z $previous ]]; then
  # Tag *names* only, never commit history: the docs workflow checks out with the
  # default shallow depth, so `git describe <tag>^` has nothing to walk. The list
  # is version-sorted descending, so the predecessor is the entry after this tag.
  previous="$(git -C "$REPO_DIR" tag --list 'api-v*' --sort=-v:refname 2>/dev/null \
    | awk -v t="$tag" 'found { print; exit } $0 == t { found = 1 }')" || previous=""
fi

version="${tag#api-v}"
major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"
moving="api-v${major}.${minor}"

render() {
  # The three bullets the changelog section carries (artifact, companion crate
  # versions, baseline) stay in the section — the cut owns them.
  local headline section_out footer
  headline="$(cat <<PREAMBLE
## Backend API image release \`${tag}\`

This is the Docker image release of the Breakdown backend API (ADR-020).
Full changelog: [\`backend/CHANGELOG.md\`](https://github.com/${slug}/blob/${tag}/backend/CHANGELOG.md).

### Deploying

Pull the **immutable** version tag (SHA-pinned digest):

\`\`\`
ghcr.io/${slug}:${tag}
\`\`\`

Moving tags \`${moving}\` (latest patch) and \`api-v${major}\` (latest minor) are also
published. The rolling \`:latest\` tag is deliberately **not** published — pin
by \`api-vX.Y.Z\` for reproducible rollbacks.

PREAMBLE
)"
  footer=""
  if [[ -n $previous ]]; then
    footer="$(printf '\n\n**Full diff:** [`%s...%s`](https://github.com/%s/compare/%s...%s)\n' \
      "$previous" "$tag" "$slug" "$previous" "$tag")"
  fi

  # GitHub rejects a body over 125000 characters (422). An accumulated cut can
  # legitimately exceed the budget (api-v0.71.0 covered 50 releases: 142 KB), so
  # truncate at a line boundary and say so — a hard failure would block the tag
  # over an artifact-size detail, and a silent cut would look like the whole entry.
  local note budget
  note="$(printf '\n\n_truncated at the release-note character limit — the rest, and every earlier release, is in [`backend/CHANGELOG.md`](https://github.com/%s/blob/%s/backend/CHANGELOG.md)._' "$slug" "$tag")"
  budget=$(( RELEASE_BODY_CHAR_LIMIT - ${#headline} - ${#footer} - ${#note} - 8 ))
  (( budget > 0 )) || budget=0
  section_out="$section"
  if (( ${#section} > budget )); then
    section_out="$(printf '%s\n' "$section" | awk -v max="$budget" 'BEGIN { used = 0 }
      { len = length($0) + 1; if (used + len > max) { exit } used += len; print }')"
    section_out="${section_out}${note}"
    printf 'release-notes: section is %s chars, body budget is %s — truncated; the full entry stays in the changelog\n' \
      "${#section}" "$budget" >&2
  fi

  printf '%s%s%s\n' "$headline" "$section_out" "$footer"
}

if [[ -n $out ]]; then
  render > "$out"
  printf 'release-notes: wrote %s (%s lines)\n' "$out" "$(wc -l < "$out")" >&2
else
  render
fi
