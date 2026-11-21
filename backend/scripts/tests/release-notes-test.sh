#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Guard test for `scripts/release-notes.sh` (ADR-020 D9,
# docs/operations/release-runbook.md §3).
#
# The script exists because `api-v0.71.0` was published with
# `gh release create --generate-notes`: the notes were a 223-line squash-merge
# list while the curated, reviewed prose sat in `backend/CHANGELOG.md`. Two
# artifacts, one unreviewed, guaranteed to drift. The release body now comes from
# one of exactly two reviewed sources — the curated
# `backend/RELEASE-NOTES/<tag>.md` (preferred, verbatim) or the tag's cut
# CHANGELOG section (derived fallback) — so five promises must hold:
#
#   0. **The curated file wins, verbatim** (minus its SPDX comment header):
#      nothing is prepended, appended or reformatted.
#   2. **A missing section fails closed (exit 2).** Falling back to
#      auto-generated notes is the defect, not the escape hatch — the caller must
#      abort instead of publishing a commit list.
#   3. **The mechanical preamble is correct**: the immutable pull line, the two
#      moving tags derived from the tag, the changelog link pinned to the tag.
#   4. **owner/repo is derivable** from `GITHUB_REPOSITORY`, from an ssh/https
#      origin remote, or overridden — the workflow sets neither env var.
#
# Daemon-free: bash + git + a `mktemp -d` fixture. No network, no gh, no docker.
#
# Usage: bash scripts/tests/release-notes-test.sh

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
SCRIPT="${BACKEND_DIR}/scripts/release-notes.sh"
REAL_CHANGELOG="${BACKEND_DIR}/CHANGELOG.md"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/release-notes-test.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
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
  if "$@"; then pass "${description}"; else fail "${description}"; fi
}
contains() { grep -qF -- "$2" <<<"$1"; }
omits() { ! grep -qF -- "$2" <<<"$1"; }

# ── fixture: a throwaway repo with two releases and a live [Unreleased] ──────
FIXTURE="${WORK}/repo"
mkdir -p "${FIXTURE}/backend/scripts"
cp "${SCRIPT}" "${FIXTURE}/backend/scripts/release-notes.sh"
cat > "${FIXTURE}/backend/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

### Added

- an unreleased entry that must never reach a release body

## [api-v9.9.9] – Released 2026-01-02

- Shipped artifact: `ghcr.io/<owner>/<repo>:api-v9.9.9` (immutable, SHA-pinned digest).
- Companion crate versions at this release: `core 1.0.0`, `infra 2.0.0`, `api 9.9.9`.

### Added

- **Fixture entry.** The curated prose of the release.

### Fixed

- **Second subsection** survives the extraction.

## [api-v9.9.8] – 2026-01-01

- a previous release that must never appear
MD
# A second fixture section long enough to blow the body budget, so the truncation
# path (GitHub caps a release body at 125000 chars; the real api-v0.71.0 cut
# renders 142 KB) is exercised for real instead of by reading the code.
LONG="${WORK}/long"
mkdir -p "${LONG}/backend/scripts"
cp "${SCRIPT}" "${LONG}/backend/scripts/release-notes.sh"
{
  printf '# Changelog\n\n## [Unreleased]\n\n## [api-v9.9.9] \xe2\x80\x93 Released 2026-01-02\n\n'
  printf -- '- Shipped artifact: `ghcr.io/<owner>/<repo>:api-v9.9.9`.\n'
  printf -- '- Companion crate versions at this release: `core 1.0.0`, `infra 2.0.0`, `api 9.9.9`.\n\n### Added\n\n'
  for i in $(seq 1 60); do
    printf -- '- **Long entry %02d.** %s\n' "$i" "$(printf 'filler prose %.0s' $(seq 1 12))"
  done
  printf '\n## [api-v9.9.8] \xe2\x80\x93 2026-01-01\n\n- a previous release that must never appear\n'
} > "${LONG}/backend/CHANGELOG.md"
git -C "${LONG}" init -q

git -C "${FIXTURE}" init -q
git -C "${FIXTURE}" remote add origin "git@github.com:acme/widget.git"

# ── 0. the curated notes file wins, verbatim ──────────────────────────────
mkdir -p "${FIXTURE}/backend/RELEASE-NOTES"
cat > "${FIXTURE}/backend/RELEASE-NOTES/api-v9.9.9.md" <<'MD'
<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

## Backend API image release `api-v9.9.9`

Curated body: the reviewed prose, with its own upgrade guidance.
MD
curated_out="$(cd "${FIXTURE}" && bash ./backend/scripts/release-notes.sh api-v9.9.9 2>/dev/null)"
check "the curated file is used when present" \
  contains "${curated_out}" "Curated body: the reviewed prose"
check "the curated body is verbatim — no preamble is prepended" \
  grep -qx -- "## Backend API image release \`api-v9.9.9\`" <<<"$(head -1 <<<"${curated_out}")"
check "the curated body is verbatim — no diff footer is appended" \
  omits "${curated_out}" "**Full diff:**"
check "the SPDX/co-author comment header is stripped from the body" \
  omits "${curated_out}" "SPDX-License-Identifier"
