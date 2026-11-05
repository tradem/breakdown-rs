---
name: issue-implementation
description: Systematically implement a GitHub issue from analysis to completion. Use when starting work on an issue to ensure no drift and proper implementation.
license: AGPL-3.0
compatibility: Requires `gh` CLI authenticated with GitHub.
metadata:
  author: breakdown-rs
  version: "1.3"
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

Freshness first — the knowledge-graph index is machine-local and rots between
refreshes, so a stale index answers "no such symbol" for code that exists:

```bash
root=$(git rev-parse --show-toplevel)             # the scripts are monorepo-root assets
bash "$root/scripts/check-graph-freshness.sh"        # report: fresh / stale
bash "$root/scripts/reindex-graph.sh" --if-stale     # only when the index lags
```

Then use the matching tool for the shape of the question — the graph
(`codebase-memory`, project `breakdown-rs`) for meaning, `rg` only for text
(ARB keys, problem codes, config values, Markdown):

```bash
# Meaning questions (definition, callers, blast radius) → graph
search_graph --name_pattern ".*[Keyword].*" --file_pattern "backend/**"
trace_path --function_name "[KnownHandlerOrService]" --direction inbound
# Second opinion on the same question (ast-bro resolves Rust too)
analyze_ast_search --query "[keywords from issue]" --mode summary
analyze_ast_context --path "[affected files]"
```

**Produce the Discovery-evidence block (mandatory artefact).** A graph-first
claim is only reviewable if it is written down — prose rules lose to `grep`
under time pressure, so the workflow demands the evidence instead of the
intention. Fill this in during Step 2 and carry it verbatim into the proposal
(Step 4) and the PR body (Step 9):

````markdown
### Discovery evidence (issue #NNN)
- Index: project `breakdown-rs`; `scripts/check-graph-freshness.sh` → fresh (or stale → reindexed)
- Graph (meaning): `search_graph ".*X.*"` → `path:Symbol (Label)`; `trace_path X inbound` → N edges (a, b)
- Text (occurrence): `rg -n "<key>"` for <problem code / config value / prose> — text by nature, not a symbol
- Coverage: `check_index_coverage(paths=[…])` → clean, or gaps: `path:ranges` verified by <read/rg of those ranges>
- Not the graph (and why): <macro-generated dispatch → `rg` plus a source read; trait-object dispatch → `analyze_ast_impact`>
````

Rules that make the block a gate rather than another paragraph:

- A **symbol question** (where is X defined, who calls X, what does a change
  touch) answered only with `rg` is sent back: `rg` cannot report kinds, edge
  types or completeness.
- A **negative claim** ("nothing else consumes X", "no other call site") needs
  the `Coverage` line; without it the claim is provisional, not done.
- A missing block is a review blocker, exactly like a missing `AUTHZ-GATE`
  comment — the reviewer checks for the block, not for good intentions.

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
- `Cargo.lock` (regenerated by the build; stage it with the change)

Record every bump in a **version-bump table** — this is mandatory, even when
no crate was bumped (the table then states `none` explicitly):

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `api` | 0.4.6 | 0.4.7 | MINOR | New public `TlsConfig` fields (additive API) |
| `core` | 0.5.0 | 0.5.0 | none | No domain change |
| `infra` | 0.10.0 | 0.10.0 | none | No infra API change; no re-pin needed |

Keep the table in the implementation notes and reuse it verbatim in the PR
body (Step 9) and the final report (Step 11).

### Step 7: Weigh Up Deferred Work (issue creation is NOT automatic)

Before deferring anything, walk the gate below. **Creating a follow-up issue
is a decision, not a workflow step** — it requires a *yes* on every question
below **and** the user's explicit go-ahead (ask with `ask_user`). A "no" is the
default outcome and needs no justification.

1. **Is it real work, or an observation?** A finding that is already fully
   captured in code, docs, a commit body or the PR body needs **no** issue —
   that is where it belongs. Upstream/environment noise (a dependency release,
   a flaky upstream, a CI config quirk someone else owns) is documented in the
   PR body, not ticketed. Issue only work someone must *do*.
