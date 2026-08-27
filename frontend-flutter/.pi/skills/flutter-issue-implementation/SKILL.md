---
name: flutter-issue-implementation
description: Systematically implement a GitHub issue for the Flutter frontend (frontend-flutter/) from analysis to PR. Use when starting work on an issue to ensure no drift and proper implementation, adapted to Dart/Flutter conventions.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub and the Flutter/Dart SDK.
metadata:
  author: breakdown-rs
  version: "1.0"
  provenance: |
    Ported from backend/.pi/skills/issue-implementation (Rust/Cargo
    workflow), adapted to the frontend-flutter conventions in AGENTS.md —
    Dart/Flutter toolchain, Riverpod/freezed/drift codegen, OpenSpec
    change proposals, and SPDX headers per §10. The threaded issue→PR
    structure is preserved; crate-specific steps (cargo, Cargo.toml bumps)
    are replaced by their Dart/Flutter equivalents.
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# Flutter Issue Implementation Workflow

Systematically implement a GitHub issue for the **Flutter frontend**:
analyze, check for drift, plan, create branch, implement, test, and create PR.

> **Language note:** This is the Dart/Flutter port of the backend
> `issue-implementation` skill. Where the backend uses `cargo` / `Cargo.toml`
> / crate version bumps, this skill uses `flutter` / `dart` / codegen
> regeneration and `pubspec.yaml`. The issue→branch→plan→PR spine is
> unchanged.

## When to Use

- Starting work on a new issue against the `frontend-flutter/` app
- Want to ensure no drift from existing Flutter implementations
- Need a systematic approach from issue to PR

## Prerequisites

- `gh` CLI installed and authenticated
- Issue number
- Clean working tree
- Flutter/Dart SDK available (for verify steps)

## Workflow

### Step 1: Read and Analyze the Issue

```bash
# Fail immediately if issue cannot be retrieved
if ! gh issue view {issue}; then
  echo "Issue lookup failed" >&2
  exit 1
fi
```

**Critical reflection:**

- What does the issue ask for?
- Are there similar implementations already in `frontend-flutter/lib/`?
- Could there be drift (issue describes already-implemented features)?

### Step 2: Check for Drift

```bash
# Search for related code (ast-bro resolves Dart too)
analyze_ast_search --query "[keywords from issue]" --mode summary

# Inspect the affected feature/aggregate folder
analyze_ast_context --path "frontend-flutter/lib/features/[affected]"
```

**Ask user if drift detected:**

> "Issue #X mentions [feature], but I found [existing implementation in
> frontend-flutter/lib/...]. Should I proceed with [approach A] or
> [approach B]?"

`analyze_ast_search` and the other ast-bro tools operate repo-wide; they
resolve Dart symbols, so prefer them over raw `grep` for drift checks.

### Step 3: Create Feature Branch

```bash
git checkout -b feature/{issue}-{short-description}
```

**Branch naming:**

- `feature/{issue}-{kebab-case-description}`
- Example: `feature/174-seasons-screen-optimistic-update`

### Step 4: Create Implementation Plan

Use the **AskUser tool** if architectural decisions are needed (layer
placement, Riverpod provider shape, optimistic-update strategy):

```json
{
  "question": "Which approach should we use for [decision]?",
  "context": "[Current state and constraints]",
  "options": [
    {"title": "Option A", "description": "..."},
    {"title": "Option B", "description": "..."}
  ]
}
```

Write the plan to an OpenSpec proposal. Flutter change artifacts live at the
monorepo OpenSpec root:

```text
openspec/changes/{issue}-{description}/proposal.md
```

(See `frontend-flutter/AGENTS.md` §Cross-references, Decision Q3 → c.)

### Step 5: Implement

1. Create/modify files as planned under `frontend-flutter/lib/`
   (`core/`, `data/`, `domain/`, `features/`, `design/`, `routing/`,
   `auth/`).
2. Add language-appropriate SPDX headers (AGENTS.md §10):

**Dart files:**

```dart
// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: [model] ([provider])
```

**YAML files (`pubspec.yaml`, `analysis_options.yaml`):**

```yaml
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: [model] ([provider])
```

**Markdown / Gherkin `.feature` files:**

```markdown
<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: [model] ([provider]) -->
```

3. Respect the **rebuild-only** rule (AGENTS.md §2 / §3 / §9): never hand-edit
   `lib/api/generated/`, `*.g.dart`, or `*.freezed.dart`. Regenerate instead.
4. Run checks frequently during implementation:

```bash
# Only run the Dart/Flutter toolchain when this is a code change
# (pubspec.yaml present). OpenSpec-only / markdown changes have no Flutter
# package to build, so guard the checks behind it.
if [ -f frontend-flutter/pubspec.yaml ]; then
  cd frontend-flutter
  dart format --set-exit-if-changed .
  flutter analyze
  flutter test
  # Regenerate drift/freezed/riverpod codegen when an annotation or drift
  # schema changed (distinct from the OpenAPI client below):
  dart run build_runner build --delete-conflicting-outputs
  cd ..
fi

# Regenerate the OpenAPI client ONLY when backend/openapi.yaml actually
# changed vs the base branch (NOT merely because the file exists). Use
# openapi-generator-cli (NOT build_runner) per AGENTS.md §3.
# First resolve the base revision, then determine whether the schema
# changed; only then require `npx`. Do NOT fall back to HEAD: if the base
# cannot be resolved, committed changes relative to the intended base would
# appear unchanged and regeneration would be silently skipped.
if [ -f backend/openapi.yaml ]; then
  base="${BASE_BRANCH:-origin/main}"
  if ! merge_base="$(git merge-base HEAD "$base" 2>/dev/null)"; then
    echo "ERROR: cannot resolve merge-base between HEAD and '$base'; cannot determine whether backend/openapi.yaml changed. Set BASE_BRANCH explicitly or fetch the upstream ref." >&2
    exit 1
  fi
  if ! git diff --quiet "$merge_base" -- backend/openapi.yaml 2>/dev/null; then
    if ! command -v npx >/dev/null 2>&1; then
      echo "ERROR: backend/openapi.yaml changed but npx is unavailable; cannot regenerate the OpenAPI client. Install Node.js/npm or regenerate manually." >&2
      exit 1
    fi
    (cd frontend-flutter && npx @openapitools/openapi-generator-cli generate \
      -i ../backend/openapi.yaml -g dart -o lib/api/generated \
      --additional-properties=pubName=breakdown_api)
  fi
fi
```

