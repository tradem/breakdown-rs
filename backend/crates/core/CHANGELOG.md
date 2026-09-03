<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->

# Changelog

All notable changes to the `core` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.10.0] - Unreleased

### Added — Series-scoped membership predicate (issue #342)

- `MembershipRepository::has_active_membership_in_series(series_id, user_id)`:
  the tenant counterpart of `is_active_member`. It answers “is `user_id` an
  *active* member of any block of `series_id`?” and backs the `GET /v1/audit`
  gate, whose data is selected by a `series_id` **query parameter** rather
  than by the caller's active block. Deliberately role-agnostic — the audit
  journal is an operational record of the whole production, not a
  costume-department artefact.
- **Breaking (MAJOR, ADR-020 D2):** new required method on the public
  `MembershipRepository` trait — every implementor must provide it. A trait
  signature change is MAJOR per ADR-020 D2, which in this workspace's 0.x
  scheme bumps the MINOR component: **0.9.0 → 0.10.0**.

### Added — Plain-text storage tokens for `Role` / `MembershipStateKind`

- `Role::as_str` / `Role::from_token` and `MembershipStateKind::as_str` /
  `MembershipStateKind::from_token` are the single source for the **storage**
  representation of `projection_membership.role` / `.state`
  (`costume_assistant`, `active`). They are deliberately distinct from the
  serde wire form (`"costume_assistant"`, `"active"`), which is unchanged:
  the membership authorization predicates compare those columns against plain
  SQL string literals, so JSON-quoted values matched nothing and the gates
  denied every caller. `crates/core/tests/membership_projection_tokens.rs`
  pins both representations to the same `snake_case` token.
- **MINOR (additive):** `Role::as_str` / `Role::from_token` and
  `MembershipStateKind::as_str` / `MembershipStateKind::from_token` are new
  `pub` items. Subsumed by the MAJOR bump above.

## [0.9.0] - 2026-08-23

### Changed — Bump MSRV to 1.98 (issue #257)

- **Breaking (MAJOR, ADR-020 D2):** `rust-version` raised from `1.94` to `1.98` (workspace floor + Dockerfile builder `rust:1.98-bookworm`). Consumers must build with Rust ≥ 1.98.

## [0.8.0] - 2026-08-13

### Changed — Structured `DomainError` variants + problem-code registry (issue #230)

`DomainError` is restructured from string-carrying variants to structured ones
that carry their registry entry (`code`) and typed S0/S1 data:
`NotFound { resource, id }`, `VersionConflict { expected, current }`, …;
`membership` errors drop the S2 `user_id` entirely. All 12 `From<*Error>`
impls are ported; interpolated `format!` messages are deleted from the wire
path (`Display` is log-only).

- **Breaking:** every consumer matching on `DomainError` variants must switch
  to the structured fields (`code` + typed ids). ~460 construction sites
  across the workspace were ported (ast-grep-assisted).
- The code registry (`error_registry`) grows from 19 to 73 codes — every
  aggregate error gets `{context}.{reason}` with status, constant English
  title and declared S0/S1 extension whitelists; per-context validation
  codes; S1 gating audit documented.
- `problem_code(&str)` resolves a registry entry by code (registry + lint
  lookup).

### Changed — Single-source problem-code registry (issue #232)

- The `error_registry` is rewritten as a single-source `problem_codes!`
  macro: every `pub const …: ProblemCode` and its `PROBLEM_CODES` array
  entry are now emitted from one invocation, so a code that is not
  registered cannot exist (previously a new constant omitted from
  `PROBLEM_CODES` compiled silently and `problem_code()` returned `None`).
  No public API change — all 73 codes, values, ordering and documentation
  are preserved (verified by the unchanged golden snapshots).

## [0.7.0] - Unreleased

### Added — Persisted source document format for AI imports (issue #221)

- `SourceFormat` (`csv` | `pdf` | `plain_text`): the declared format of an AI
  import source document, captured at the API edge from the upload's
  `Content-Type` and persisted on the job so the schedule worker can route
  CSV natively and PDF/plain-text through the LLM extraction path.
  `SourceFormat::uses_native_csv()` is the routing predicate; scripts are
  always `Pdf`.
- **Breaking:** `AiImportJob` and `AiImportEnqueueRequest` gain a required
  `source_format: SourceFormat` field. Every constructor must set it; the
  schedule worker derives the extraction path from the job instead of a
  caller-supplied `native_csv` flag.

### Added — Non-resumable AI import jobs (issue #181)

- `JobStatus::PayloadUnavailable` (`"payload_unavailable"`): a terminal status
  for a job whose durable payload — source document or preview blob — is gone.
  It is deliberately distinct from `DeadLetter`: a dead-lettered job exhausted
  its retries against a real failure, this one has no input left to retry
  *with*. Only *absence* leads here; storage that is merely unreachable stays
  on the retryable path.
  *Note for exhaustive `match`es on `JobStatus`* — the enum is not
  `#[non_exhaustive]`, so an exhaustive match must add the arm.
- `JobStatus::is_terminal()` / `JobStatus::is_non_resumable()`. `is_terminal`
  deliberately excludes `Failed`, which is the *retryable* backoff state:
  payload retention keys off this predicate, and misclassifying `Failed` would
  delete the source document of a job that is still scheduled to run.
- `AiImportQueue::mark_payload_unavailable(id, worker_id, error_summary)`,
  **defaulted** (delegates to `mark_failed(.., retryable = false)`) so
  in-memory and test queues need no change. Owner-fenced like the other worker
  transitions.

### Added — AI import permit reconciliation ports (issue #180)

