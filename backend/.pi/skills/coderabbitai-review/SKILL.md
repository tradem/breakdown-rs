---
name: coderabbitai-review
description: Systematically read, evaluate, and respond to CodeRabbitAI review comments on GitHub PRs. Use when a PR has CodeRabbitAI feedback that needs to be addressed.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub.
metadata:
  author: breakdown-rs
  version: "1.4"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# CodeRabbitAI Review Response

Systematically process CodeRabbitAI review comments, evaluate their validity,
implement justified fixes, and respond to each comment.

## Core Rule: 1:1 Threaded Replies Are Mandatory — and the Loop Repeats

CodeRabbit tracks resolution **per comment thread**. A single top-level
summary comment ("I addressed everything") does **not** resolve any thread —
the PR stays in `CHANGES_REQUESTED` and the reviewer must run another
approval cycle.

Therefore, for **every** CodeRabbit comment you must post a **threaded reply**
via the GitHub replies endpoint, prefixed with the status vocabulary
(`Fixed:` / `Deferred:` / `Not applicable:`). The top-level re-review request
(Step 6) is **additive** — it is never a substitute for per-comment replies.

**One reply is not the end of a thread.** CodeRabbit almost always answers
your reply — and that answer is a *review finding of its own*: "I'm not
marking the finding as addressed yet", "the fix introduces a lock-order
conflict", "one issue remains", "the finding still applies to the production
path". Replying once and declaring victory is the single most common way to
leave a PR blocked while all threads *look* answered.

The unit of work is therefore the **thread, not the comment**: a thread is
done when **your status-prefixed reply is its last message** (Step 7). Until
then you owe it another round — read the follow-up, verify it against the
current code, fix or rebut it, and reply again with the status word. Expect two
to four rounds on a large change; treat any round that CodeRabbit answers with
a new objection as unfinished work, not as noise.

## When to Use

- PR has CodeRabbitAI review comments
- Need to address reviewer feedback before merge
- Want to ensure all comments are properly responded to

## Prerequisites

- `gh` CLI installed and authenticated
- PR number or branch name

## Workflow

### Step 1: Read All Review Comments (primary + replies)

Fetch the **CodeRabbit primary comments** *and the full comment stream*: the
replies they carry are the next round's work, and a thread is only finished when
your status reply is its last message (Step 4/7). Keep the whole collection —
the coverage check needs parent/child relationships:

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate --jq '
  .[] | select(.in_reply_to_id == null and .user.login == "coderabbitai[bot]")
  | {id: .id, path: .path, line: .line, body: .body[0:800]}'
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

### Step 3: Implement Fixes

For each "Fixed" comment:

1. Read the affected file
2. Understand the suggestion
3. Implement the fix
4. Verify with `cargo check`, `cargo test`, `cargo clippy`

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

After posting all replies, **verify thread coverage**. The gate is
**round-aware**: a thread is covered when **the last message in it is your
reply and it starts with the status vocabulary** — not when it merely contains
one status reply. An earlier `Fixed:` does not cover a later CodeRabbit
objection.

Why the change: a thread accumulates rounds (`your reply → CodeRabbit's
follow-up → your new reply`). Counting status replies would either block
correct loops ("duplicate") or, worse, pass a thread whose last word was
CodeRabbit's "I'm not marking the finding as addressed yet". Only the final
message decides whether the reviewer still has an open objection.

The check aggregates the full (paginated) comment stream first, so
parent/child relationships are evaluated against the whole collection, never
per-object:

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate --jq '.[]' \
  | jq -s -r --arg me "$(gh api user --jq .login)" '
      . as $all
      | $all[]
      | select(.in_reply_to_id == null and .user.login == "coderabbitai[bot]") as $primary
      | [ $all[] | select(.in_reply_to_id == $primary.id) ] | sort_by(.created_at) as $thread
      | ($thread | last) as $last
      | if ($thread | length) == 0 then
          "NO_REPLY \($primary.id): \($primary.path)"
        elif ($last.user.login == "coderabbitai[bot]") then
          "CODERABBIT_REPLIED_LAST \($primary.id): \($primary.path) — read the follow-up and answer it"
        elif ($last.user.login != $me) then
          "NOT_MINE_LAST \($primary.id): \($primary.path) — last word by \($last.user.login)"
        elif ($last.body | test("^(Fixed|Deferred|Not applicable):") | not) then
          "MISSING_STATUS_WORD \($primary.id): \($primary.path) — your last reply must start with Fixed:/Deferred:/Not applicable:"
        else empty
        end'
