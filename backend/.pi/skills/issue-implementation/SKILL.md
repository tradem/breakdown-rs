---
name: issue-implementation
description: Systematically implement a GitHub issue from analysis to completion. Use when starting work on an issue to ensure no drift and proper implementation.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub.
metadata:
  author: breakdown-rs
  version: "1.1"
---

# Issue Implementation Workflow

Systematically implement a GitHub issue: analyze, check for drift, plan, create branch, implement, test, and create PR.

## When to Use

- Starting work on a new issue
- Want to ensure no drift from existing implementations
- Need a systematic approach from issue to PR

## Prerequisites

- `gh` CLI installed and authenticated
- Issue number
- Clean working tree

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
- Are there similar implementations already?
- Could there be drift (issue describes already-implemented features)?

### Step 2: Check for Drift

```bash
# Search for related code
analyze_ast_search --query "[keywords from issue]" --mode summary

# Check existing implementations
analyze_ast_context --path "[affected files]"
```

**Ask user if drift detected:**

> "Issue #X mentions [feature], but I found [existing implementation]. Should I proceed with [approach A] or [approach B]?"

### Step 3: Create Feature Branch

```bash
git checkout -b feature/{issue}-{short-description}
```

**Branch naming:**

- `feature/{issue}-{kebab-case-description}`
- Example: `feature/174-durable-ai-payload-storage`

### Step 4: Create Implementation Plan

Use the **AskUser tool** if architectural decisions needed:

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

Write plan to `openspec/changes/{issue}-{description}/proposal.md`.

### Step 5: Implement

1. Create/modify files as planned
2. Add language-appropriate SPDX headers:

**Rust files:**

```rust
// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: [model] ([provider])
```

**Markdown files:**

```markdown
<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: [model] ([provider]) -->
```

**Shell scripts:**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: [model] ([provider])
```

3. Run tests frequently:

```bash
cargo check --workspace
cargo test -p [affected-crate]
cargo clippy -p [affected-crate]
```

### Step 6: Bump Versions (if needed)

For crate API changes:

- `infra`: MINOR bump for additive changes
- `api`: PATCH for consumption, MINOR for new public API

Update:

- `Cargo.toml` version
- `CHANGELOG.md`
- Dependency pins in consuming crates

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
# Stage only intended files
git add backend/crates/{crate}/src/{file}.rs
git diff --cached

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

### Step 9: Push and Create PR

```bash
git push -u origin {branch}

gh pr create --title "{type}: {description} (issue #{number})" --body "[PR description]"
```

### Step 10: Link Issues

```bash
# Close issue when PR merges
gh issue close {issue} --comment "Closed by PR #{pr}"

# Mark follow-up issues
gh issue comment {followup} --body "Follow-up to issue #{issue} (PR #{pr})."
```

## Guardrails

- **Fail immediately** if issue lookup fails
- **Always check for drift** before implementing
- **Ask user** for architectural decisions
- **Test frequently** during implementation
- **Use conventional commits**
- **Create follow-up issues** for deferred work
- **Use language-appropriate SPDX headers**
