<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->

# Tasks: Series-scoped audit gate for `GET /v1/audit`

## 1. Core — the series membership predicate

- [x] Add `MembershipRepository::has_active_membership_in_series(series_id, user_id)` to `crates/core/src/membership/ports.rs` (role-agnostic, documented as the tenant counterpart of `is_active_member`).
- [x] Add `Role::as_str` / `Role::from_token` (`crates/core/src/membership/mod.rs`).
- [x] Add `MembershipStateKind::as_str` / `MembershipStateKind::from_token` (`crates/core/src/membership/views.rs`).
- [x] Add `crates/core/tests/membership_projection_tokens.rs` pinning the storage token to the serde wire form.

## 2. Infra — SQL and projection encoding

- [x] Implement `has_active_membership_in_series` in `crates/infra/src/queries/membership.rs` (join `projection_membership` → `projection_block`, static SQL, bound values only).
- [x] Write plain tokens instead of JSON in `crates/infra/src/projectors/membership.rs`.
- [x] Parse plain tokens in `map_membership_row`, rejecting unknown values loudly.

## 3. API — classification and handler gate

- [x] Return `Requirement::Authenticated` for the exact path `/audit` in `requirement_for()`.
- [x] Add the `// AUTHZ-GATE:` check to `get_audit_history` (403, fail closed) and document the 400/403 responses in `#[utoipa::path]`.
- [x] Extend the `MembershipRepository` test doubles (`handlers/test_helpers.rs`, `tests/common/mod.rs`, both `MockSeasonMembershipRepo`s) with the new method / a `series_membership_override`.

## 4. Tests

- [x] `crates/api/tests/route_coverage.rs` — reclassify `/audit` as `Authenticated`, update the rules-of-thumb comment.
- [x] `crates/api/tests/auth_authorization.rs` + `crates/api/src/auth/authorization/authorization_test.rs` — add `/audit` and `/v1/audit` to the allowlist; new `series_audit_route_is_authenticated_only_block_audit_stays_block_member` test.
- [x] `crates/api/tests/handler_authz_batch2.rs` — deny without series membership, deny on repository error, allow for a member (with a foreign-series entry that must not leak).
- [x] `crates/integration-tests/tests/membership_round_trip.rs` — Tier-4 coverage of `has_active_membership_in_series` (member / outsider / foreign series / pending invitee / accepted / removed) plus a regression assertion for `has_active_costume_role_in_season`.

## 5. Contract, docs, changelogs

- [x] Regenerate `backend/openapi.yaml` (`UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`).
- [x] `backend/docs/security/security-architecture.md` — allowlist table entry for `/audit`, handler-gate pattern, membership projection encoding section.
- [x] OpenSpec change `342-audit-series-membership-gate` (proposal, tasks, `api-authorization` delta).
- [x] CHANGELOG entries for `core`, `infra`, `api`.

## 6. Verification

- [x] `cargo test --workspace --exclude integration-tests` — 74 test binaries green.
- [x] `cargo test -p integration-tests --test membership_round_trip` — 4 passed (Docker required).
- [x] `cargo clippy --workspace --all-targets --all-features` — clean.
