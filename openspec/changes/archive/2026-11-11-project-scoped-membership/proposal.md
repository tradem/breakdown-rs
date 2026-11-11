<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Proposal: project-scoped membership — a costume role without a block

## Why

The block-less AI-import upload (`829-script-derived-import-target`, D1) is
authorized against the declared season through
`AuthorizationPolicy::authorize_season_result` →
`MembershipRepository::has_active_costume_role_in_season`, which joins
`projection_block`:

```sql
JOIN projection_block b ON b.id = m.block_id
WHERE b.season_id = $2 AND m.role IN ('costume_designer','wardrobe_supervisor','costume_assistant')
```

A role therefore exists **only at a block**. A season with no block has no
roles at all, so the intended workflow — pick the season, upload the
screenplay, let `827`/`829` derive the block from the script — can never
authorize: the caller is refused with `403 ai-import.forbidden` even when they
are a costume designer of the production project.

Observed live on 2026-11-11: project `01a0c8bf-…` had **0 blocks**, one season,
and five orphaned membership rows (their blocks no longer exist). The client
surfaced the refusal as a network error (separate client fix landed on the same
branch), which is what made the gap visible.

`ADR-035` already moved the authorization **level** up to the project, and
`#535` did exactly this for pieces/photos ("a costume-department role in any
active block of the owning project"). The membership model never followed: it
still cannot express a role that is not attached to a block.

## What changes

- A **project-scoped costume role grant** becomes a first-class concept next to
  the block-scoped one (new stream, aggregate, events, projection, query).
- Season creation bootstraps the creator's project-scoped costume role — the
  missing piece for "a season exists, the caller is a costume designer".
- Season-scoped authorization checks resolve the **effective** role: block
  membership in the season, else a project-scoped grant on the season's
  project. Fail-closed on every error, unchanged for callers who hold a block
  role.
- Block-scoped membership keeps its semantics **unchanged** (roles still rotate
  at block boundaries).

## Impact

- `core`: new `project_membership` module (aggregate, commands, events, roles
  reuse), a role-resolution value object.
- `infra`: stream + projector + `projection_project_membership`, the new
  repository query, and `has_active_costume_role_in_season` resolving through
  it.
- `api`: `authorize_season_result` gains the project fallback; the block-less
  AI-import upload (`829` D1) starts to allow the documented workflow. No route
  or payload change, no OpenAPI delta.
- Flutter: **no change** — the client already sends `X-Declared-Season` and
  shows the server's code; it stops failing.
- Data: no migration of existing rows; the projection is new. Orphaned
  membership rows (blocks that no longer exist) become inert, not an error.
- Not touched: `ADR-035 B2` (no new `*_in_season` predicate is added — an
  existing predicate changes its resolution), block-scoped policies, and the
  season/block/project numbering invariants.

## Open question (decision needed before implementation)

Who may grant a project-scoped costume role, and is the season creator always
the project owner? Today the block creator is bootstrapped as its owner; the
project has no aggregate of its own yet (opaque `ProjectId` seam), so
"project owner" is derived. The design assumes: the **season creator** is
bootstrapped with `costume_designer` at project scope, and only a holder of a
project-scoped costume role may grant further project-scoped roles.