2. **Is it inside the issue's own scope?** If it is, it is not a follow-up at
   all — do it now (see the size gate below). Scope creep must not be laundered
   into a follow-up issue to keep the current PR tidy.
3. **Size gate (the reason deferral exists):** would doing it now push the
   current PR past a reviewable size — a second behavioural change, a second
   subsystem, or a second contract/registry change in one diff? If yes,
   deferral is legitimate. If the work is small (a doc line, one assertion, one
   `git mv`), do it in the PR; a "too big" PR is a reason to *ask the user
   about splitting the work*, not to silently open a ticket.
4. **Would the issue be actionable by someone else?** Needs a repro, a "why",
   and acceptance criteria. A finding only you can act on is a note in the PR.
5. **Does a ticket exist already?** Search first — never duplicate an issue
   that already covers the ground.

**If the gate says yes:** ask the user, then file:

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

**If the gate says no:** do not create anything. Record the decision in one
line of the PR body ("Follow-up considered: X — not ticketed, because Y") so a
reviewer sees the deliberation instead of a silently dropped finding.

### Step 8: Commit

```bash
# Stage all files selected by the implementation plan
# Include: source files, tests, Cargo.toml, CHANGELOG.md, skill files, etc.
git add backend/crates/{crate}/src/{file}.rs
git add backend/crates/{crate}/tests/{file}.rs
git add backend/crates/{crate}/Cargo.toml
git add backend/crates/{crate}/CHANGELOG.md
git add backend/.pi/skills/{skill}/SKILL.md

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

### Step 9: Push and Create PR

```bash
git push -u origin {branch}

gh pr create --title "{type}: {description} (issue #{number})" --body "[PR description]"
```

The PR body MUST include:

1. A **Summary** and **Changes** section (what / why).
2. The **Discovery evidence** block from Step 2, verbatim.
3. The **version-bump table** from Step 6, verbatim.
4. A **Validation** section (test/clippy/lint results).
5. Acceptance criteria checkboxes from the issue.

Example PR body sections:

```markdown
## Version Bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `api` | 0.4.6 | 0.4.7 | MINOR | New public `TlsConfig` fields (additive API) |
| `core` | 0.5.0 | 0.5.0 | none | No domain change |
```

### Step 10: Link Issues

```bash
# Close issue when PR merges
gh issue close {issue} --comment "Closed by PR #{pr}"

# Mark follow-up issues — ONLY those the user approved in Step 7
gh issue comment {followup} --body "Follow-up to issue #{issue} (PR #{pr})."
```

### Step 11: Final Report

Close the implementation with a structured report in your final response.
Always include the version-bump table (Step 6), even when no version changed:

```markdown
## Implementierungs-Report (Issue #{issue})

**Branch:** `{branch}` → **PR:** [#{pr}]({url})

| Schritt | Ergebnis |
|---|---|
| Drift-Check | ... |
| Tests | `cargo test -p {crate}`: N passed |
| Lints | `cargo clippy ...`: clean |
| Guardrails | ast-grep: no findings |

### Version Bumps

| Crate | Previous | New | Bump type | Reason |
|---|---|---|---|---|
| `api` | 0.4.6 | 0.4.7 | MINOR | New public `TlsConfig` fields (additive API) |
```

If any crate version changed, state the bump type and justification per crate;
if none changed, write `none` explicitly so the reviewer can see the decision
was made deliberately, not skipped.

## Guardrails

- **Fail immediately** if issue lookup fails
- **Always check for drift** before implementing
- **Ask user** for architectural decisions
- **Test frequently** during implementation
- **Use conventional commits**
- **Never create a follow-up issue by reflex** — Step 7 is a weighed
  decision gated on *and* the user's go-ahead. The default outcome is "no
  issue": the finding lives in the code, docs, commit body or PR body, and
  the PR body gets a one-line note of the deliberation
- **Prefer doing the work in the PR** when it is small (doc line, one
  assertion, one rename) or when it belongs to the issue's own scope; use a
  follow-up issue only when the work is genuinely separate *and* would grow
  the current PR past a reviewable size — and ask the user before filing

- **Use language-appropriate SPDX headers**
- **Never skip the version-bump table** in Step 6, the PR body (Step 9), and
  the final report (Step 11) — an explicit `none` beats an omission