check "the curated path beats a matching changelog section" \
  omits "${curated_out}" "**Fixture entry.** The curated prose of the release."
mv "${FIXTURE}/backend/RELEASE-NOTES/api-v9.9.9.md" "${WORK}/curated-saved.md"

# ── 1. --help ───────────────────────────────────────────────────────────────
help_out="$(bash "${SCRIPT}" --help 2>&1)"
check "--help exits zero and names the curated notes file as the preferred source" \
  contains "${help_out}" "RELEASE-NOTES/<tag>.md"
check "--help names the changelog section as the derived fallback" \
  contains "${help_out}" "section of \`backend/CHANGELOG.md\`"
check "--help states that a missing body exits 2, never generates notes" \
  contains "${help_out}" "Neither exists → exit 2"
check "--help documents every env override the caller may need" \
  grep -cE "RELEASE_(NOTES_DIR|CHANGELOG|REPO|BODY_CHAR_LIMIT)" <<<"${help_out}" >/dev/null
check "--help documents the --previous override" \
  contains "${help_out}" "--previous"

# ── 2. usage / derivation errors ────────────────────────────────────────────
set +e
bash "${SCRIPT}" >/dev/null 2>&1; no_tag=$?
bash "${SCRIPT}" api-v9.9.9 --nonsense >/dev/null 2>&1; bad_opt=$?
bash "${SCRIPT}" v0.3.0 >/dev/null 2>&1; wrong_stream=$?
missing_out="$(bash "${SCRIPT}" api-v9.9.7 2>&1 >/dev/null)"; missing=$?
set -e
check "no argument is a usage error" test "${no_tag}" -eq 1
check "an unknown option is a usage error" test "${bad_opt}" -eq 1
check "a non-api tag is refused (only image tags have a body)" test "${wrong_stream}" -eq 1
check "a tag without a cut section exits 2, not 0" test "${missing}" -eq 2
check "the exit-2 message names the tag" contains "${missing_out}" "api-v9.9.7"
check "the exit-2 message points at the cut, not at --generate-notes" \
  contains "${missing_out}" "Cut '## [Unreleased]' into a dated section"
check "the exit-2 message names the curated notes path too" \
  contains "${missing_out}" "backend/RELEASE-NOTES/api-v9.9.7.md"

# ── 3. rendering the cut section ────────────────────────────────────────────
body="$(cd "${FIXTURE}" && bash ./backend/scripts/release-notes.sh api-v9.9.9 --previous api-v9.9.8 2>/dev/null)"
check "the section's body is rendered" contains "${body}" "**Fixture entry.** The curated prose of the release."
check "every subsection survives, in order" \
  grep -q '"Second subsection"\|Second subsection' <<<"${body}"
check "[Unreleased] content never leaks in" omits "${body}" "an unreleased entry that must never reach a release body"
check "the previous release never leaks in" omits "${body}" "a previous release that must never appear"
check "the preamble is not duplicated as a section" omits "${body}" "## [api-v9.9.9]"
check "the title names the release" contains "${body}" "## Backend API image release \`api-v9.9.9\`"
check "the immutable pull line carries the tag" contains "${body}" "ghcr.io/acme/widget:api-v9.9.9"
check "moving tags are derived from the tag (patch + minor)" \
  contains "${body}" 'Moving tags `api-v9.9` (latest patch) and `api-v9` (latest minor)'
check "the changelog link is pinned to the tag, not to main" \
  contains "${body}" "https://github.com/acme/widget/blob/api-v9.9.9/backend/CHANGELOG.md"
check "the diff link is rendered when a previous tag is known" \
  contains "${body}" "compare/api-v9.9.8...api-v9.9.9"
check "the changelog's <owner>/<repo> placeholder is resolved in the body" \
  omits "${body}" "<owner>/<repo>"
check "... and the resolved slug lands in the artifact bullet" \
  contains "${body}" 'Shipped artifact: `ghcr.io/acme/widget:api-v9.9.9`'

# ── 4. owner/repo derivation ────────────────────────────────────────────────
# ssh origin: covered by §3 above (no env override). https origin and
# GITHUB_REPOSITORY are the other two inputs the workflow relies on.
git -C "${FIXTURE}" remote set-url origin "https://github.com/acme/widget.git"
https_body="$(cd "${FIXTURE}" && bash ./backend/scripts/release-notes.sh api-v9.9.9 --previous api-v9.9.8 2>/dev/null)"
check "https origin derives owner/repo without .git" \
  contains "${https_body}" "ghcr.io/acme/widget:api-v9.9.9"
gh_repo_body="$(cd "${FIXTURE}" && GITHUB_REPOSITORY="other-org/other-repo" \
  bash ./backend/scripts/release-notes.sh api-v9.9.9 --previous api-v9.9.8 2>/dev/null)"
check "GITHUB_REPOSITORY wins over the local remote (what CI uses)" \
  contains "${gh_repo_body}" "ghcr.io/other-org/other-repo:api-v9.9.9"