- `AiImportQueue` gains three **defaulted** (non-breaking) methods:
  `claim_next_reconciling` / `claim_next_kind_reconciling` — claim a job and
  report the concurrency permit orphaned by the worker that previously held it;
  `attach_permit` — link the acquired permit to the claim; and `release_claim`
  — hand a claimed job back unrun, without charging a retry, when the
  concurrency ceiling is saturated. The defaults claim normally, report no
  orphan, and no-op, so in-memory and test queues (which have no permit link
  and no lease) need no change.

### Changed — Retry-safe schedule-side apply (issue #179)

- **Breaking:** `AiImportMappingRepository` gains a required `reserve(mapping)
  -> AiImportMapping` method. It is insert-if-absent and MUST return the
  **winning** row (the existing one on conflict), so a retried AI apply
  converges on one aggregate id instead of minting a fresh one. Every
  implementor must add it. `insert` is now documented as strictly monotonic in
  `aggregate_version` — it must never roll a confirmed row back.
- `ScheduleSceneOnShootingDay` is now **state-idempotent**: `SceneAggregate`
  implements `kameo_es`'s `is_state_idempotent` for it, so re-scheduling a day
  the scene already links yields `ExecuteResult::Idempotent` (the unchanged
  current version) instead of a `Conflict`. Previously a retried schedule-apply
  hit `SceneError::AlreadyScheduled` and could never confirm its idempotency
  mapping. Optimistic concurrency is unchanged — the expected-version check
  still runs first, so a stale command fails with a version conflict.
  `handle` keeps returning `AlreadyScheduled` as a defensive guard for direct
  calls, so "emit no duplicate event" holds at both layers.
  *API-visible:* `POST /scenes/{id}/shooting-days` for an already-scheduled day
  now returns `200 OK` with the unchanged version instead of `409 Conflict`.

### Added — mapping reservation state (issue #179)

- `AiImportMapping::reservation(..)`, `AiImportMapping::is_reserved()` and
  `AiImportMapping::RESERVED_VERSION` describe the two-phase
  reserve-then-confirm mapping state. A reservation carries
  `aggregate_version = 0` — the established "no version yet" sentinel — so no
  schema change was needed.

### Changed

- **Breaking:** the worker-originated `AiImportQueue` lifecycle methods take
  the claiming `worker_id` (issue #177):
  `mark_running(id, worker_id)`, `mark_succeeded(id, worker_id, preview_handle)`,
  `mark_failed(id, worker_id, error_summary, retryable)` and the new
  `record_worker_telemetry(id, worker_id, telemetry)`.
  Worker leases let a second worker reclaim a job whose lease expired, so two
  workers can briefly run the same job. Implementors MUST fence every
  transition on the claim owner and reject a write from a displaced worker
  with `DomainError::Conflict` — otherwise a stale worker silently overwrites
  the new owner's result. Every implementor must add the parameter.
- **Breaking:** telemetry is split in two. `record_worker_telemetry` is the
  owner-fenced write used by queue workers; `record_telemetry` stays unfenced
  for the API apply path, where the job is already terminal and no claim
  exists. Without the split a displaced worker's metrics would commit even
  though its `mark_succeeded` is rejected, describing work that was discarded.

### Added

- `AiImportQueue::lease_window()` (defaulted to `None`) exposes the adapter's
  claim lease so workers can derive a heartbeat interval. Implementations
  without a lease (in-memory, tests) inherit the default and need no change.

## [0.6.0] - Unreleased

### Added — fallible authorization policy checks (issue #175)

- New defaulted `AuthorizationPolicy` methods `authorize_season_result` and
  `authorize_credential_role` in `membership::policy`: both are *fallible*
  (`Result<PolicyDecision, DomainError>`) so API handlers on
  `Authenticated`-only privileged routes can route their authorization gates
  through the policy while keeping read-model failures visible as mapped
  server errors instead of silently becoming a `403`. Defaults return
  `Ok(PolicyDecision::Deny)`, so existing policy implementations are
  unaffected.

## [0.5.0] - Unreleased

### Added — CQRS-safe merge input type (issue #172)

- New `MergeInput` struct in `ai::preview`: an immutable blob carrying the
  `ShootingSchedule` and pre-loaded `SceneView` slices, prepared at the
  authorized API/query boundary and stored before the merge job is claimed.
  The write-side merge worker reads only this blob — never a read-model
  projection (CQRS boundary, AGENTS.md §1).
- New `merge_from_input(input: &MergeInput) -> Result<MergedPreview, DomainError>`
  pure function: CQRS-safe entry point that performs the deterministic
  schedule-to-scene join against the pre-loaded scenes.

## [0.4.0] - 2026-08-07

### Changed — AI import telemetry apply-state contract (issue #171)

- `Telemetry` no longer carries `accept_as_is: Option<bool>` and
  `edit_distance: u32` as independent fields. They are replaced by a single
  `apply_state: TelemetryApplyState` discriminator:
  - `TelemetryApplyState::NotApplied` — the job never reached apply; its
    `edit_distance` is explicitly NULL, not a misleading `0`.
  - `TelemetryApplyState::Applied { accept_as_is: bool, edit_distance: u32 }`
    — an applied outcome; zero user edits stays `edit_distance = 0` and is
    distinguishable from a never-applied job.
- New public enum `TelemetryApplyState` (serde `snake_case`, `ToSchema`,
  `Default` = `NotApplied`) with accessor helpers `accept_as_is()` and
  `edit_distance()` returning `Option<T>` for persistence.
- **Breaking change under major-zero semver** (released as MINOR, ADR-020 D2):
  `Telemetry`'s removed pub fields change any construction site; acceptance
  and edit-rate calculations SHALL exclude `NotApplied` jobs. This is the
  first `core` release (per-crate tag `core-v0.4.0`).