```

The output must be empty.

- `NO_REPLY` — you never answered.
- `CODERABBIT_REPLIED_LAST` — **the normal state of an unfinished thread**.
  Read that reply: it either withdraws the finding (then answer
  `Not applicable: withdrawn by reviewer`) or restates it (then go back to
  Step 2/3 for that thread). Never leave CodeRabbit's objection as the last
  word.
- `MISSING_STATUS_WORD` — your reply exists but the reviewer's parser cannot
  see a status; the status word must be the **first token** (`Fixed: …`, not
  `Fixed (…)`, not "Thanks — fixed:").
- `NOT_MINE_LAST` — a human or bot answered after you; if it is a human,
  answer them as well (the status vocabulary is for CodeRabbit threads).

Do not delete or silently rewrite history to satisfy the gate: replying again
with the current status **is** the intended mechanism, and later rounds may
legitimately flip a status (a thread that was `Deferred` can end `Fixed` once
the deferred half is delivered — say so explicitly in the new reply instead of
editing the old one).

### Step 5: Commit and Push

```bash
# Stage ALL files modified for this review (source, tests, docs, skills, etc.)
git add backend/crates/{crate}/src/{file}.rs
git add backend/crates/{crate}/tests/{file}.rs
git add backend/crates/{crate}/Cargo.toml
git add backend/.pi/skills/{skill}/SKILL.md

# Inspect what will be committed
git diff --cached

# Commit with conventional message
git commit -m "fix: address CodeRabbitAI review feedback

- [List of fixes]

Co-authored-by: [model] ([provider])"

# Push
git push
```

### Step 6: Verify Coverage, Then Request Re-review

1. Re-run the Step 4 coverage check — its output must be empty.
2. Only then post the top-level re-review request (additive, after all
   replies exist):

```bash
gh pr comment {pr} --body "@coderabbitai I replied to every comment thread (Fixed/Deferred/Not applicable). Could you please re-review?"
```

If any thread still fails the coverage check, return to Step 4 — do **not**
request re-review.

### Step 7: Poll for the next round (this is where most PRs stall)

A re-review request is a *request*, not a result. CodeRabbit answers each
reply and may file additional findings (sometimes on the fix itself), and the
PR stays `CHANGES_REQUESTED` until its **last submitted review** flips. So the
job ends only when both are true:

```bash
# (a) no thread ends on a CodeRabbit message — run the Step 4 check again
# (b) the newest review by the bot is not CHANGES_REQUESTED
gh api repos/{owner}/{repo}/pulls/{pr}/reviews \
  --jq '[.[] | select(.user.login == "coderabbitai[bot]")] | last | {state, submitted_at}'
```

An acknowledgement that is **not** a review ("I've noted the fixes … I have
not independently verified them") does not clear (b) — the stale
`CHANGES_REQUESTED` review is still the blocking review. Two legitimate exits:

- CodeRabbit submits a fresh review (repeat this step until it does), or
- the repository owner dismisses the stale review, **or** approves it away.
  Say explicitly in the PR that the review is stale, which commits answered it,
  and why the remaining checks are green — never dismiss silently.

Re-poll on a timer while the CI run finishes; a review submitted *before* your
last push reviews the old code and will look unsatisfied for that reason alone.

```bash
# Poll: repeat until no thread ends on CodeRabbit and the last review is not
# CHANGES_REQUESTED. Cite the commit each round answered.
```

Only then post the final summary and hand the PR back.

## Comment Response Templates

### Fixed

```
Fixed: [Brief description of what was changed].

[Optional: Reference to commit or file changes]
```

### Deferred

```
Deferred: [Reason for deferring].

Tracked in issue #[number]. [Brief explanation of why it's a separate concern].
```

### Not Applicable

```
Not applicable: [Reason why this doesn't apply].

[Explanation of current behavior or why the suggestion isn't relevant]
```

## Common CodeRabbitAI Patterns

| Pattern | Typical Response |
|---------|------------------|
| "Document X" | Fixed |
| "Add test for Y" | Deferred (if complex) |
| "Use ErrorKind::NotFound" | Fixed (if justified) |
| "Merge duplicate headers" | Fixed |
| "Do not echo secrets" | Fixed (security) |
| "Add reconciliation" | Deferred (cleanup worker) |
| Already withdrawn by CodeRabbit | Not applicable (withdrawn by reviewer) |
| "I'm not marking the finding as addressed yet" + a new objection | Fixed (it is a new finding — fix it, then reply again) |
| "the fix introduces/reveals …" | Fixed (the fix itself is the finding; verify the claim first) |
| Follow-up asks for a test of the exact sequence | Fixed (add it; a unit test through a fake is not the sequence) |
| "I recommend …" (advisory, not the finding) | Fixed or Not applicable — state which and why, never leave it unanswered |

## Guardrails

- **1:1 threaded replies are mandatory** — never substitute a single
  summary comment for per-comment replies; a summary alone does not resolve
  CodeRabbit threads
- **Read CodeRabbit's replies to your replies** — the bot's follow-up is a
  finding, not a receipt. A thread you consider "answered" but which ends on
  "I'm not marking the finding as addressed yet" is open work
- **The gate is the last message, not a count** — one `Fixed:` does not cover a
  later objection; answer each round with a fresh status reply
- **A stale `CHANGES_REQUESTED` review is not a resolved review** — check the
  bot's newest review state, not only the thread coverage
- **Use consistent status vocabulary** as the first token of every reply:
  Fixed, Deferred, or Not applicable
- **Reply to EVERY comment** — including withdrawn ones — before requesting
  re-review
- **Verify thread coverage** (no `UNREPLIED_OR_DUPLICATE` lines) before
  posting the re-review request
- **Stage only intended files** — do not use `git add -A`
- **Verify fixes compile** before committing
- **Use conventional commit messages**
