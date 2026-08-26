---
name: flutter-coderabbitai-review
description: Systematically read, evaluate, and respond to CodeRabbitAI review comments on GitHub PRs that touch the Flutter frontend (frontend-flutter/). Use when a PR has CodeRabbitAI feedback that needs to be addressed, adapted to Dart/Flutter verification steps.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub and the Flutter/Dart SDK.
metadata:
  author: breakdown-rs
  version: "1.0"
  provenance: |
    Ported from backend/.pi/skills/coderabbitai-review (Rust/cargo
    workflow), adapted to the frontend-flutter conventions in AGENTS.md.
    The 1:1 threaded-reply spine and gh API calls are language-agnostic and
    preserved verbatim; only the fix-verification step (cargo → flutter/dart)
    and the git staging paths (Rust crates → frontend-flutter/) are
    Dart/Flutter-specific.
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy3 (opencode-go) -->

# CodeRabbitAI Review Response (Flutter port)

Systematically process CodeRabbitAI review comments on **Flutter frontend**
PRs, evaluate their validity, implement justified fixes, and respond to each
comment.

> **Language note:** This is the Dart/Flutter port of the backend
> `coderabbitai-review` skill. The threaded-reply protocol (Step 1/2/4/6) and
> all `gh` API calls are language-agnostic and reused unchanged. Only Step 3
> (verify with `flutter`/`dart` instead of `cargo`) and Step 5 (stage
> `frontend-flutter/` paths, regenerate codegen instead of editing
> `Cargo.toml`) are Flutter-specific.

## Core Rule: 1:1 Threaded Replies Are Mandatory

CodeRabbit tracks resolution **per comment thread**. A single top-level
summary comment ("I addressed everything") does **not** resolve any thread —
the PR stays in `CHANGES_REQUESTED` and the reviewer must run another
approval cycle.

Therefore, for **every** CodeRabbit comment you must post **exactly one
threaded reply** via the GitHub replies endpoint, prefixed with the status
vocabulary (`Fixed:` / `Deferred:` / `Not applicable:`). The top-level
re-review request (Step 6) is **additive** — it is never a substitute for
per-comment replies.

## When to Use

- PR touching `frontend-flutter/` has CodeRabbitAI review comments
- Need to address reviewer feedback before merge
- Want to ensure all comments are properly responded to

## Prerequisites

- `gh` CLI installed and authenticated
- `jq` installed (used by the `--jq` comment streams in Step 1 and the Step 4
  coverage aggregation)
- PR number or branch name

## Workflow

### Step 1: Read All Review Comments (primary + replies)

Fetch the **CodeRabbit primary comments** (and keep the full stream so you
can see existing replies and know which threads are already resolved):

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate --jq '
  .[] | select(.in_reply_to_id == null and .user.login == "coderabbitai[bot]")
  | {id: .id, path: .path, line: .line, body: .body}'
```

- Only comments with `in_reply_to_id == null` and author
  `coderabbitai[bot]` are **primary comments** — each one needs your reply.
  Human comments and CodeRabbit replies are ignored for the thread gate.
- A comment is already handled when it has a child reply from you; skip
  replying twice.
- If CodeRabbit has already withdrawn a finding (its reply contains
  `<review_comment_withdrawn>` or "I withdraw"), still reply
  `Not applicable: withdrawn by reviewer` — never leave the thread silent.

### Step 2: Categorize Comments

For each comment, classify using exactly one of these three statuses:

- **Fixed**: Justified, will implement now
- **Deferred**: Valid but tracked in separate issue
- **Not applicable**: False positive or not relevant

### Step 3: Implement Fixes (Flutter/Dart verification)

For each "Fixed" comment:

1. Read the affected file under `frontend-flutter/lib/` (or `test/`,
   `features-spec/`, `pubspec.yaml`, `analysis_options.yaml`).
2. Understand the suggestion.
3. Implement the fix.
4. Verify with the Dart/Flutter toolchain:

```bash
cd frontend-flutter
# If a codegen input changed (annotation / openapi.yaml / drift schema),
# regenerate generated sources FIRST so the analysis/test below see them:
dart run build_runner build --delete-conflicting-outputs
# Then verify with the Dart/Flutter toolchain:
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

- Respect the **rebuild-only** rule (AGENTS.md §2/§3/§9): never hand-edit
  `lib/api/generated/`, `*.g.dart`, or `*.freezed.dart`. Regenerate instead.
- If the comment concerns a generated file, fix the source annotation/spec
  and regenerate — do **not** patch the generated output.

### Step 4: Reply 1:1 to Every Comment (mandatory)

For EVERY CodeRabbit comment — `Fixed`, `Deferred`, or `Not applicable` —
post a **threaded** reply. Never replace these with a single summary comment.

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  -f body="Fixed: [what was changed]"

gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  -f body="Not applicable: [reason]"
```

**Reply format** — the status word MUST be the first token of the reply:

- `Fixed: [what was changed]`
- `Deferred: [reason]. Tracked in issue #[number].`
- `Not applicable: [reason]`

After posting all replies, **verify thread coverage** — every CodeRabbit
primary comment must have **exactly one** direct reply from you that starts
with the status vocabulary. The check aggregates the full (paginated)
comment stream first, so parent/child relationships are evaluated against the
whole collection, never per-object:

```bash
set -o pipefail
coverage="$(gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate --jq '.[]' \
  | jq -s -r --arg me "$(gh api user --jq .login)" '
      . as $all
      | $all[]
      | select(.in_reply_to_id == null and .user.login == "coderabbitai[bot]") as $primary
      | [ $all[] | select(.in_reply_to_id == $primary.id and .user.login == $me
          and (.body | test("^(Fixed|Deferred|Not applicable):"))) ] as $replies
      | if ($replies | length) != 1 then
          "UNREPLIED_OR_DUPLICATE \($primary.id): \($primary.path) (status-replies=\($replies|length))"
        else empty
        end')"
printf '%s\n' "$coverage"
test -z "$coverage"   # fail-closed: any output ⇒ return to Step 4, do NOT proceed
```

The output must be empty. `UNREPLIED_OR_DUPLICATE` means the thread has zero
or more than one **status-prefixed** reply from you — a missing answer, a
reply that does not start with `Fixed:` / `Deferred:` / `Not applicable:`,
or contradictory status replies. Only replies whose body starts with the
status vocabulary count; discussion replies (e.g. your clarifying question)
are ignored. Go back and fix the thread before continuing.

### Step 5: Commit and Push

```bash
cd frontend-flutter
# Stage ALL files modified for this review (source, tests, docs, skills, etc.)
git add lib/features/{feature}/{file}.dart
git add lib/features/{feature}/{file}_test.dart
git add features-spec/{scope}.feature
git add pubspec.yaml
git add lib/api/generated/          # only if regenerated this review
git add ../frontend-flutter/.pi/skills/{skill}/SKILL.md

# Inspect what will be committed
git diff --cached

# Commit with conventional message
git commit -m "fix: address CodeRabbitAI review feedback (frontend-flutter)

- [List of fixes]

Co-authored-by: [model] ([provider])"

# Push
git push
```

Note: `frontend-flutter` is a single app package — there is no `Cargo.toml`
to bump by hand. If a generated artifact changed, commit the regenerated diff
(already staged above); do not hand-edit it.

### Step 6: Verify Coverage, Then Request Re-review

1. Re-run the Step 4 coverage check — it must print no
   `UNREPLIED_OR_DUPLICATE` lines.
2. Only then post the top-level re-review request (additive, after all
   replies exist):

```bash
gh pr comment {pr} --body "@coderabbitai I replied to every comment thread (Fixed/Deferred/Not applicable). Could you please re-review?"
```

If any thread still fails the coverage check, return to Step 4 — do **not**
request re-review.

## Comment Response Templates

### Fixed

```text
Fixed: [Brief description of what was changed].

[Optional: Reference to commit or file changes]
```

### Deferred

```text
Deferred: [Reason for deferring].

Tracked in issue #[number]. [Brief explanation of why it's a separate concern].
```

### Not Applicable

```text
Not applicable: [Reason why this doesn't apply].

[Explanation of current behavior or why the suggestion isn't relevant]
```

## Common CodeRabbitAI Patterns

| Pattern | Typical Response |
|---------|------------------|
| "Document X" | Fixed |
| "Add test for Y" | Deferred (if complex) |
| "Use freezed union for Z" | Fixed (if justified) |
| "Merge duplicate headers" | Fixed |
| "Do not echo secrets" | Fixed (security) |
| "Add AUTHZ-GATE check" | Fixed (mirror backend `// AUTHZ-GATE:` rule) |
| "Add drift migration" | Deferred (schema follow-up) |
| Already withdrawn by CodeRabbit | Not applicable (withdrawn by reviewer) |

## Guardrails

- **1:1 threaded replies are mandatory** — never substitute a single
  summary comment for per-comment replies; a summary alone does not resolve
  CodeRabbit threads
- **Use consistent status vocabulary** as the first token of every reply:
  Fixed, Deferred, or Not applicable
- **Reply to EVERY comment** — including withdrawn ones — before requesting
  re-review
- **Verify thread coverage** (no `UNREPLIED_OR_DUPLICATE` lines) before
  posting the re-review request
- **Stage only intended files** — do not use `git add -A`
- **Verify fixes pass** `flutter analyze` + `flutter test` (+ `build_runner`
  if codegen inputs changed) before committing
- **Never hand-edit generated files** (`lib/api/generated/`, `*.g.dart`,
  `*.freezed.dart`) — regenerate instead
- **Use conventional commit messages**
