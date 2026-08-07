---
name: coderabbitai-review
description: Systematically read, evaluate, and respond to CodeRabbitAI review comments on GitHub PRs. Use when a PR has CodeRabbitAI feedback that needs to be addressed.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub.
metadata:
  author: breakdown-rs
  version: "1.1"
---

# CodeRabbitAI Review Response

Systematically process CodeRabbitAI review comments, evaluate their validity, implement justified fixes, and respond to each comment.

## When to Use

- PR has CodeRabbitAI review comments
- Need to address reviewer feedback before merge
- Want to ensure all comments are properly responded to

## Prerequisites

- `gh` CLI installed and authenticated
- PR number or branch name

## Workflow

### Step 1: Read All Review Comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | {id: .id, path: .path, line: .line, body: .body[0:800]}'
```

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

### Step 4: Reply to Each Comment

```bash
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  -f body="Fixed/Deferred/Not applicable: [explanation]"
```

**Reply format** (must match categorization exactly):

- `Fixed: [what was changed]`
- `Deferred: [reason]. Tracked in issue #[number].`
- `Not applicable: [reason]`

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

### Step 6: Request Re-review

```bash
gh pr comment {pr} --body "@coderabbitai I've addressed all actionable comments. Could you please re-review?"
```

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

## Guardrails

- **Use consistent status vocabulary**: Fixed, Deferred, or Not applicable
- **Reply to EVERY comment** — never leave comments unanswered
- **Stage only intended files** — do not use `git add -A`
- **Verify fixes compile** before committing
- **Use conventional commit messages**