### Step 6: Track Affected Packages / Generated Artifacts

Dart has no publishable-crate workspace. The app is a single `pubspec.yaml`
package; the OpenAPI client (`breakdown_api`) and all `*.g.dart` /
`*.freezed.dart` outputs are **codegen-owned** and regenerated, not version
-bumped by hand.

Record every affected package/artifact in a table — mandatory, even when
nothing changed (the table then states `none` explicitly):

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | bump 1.2.0 → 1.3.0 | New custom feature / dep addition |
| `breakdown_api` (`lib/api/generated/`) | regenerated via `openapi-generator-cli` | `backend/openapi.yaml` changed |
| `*.g.dart` / `*.freezed.dart` | regenerated | `@freezed` / `@riverpod` / drift edits |
| (none) | — | Pure logic change in `lib/core/` |

Keep the table in the implementation notes and reuse it verbatim in the PR
body (Step 9) and the final report (Step 11).

### Step 7: Create Issues for Follow-ups

```bash
gh issue create --title "[type]: [description]" --body "## Summary
[Description]

## Problem
[Why this is needed]

## Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Depends On
- Issue #{prerequisite}"
```

### Step 8: Commit

```bash
cd frontend-flutter
# Stage all files selected by the implementation plan.
# Include: source (.dart), tests, pubspec.yaml, generated regen diffs,
# OpenSpec proposal, skill files, etc.
git add lib/core/.../file.dart
git add lib/features/.../file.dart
git add lib/features/.../file_test.dart
git add pubspec.yaml
git add lib/api/generated/            # only if regenerated this change
git add ../openspec/changes/{issue}-*/proposal.md
git add ../frontend-flutter/.pi/skills/{skill}/SKILL.md

# Inspect what will be committed
git diff --cached

# Commit with conventional message
git commit -m "{type}: {description} (issue #{number})

{Detailed description}

Co-authored-by: [model] ([provider])"
```

**Commit message format:**

- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation
- `refactor:` code refactoring
- `test:` adding tests
- `chore:` codegen regeneration / dependency bumps

### Step 9: Push and Create PR

```bash
git push -u origin {branch}

gh pr create --title "{type}: {description} (issue #{number})" --body "[PR description]"
```

The PR body MUST include:

1. A **Summary** and **Changes** section (what / why).
2. The **affected-packages / generated-artifacts table** from Step 6, verbatim.
3. A **Validation** section (`dart format`, `flutter analyze`, `flutter test`,
   and — if codegen ran — `build_runner` / OpenAPI drift check results).
4. Acceptance criteria checkboxes from the issue.

Example PR body sections:

```markdown
## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | bump 1.2.0 → 1.3.0 | New custom feature |
| `breakdown_api` | regenerated | `backend/openapi.yaml` changed |

## Validation
- `dart format --set-exit-if-changed .`: clean
- `flutter analyze`: clean
- `flutter test`: N passed
- OpenAPI drift check: no diff
```

### Step 10: Link Issues

```bash
# Close the issue only AFTER the PR merges (post-merge step: via the merge
# hook/CI, or manually once merged) — do not close it as part of local impl.
gh issue close {issue} --comment "Closed by PR #{pr}"

# Mark follow-up issues
gh issue comment {followup} --body "Follow-up to issue #{issue} (PR #{pr})."
```

### Step 11: Final Report

Close the implementation with a structured report in your final response.
Always include the affected-packages / generated-artifacts table (Step 6),
even when nothing changed:

```markdown
## Implementierungs-Report (Issue #{issue})

**Branch:** `{branch}` → **PR:** [#{pr}]({url})

| Schritt | Ergebnis |
|---|---|
| Drift-Check | ... |
| Tests | `flutter test`: N passed |
| Lints | `flutter analyze`: clean |
| Format | `dart format --set-exit-if-changed .`: clean |
| Guardrails | generated files: regenerated, not hand-edited |

### Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | bump 1.2.0 → 1.3.0 | New custom feature |
| (none) | — | Pure logic change in `lib/core/` |
```

If any package/artifact changed, state the action and justification; if none
changed, write `none` explicitly so the reviewer can see the decision was made
deliberately, not skipped.

## Guardrails

- **Fail immediately** if issue lookup fails
- **Always check for drift** before implementing
- **Ask user** for architectural decisions
- **Test/format/analyze frequently** during implementation
- **Use conventional commits**
- **Create follow-up issues** for deferred work
- **Use language-appropriate SPDX headers** (Dart `//`, YAML `#`, md `<!-- -->`)
- **Never hand-edit generated files** — regenerate (`build_runner` /
  openapi-generator) instead
- **Never skip the affected-packages table** in Step 6, the PR body (Step 9),
  and the final report (Step 11) — an explicit `none` beats an omission
