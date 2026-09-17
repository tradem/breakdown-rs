<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->

# Proposal: Series-scoped audit gate for `GET /v1/audit`

## Why

`GET /v1/audit` (`handlers::get_audit_history`) is classified `BlockMember`
by `requirement_for()`, but the only thing it authorizes on is the presence
of a `series_id` **query parameter** (`require_series`). The middleware's
`X-Active-Block` membership check is therefore unrelated to the series whose
journal is requested: any caller with an active membership in *any* block
could read the audit journal of *any* series.

The exposure is real, not theoretical: `projection_audit.series_id` is
populated from `EventMetadata` for all twelve aggregate categories, so
`list_by_series` returns the **whole tenant journal** — including entries of
blocks and seasons the caller has no membership in. The route only became
visible when issue #333 exported it into `backend/openapi.yaml`; `route_coverage`
then documented the status quo and this change is the follow-up that changes
it.

While implementing the gate we found a second, pre-existing defect (see
[What changes](#what-changes) → 3): every membership authorization predicate
compared a bare SQL literal against a JSON-encoded column, so none of them
could ever match.

## What changes

1. **A series-scoped membership predicate.**
   `MembershipRepository::has_active_membership_in_series(series_id, user_id)`
   resolves the tenant along the production hierarchy
   (membership → block → series, joining on the indexed
   `projection_block.series_id`). It is deliberately **role-agnostic**: the
   journal is an operational record of the whole production, not a
   costume-department artefact, so any *active* membership in the series
   grants access.

2. **Classification and handler gate agree.**
   `requirement_for()` returns `Requirement::Authenticated` for the exact
   path `/audit`, and `get_audit_history` performs the membership check
   itself behind an `// AUTHZ-GATE:` comment, returning
   `403 domain.forbidden` on denial. A repository error fails closed. The
   block-scoped twin `/blocks/{id}/audit` keeps `Requirement::BlockMember`.

3. **The membership projection stores plain tokens.**
   `projection_membership.role` / `.state` were written with
   `serde_json::to_string`, producing `"costume_assistant"` and `"active"`
   — while `has_active_costume_role_in_season`,
   `has_active_report_archive_role_in_season` and
   `has_active_credential_role` compared `m.state = 'active'` and
   `m.role IN ('costume_designer', …)`. No row could ever match, so those
   three predicates always returned `false` and every photo, report,
   AI-import and credential handler denied every caller. The projector now
   writes the bare token via `Role::as_str` /
   `MembershipStateKind::as_str`, and the read mapper parses it with
   `from_token`. The JSON wire form of `MembershipView` is unchanged.

## Non-goals

- No general per-`SeriesId` tenancy enforcement. This change gates one
  route; the deferred-tenancy requirement is amended only to record this
  documented exception.
- No data migration for existing `projection_membership` rows — the backend
  is not in production, so development databases are re-seeded. Rows written
  by the old projector are rejected loudly by `from_token` instead of being
  mis-read.
- No change to the `/v1` path version: the wire contract change is additive
  (one additional `400` response and updated descriptions).

## Depends on

- Issue #333 — exports `GET /v1/audit` into the contract (merged).
