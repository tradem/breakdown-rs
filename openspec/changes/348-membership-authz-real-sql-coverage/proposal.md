<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: Muse Spark (neuralwatt) -->

# Proposal: Real-SQL coverage for the repaired membership authz predicates (issue #348)

## Why

PR #347 (issue #342) fixed a defect that made three membership authorization
predicates return `false` for every caller: the projector JSON-encoded
`role`/`state` while the SQL compared bare literals. The projection now
stores bare tokens, but the coverage gap that let the defect ship remains:

- The API-level authz tests (`crates/api/tests/handler_authz_batch2.rs`)
  drive the gates through `FakeMembershipRepo`, whose predicates hardcode
  `Ok(true)`. A broken SQL predicate is invisible to them by construction.
- The only real-SQL coverage is one positive assertion in
  `crates/integration-tests/tests/membership_round_trip.rs`
  (`has_active_costume_role_in_season` matches a projected active member).
- Nothing asserts denial for the right reason, and the role allowlists are
  unpinned: `costume_assistant` must stay excluded from manual report
  archival, and `wardrobe_supervisor` must stay excluded from the settings
  credential gate (ADR-027).

## What changes

1. **Tier-4 predicate truth tables in `membership_round_trip.rs`** (full
   `command → SierraDB → projector → PG` chain, read back through the real
   `MembershipRepositoryImpl`):
   - `has_active_report_archive_role_in_season`: `costume_designer` /
     `wardrobe_supervisor` allowed, `costume_assistant` denied, pending /
     removed members denied, member of a block in a *different* season
     denied.
   - `has_active_credential_role` (ADR-027): `costume_designer` /
     `costume_assistant` allowed, `wardrobe_supervisor` denied, inactive /
     unknown callers denied.
   - One round-trip per gate family (photo + JSON/PDF report share the
     costume-role predicate; manual archive; settings credential; audit is
     already covered): a caller who is an active member of a block in a
     different season/series is denied, a genuinely authorized member is
     allowed.

2. **`FakeMembershipRepo` resolves predicates from seeded data** (both
   `crates/api/tests/common/mod.rs` and the `pub(crate)` twin in
   `crates/api/src/handlers/test_helpers.rs`):
   - New seeded state: per-member `(Role, MembershipStateKind)` plus a
     `block → (season, series)` scope map, with a small seeding helper.
     The existing `members` set keeps its meaning (active
     `CostumeAssistant`).
   - Predicates evaluate the allowlists against the seeded rows and fail
     closed (deny) for unknown blocks/users instead of returning `Ok(true)`.
   - The explicit override knobs stay and keep precedence, so error-injection
     (`Err`) and explicit allow/deny tests keep working.
   - Affected api handler tests that relied on default-allow are updated to
     seed membership (or set an explicit override).

## Non-goals

- No production code changes (`core`, `infra`, `api` handlers untouched) —
  test-only change, so no crate version bumps (recorded as `none`).
- No `api` dev-dependency in `crates/integration-tests`: the crate keeps its
  `core`/`infra`-only boundary (AGENTS.md §4). The repo predicates *are* the
  gates' decision procedures; the handler `bool → 403` mapping stays covered
  by the api fake tests. No true handler-level round-trip through real SQL.
- No data migration: out of scope, unchanged from #342.

## Depends on

- Issue #342 (projection encoding fix; PR #347, merged).
