---
name: pr-lifecycle
description: Manage the full lifecycle of a GitHub PR from creation to merge. Use when creating PRs, linking issues, managing reviews, and handling follow-ups.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub.
metadata:
  author: breakdown-rs
  version: "1.0"
---

# PR Lifecycle Management

Manage PRs from creation through review to merge, including issue linking, follow-up tracking, and reviewer coordination.

## When to Use

- Creating a new PR
- Need to link issues properly
- Managing reviewer feedback
- Tracking follow-up work

## Prerequisites

- `gh` CLI installed and authenticated
- Changes committed on feature branch

## Workflow

### Step 1: Pre-PR Checklist

Before creating PR, verify:

```bash
# Tests pass
cargo test -p [affected-crates]

# Linting clean
cargo clippy -p [affected-crates]

# Formatting correct
cargo fmt --check

# Architecture tests pass (if applicable)
cargo test -p architecture_tests
```

### Step 2: Create PR with Rich Description

```bash
gh pr create --title "{type}: {description} (issue #{number})" --body "## Summary

[1-2 sentence summary]

Fixes #{issue}

## Problem

[What problem does this solve?]

## Solution

[How does this solve it?]

## Key Changes

- **New [thing]**: [description]
- **Changed [thing]**: [description]
- **Fixed [thing]**: [description]

## Testing

- [What tests were added/updated]
- [Test results]

## Follow-up Issues

- #{issue}: [Description]
- #{issue}: [Description]

## Crate Version Bumps (if applicable)

- \`crate\`: X.Y.Z → X.Y.Z (reason)

---

Co-authored-by: [model] ([provider])"
```

### Step 3: Link Issues

**Close issue when PR merges:**
```bash
gh issue close {issue} --comment "Closed by PR #{pr}: {title}"
```

**Mark follow-up issues:**
```bash
gh issue comment {followup} --body "Follow-up to issue #{original} (closed by PR #{pr}). [Description of what this issue tracks]."
```

### Step 4: Manage Reviews

**Request review:**
```bash
gh pr request-review {pr} --reviewer {username}
```

**Respond to review comments:**
```bash
# See coderabbitai-review skill for detailed workflow
```

**Dismiss stale reviews (if needed):**
```bash
gh pr dismiss-review {pr} --reason "Changes addressed feedback"
```

### Step 5: Bump Crate Versions & Update Changelogs

When modifying crate APIs, bump versions and update changelogs per ADR-020.

**Version Bump Rules (ADR-020):**
- **MINOR**: Additive public API changes (new traits, new methods, new types)
- **PATCH**: Bug fixes, internal changes, consumption of new infra API
- **MAJOR**: Breaking changes (avoid in major-zero crates)

**Files to update:**

```bash
# 1. Bump version in Cargo.toml
crates/{crate}/Cargo.toml

# 2. Update CHANGELOG.md
crates/{crate}/CHANGELOG.md

# 3. Re-pin dependencies in consuming crates
crates/{consumer}/Cargo.toml  # version = "X.Y.Z"
```

**Changelog format:**

```markdown
## [X.Y.Z] - Unreleased

### Added

- New feature description (issue #{number})

### Changed

- Change description (issue #{number})

### Fixed

- Bug fix description (issue #{number})

- Re-pins `{crate}` to X.Y.Z (description; under major-zero semver this is a PATCH/MINOR bump, ADR-020 D2/D3).
```

**Dependency chain example:**

```
core 0.5.0 (new trait)
  ↓
infra 0.8.0 → 0.9.0 (consumes core, adds new trait)
  ↓
api 0.4.4 → 0.4.5 (consumes infra)
```

**Validation:**

```bash
cargo check --workspace
cargo test -p [affected-crates]
```

### Step 6: Handle CI Failures

```bash
# Check CI status
gh pr checks {pr}

# View failed job logs
gh run view {run-id} --log-failed
```

**Common fixes:**
- Formatting: `cargo fmt`
- Linting: `cargo clippy --fix`
- Tests: Fix failing tests

### Step 7: Merge

```bash
# Squash merge (default for feature branches)
gh pr merge {pr} --squash --delete-branch

# Or merge commit
gh pr merge {pr} --merge --delete-branch
```

**Merge message format:**
```
{type}: {description} (issue #{number})

{Body from PR}

Co-authored-by: [model] ([provider])
```

### Step 8: Post-Merge Cleanup

```bash
# Delete local branch
git branch -d {branch}

# Verify issue closed
gh issue view {issue} --json state
```

## Issue Linking Keywords

Use in PR body to auto-close issues:
- `Fixes #123` - closes issue when PR merges
- `Closes #123` - same as Fixes
- `Resolves #123` - same as Fixes
- `Relates to #123` - links but doesn't close

## Follow-up Issue Template

```markdown
## Summary
[What this follow-up tracks]

## Problem
[Why this wasn't done in the original PR]

## Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Depends On
- Issue #{prerequisite} must be merged first

## Follow-up from
- PR #{original-pr} review comment {comment-id}
```

## Guardrails

- **Always run tests** before creating PR
- **Use conventional commits** in PR title
- **Link all related issues** properly
- **Track follow-ups** as separate issues
- **Add co-authored-by** to PR and commits
- **Respond to all review comments**
