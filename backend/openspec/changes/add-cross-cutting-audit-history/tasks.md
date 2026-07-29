## 1. Shared metadata type in core

- [x] 1.1 Define `core::shared::EventMetadata { actor: Option<UserId>, provenance: Provenance, series_id: Option<SeriesId> }` and `pub enum Provenance { Human, Saga(&'static str), System }` with `Serialize`/`Deserialize`/`Clone`/`Debug`/`PartialEq`.
- [x] 1.2 Switch all 11 aggregates' `Entity::Metadata` to `EventMetadata`: `season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `photo`, `membership`. Remove the old `MembershipMetadata` (or alias it to `EventMetadata` during transition) — final state is a single shared type.
- [x] 1.3 Update `MembershipAggregate::handle(LeaveBlock, …)` to read `actor` from `EventMetadata` instead of `MembershipMetadata` (semantics unchanged).
- [x] 1.4 Verify `crates/core` builds with no `MembershipMetadata` references outside `EventMetadata` aliases.

## 2. Command adapters inject actor, provenance, and series_id

- [ ] 2.1 Update `MembershipCommandsImpl` to inject `EventMetadata { actor: Some(actor), provenance: Human, series_id: <resolved> }` on every command instead of `MembershipMetadata { actor: Some(actor) }`.
- [ ] 2.2 For each non-membership command adapter, thread the authenticated `UserId` into the method signature (where not already present) and inject `EventMetadata { actor: Some(actor), provenance: Human, series_id }` at dispatch. For aggregates whose command payload already carries `series_id` (`CreateBlock`, `CreateEpisode`), use it directly; otherwise resolve via a single repository read.
- [ ] 2.3 Update all saga command-dispatch paths to inject `provenance: Provenance::Saga(<stable name>)` with the appropriate saga identifier (e.g. `"SeasonSeedingSaga"`, `"PhotoDeletionSaga"`, `"PhotoThumbnailSaga"`, `"ContinuityDeletionSaga"`, `"PhotoBytesCleanupSaga"`).
- [ ] 2.4 Ensure system-initiated dispatches (if any remain) inject `provenance: System`.

## 3. Generalize the AuditProjector

- [ ] 3.1 Refactor `crates/infra/src/projectors/audit.rs` from `EntityEventHandler<BlockMembership, …>` to an `EntityEventHandler` impl per aggregate category (or an exhaustive dispatcher sharing the insert logic). Reuse the existing `event_key` + `ON CONFLICT DO NOTHING` idempotency pattern.
- [ ] 3.2 For each category, read `actor`, `provenance`, and `series_id` from `EventMetadata` and write them into `projection_audit` (canonicalize `provenance` to a stable string column representation — verify the column type supports it; add a migration only if needed; the table already has `series_id` and `actor`).
- [ ] 3.3 Verify the `entity_type` value written for each category matches the `Entity::category()` string exactly (e.g. `scene_shoot`, `costume_category`, `shooting_day`).
- [ ] 3.4 Ensure no audit projector performs entity→series chain resolution at projection time — `series_id` comes from `EventMetadata` only.

## 4. Compile-time-exhaustive coverage guard (Decision 4 / 5a)

- [ ] 4.1 Define `infra::projectors::audit::AuditCategory` (a `#[non_exhaustive]` enum) with one variant per aggregate category.
- [ ] 4.2 Refactor the supervisor audit-projector registration to `match` on `AuditCategory` exhaustively; each arm registers the category's `EntityEventHandler` audit projector.
- [ ] 4.3 Add a documentation-style unit test (`#[test] fn audit_category_coverage_is_exhaustive`) that documents *why* the enum exists and asserts all expected variants are present, so future readers understand its purpose.
- [ ] 4.4 Verify that adding a 12th aggregate without a variant fails compilation (can be validated via a temporary scratch variant / compile-fail check, or asserted in the unit test by deriving from a const list of expected categories).

## 5. AuditRepository query surface

- [ ] 5.1 Add `list_by_series(series_id: SeriesId, limit, offset) -> Vec<AuditEntry>` to the `AuditRepository` port in `crates/core/src/audit/ports.rs`.
- [ ] 5.2 Implement `list_by_series` in `AuditRepositoryImpl` against `projection_audit WHERE series_id = $1 ORDER BY occurred_at DESC, id DESC LIMIT $2 OFFSET $3` (static SQL literal + `.bind()`; no interpolated identifiers).
- [ ] 5.3 (Optional, only if needed) Add `list_by_provenance` filter if the admin UI surfaces saga-vs-human distinction. Defer if out of immediate scope.

## 6. Tests

- [ ] 6.1 Extend `crates/integration-tests/tests/audit_projector_tests.rs` (or add a new tier-4 file) to assert that non-membership events (e.g. `CreateCharacter`, `CreateScene`, `CreateCostumeCategory`) produce correctly-attributed `projection_audit` rows with `actor`, `provenance = Human`, and `series_id`.
- [ ] 6.2 Add a test asserting a saga-dispatched command (`SeasonSeedingSaga` → `CreateCostumeCategory`) produces an audit row with `provenance = Saga("SeasonSeedingSaga")` and `actor = NULL`.
- [ ] 6.3 Add a test for `list_by_series` returning only the requested tenant's rows and excluding others.
- [ ] 6.4 Verify idempotency under redelivery: delivering the same event twice produces exactly one `projection_audit` row for every category, not just membership.
- [ ] 6.5 Add/run the `AuditCategory`-exhaustiveness compile-time guard test (section 4.3).

## 7. API surface and OpenAPI

- [ ] 7.1 If an admin audit-history endpoint is needed: add an `#[utoipa::path]` GET handler (e.g. `GET /audit?actor=&series_id=&entity_type=&from=&to=&limit=&offset=`) served via `AuditRepository`; gate handler-internal authorization per the photo-handler `// AUTHZ-GATE:` pattern if gated by `Authenticated`-only. If this change does not introduce the endpoint, defer to a follow-up.
- [ ] 7.2 Update `AGENTS.md`/OpenAPI only if a new public surface is introduced; otherwise no doc changes required.

## 8. Architecture and guardrails

- [ ] 8.1 Run `cargo test -p architecture_tests` to confirm no core→infra boundary violation was introduced by the metadata refactor.
- [ ] 8.2 Run `cargo deny check bans` to confirm no new banned dependency was introduced.
- [ ] 8.3 Confirm no string-interpolated SQL was introduced (static literals only) via the `no-string-interpolation-sql` CI job.
- [ ] 8.4 Run `cargo mutants --in-diff` for changed core/infra code; close any surviving mutants in the audit metadata extraction path.
