---
name: coderabbitai-review
description: Systematically read, evaluate, and respond to CodeRabbitAI review comments on GitHub PRs. Use when a PR has CodeRabbitAI feedback that needs to be addressed.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub.
metadata:
  author: breakdown-rs
  version: "1.0"
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
# Get all CodeRabbitAI comments
gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | {id: .id, path: .path, line: .line, body: .body[0:800]}'
```

### Step 2: Categorize Comments

For each comment, classify as:
- **Fixed**: Justified, will implement
- **Deferred**: Valid but tracked in separate issue
- **Rejected**: False positive, not applicable

### Step 3: Implement Fixes

For each "Fixed" comment:
1. Read the affected file
2. Understand the suggestion
3. Implement the fix
4. Verify with `cargo check`, `cargo test`, `cargo clippy`

### Step 4: Reply to Each Comment

```bash
# Reply to a specific comment
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies \
  -f body="Fixed/Deferred: [explanation]"
```

**Reply format:**
- Start with status: `Fixed:`, `Deferred:`, or `Not applicable:`
- Brief explanation of what was done or why deferred
- Reference to issue if deferred

### Step 5: Commit and Push

```bash
git add -A
git commit -m "fix: address CodeRabbitAI review feedback

- [List of fixes]

Co-authored-by: [model] ([provider])"
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
| "Document X" | Fix documentation |
| "Add test for Y" | Defer to separate issue if complex |
| "Use ErrorKind::NotFound" | Implement if justified |
| "Merge duplicate headers" | Fix |
| "Do not echo secrets" | Fix security issue |
| "Add reconciliation" | Defer to cleanup worker issue |

## Guardrails

- Always reply to EVERY comment, even if just acknowledging
- Never leave comments unanswered
- Defer complex changes to separate issues with clear description
- Verify fixes compile and pass tests before committing
- Use conventional commit messages