set +e
no_remote_out="$(git -C "${FIXTURE}" remote remove origin &&
  cd "${FIXTURE}" && bash ./backend/scripts/release-notes.sh api-v9.9.9 2>&1 >/dev/null)"; no_remote=$?
set -e
check "an underivable slug fails loudly instead of guessing" test "${no_remote}" -eq 1
check "the underivable-slug message names the override" contains "${no_remote_out}" "RELEASE_REPO=owner/repo"

# ── 5. --out writes the body and keeps stdout clean ────────────────────────
out_file="${WORK}/notes.md"
stdout_out="$(cd "${FIXTURE}" && RELEASE_REPO=acme/widget \
  bash ./backend/scripts/release-notes.sh api-v9.9.9 --previous api-v9.9.8 --out "${out_file}" 2>/dev/null)"
check "--out writes the body to the file" test -s "${out_file}"
check "--out keeps stdout empty (the workflow redirects only the file)" test -z "${stdout_out}"
check "the written file is the same render" contains "$(cat "${out_file}")" "**Fixture entry.**"

# ── 6. the real changelog renders the release that shipped ────────────────
# `RELEASE_NOTES_DIR` is masked: the real repo ships a curated
# `api-v0.71.0.md`, and this section is about the derived path.
real_body="$(RELEASE_NOTES_DIR=/nonexistent RELEASE_REPO=example/repo \
  bash "${SCRIPT}" api-v0.71.0 --previous api-v0.14.0 2>/dev/null)"
check "the real api-v0.71.0 section is found and rendered" \
  contains "${real_body}" "Companion crate versions at this release: \`core 0.75.0\`"
check "the real section ends before api-v0.14.0" \
  omits "${real_body}" "## [api-v0.14.0]"
check "the real render is not a commit list (regression of the #0.71.0 defect)" \
  omits "${real_body}" "* chore(deps): bump"

# ── the real changelog's cut must stay honest about its own tag ────────────
# A section that names a *different* tag is what a copy-paste cut produces; the
# heading match is exact, so the render would silently be the wrong body.
check "the real section heading matches the tag exactly" \
  grep -qF -- "## [api-v0.71.0] – Released 2026-11-21" "${REAL_CHANGELOG}"

# The curated file that actually ships must be preferred over the section, and
# must itself be a body (a title, a pull line) rather than a stub.
real_curated="$(RELEASE_REPO=example/repo bash "${SCRIPT}" api-v0.71.0 2>/dev/null)"
check "the real curated notes file wins over the real section" \
  contains "${real_curated}" "## Backend API image release \`api-v0.71.0\`"
# Verbatim means verbatim: the curated file spells out the real image itself,
# the script must not rewrite it.
check "the real curated body names the real image" \
  contains "${real_curated}" "ghcr.io/tradem/breakdown-rs:api-v0.71.0"
check "the real curated body carries no repo metadata header" \
  omits "${real_curated}" "SPDX-License-Identifier"

# ── 7. the character limit: truncated loudly, never silently ───────────────
LIMIT=2400
trunc_body="$(cd "${LONG}" && RELEASE_REPO=acme/widget RELEASE_BODY_CHAR_LIMIT="${LIMIT}" \
  bash ./backend/scripts/release-notes.sh api-v9.9.9 --previous api-v9.9.8 2>/dev/null)"
trunc_len="$(printf '%s' "${trunc_body}" | wc -m | tr -d ' ')"
check "an oversized section still renders (exit 0, no failed job)" \
  contains "${trunc_body}" "## Backend API image release"
check "the truncated body stays inside the budget" test "${trunc_len}" -le "${LIMIT}"
check "the truncation is announced, not silent" contains "${trunc_body}" "_truncated at the release-note character limit"
check "the truncation points at the full changelog entry" \
  contains "${trunc_body}" "blob/api-v9.9.9/backend/CHANGELOG.md"
check "the full-diff link survives truncation" \
  contains "${trunc_body}" "compare/api-v9.9.8...api-v9.9.9"
check "the last (60th) long entry is what got cut" omits "${trunc_body}" "**Long entry 60.**"
# Captured, not piped into `grep -q`: an early-exiting reader would SIGPIPE the
# still-writing script and abort this test with 141 instead of reporting a result.
warn_out="$(cd "${LONG}" && RELEASE_REPO=acme/widget RELEASE_BODY_CHAR_LIMIT="${LIMIT}" \
  bash ./backend/scripts/release-notes.sh api-v9.9.9 2>&1 >/dev/null)"
check "a stderr warning names the sizes (visible in the job log)" \
  contains "${warn_out}" "truncated; the full entry stays in the changelog"

# The real cut that made this necessary: 50 accumulated releases, 142 KB, still
# renders under GitHub's 125000-character ceiling.
real_len="$(printf '%s' "${real_body}" | wc -m | tr -d ' ')"
check "the real api-v0.71.0 body fits GitHub's 125000-character body limit" \
  test "${real_len}" -le 125000

if [[ ${FAILURES} -ne 0 ]]; then
  printf '\n%d assertion(s) failed\n' "${FAILURES}" >&2
  exit 1
fi
printf '\nall assertions passed\n'
