<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->
<!-- Co-authored-by: muse-spark-1.3-contributor (opencode-go) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Changelog

All notable changes to the `api` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.12.0] - Unreleased

### Added — Scene provenance in the wire contract (issue #517, EU AI Act Art. 50)

- `SceneView` responses (GET scene / scenes-by-episode / scenes-by-day /
  scenes-by-character) gain an additive optional `source` field (`Manual` |
  `AiExtracted { document_id, external_ref, confidence }`) so clients can
  render persistent AI badges — point-of-interaction transparency data, EU AI
  Act Art. 50. `Some(AiExtracted)` marks AI-imported scenes; `Some(Manual)`
  the user-created path; `None`/absent only legacy clients that predate the
  field (serde-`default`-backed, ADR-021 D3/D5 MINOR). `/v1` path version
  stays; `openapi.yaml` regenerated, wire fixture additively allowlisted.
- REST scene creation is unaffected: the handler records `Manual`; AI
  provenance is set server-side only by the import worker.
- **MINOR bump (ADR-020 D2):** additive optional response schema field plus
  re-pinned `breakdown_core` 0.13.0 / `infra` 0.18.0: **0.11.0 → 0.12.0**.

## [0.11.0] - Unreleased

### Fixed — photo upload returns a spurious 404 when the photo projector lags (issue #514)

- `POST /costumes/{id}/photos` previously built its 201 `PhotoView` response
  by synchronously reading the freshly-uploaded photo back from the
  projection (`photo_repo().find_by_id`). With any projector lag the just
  written photo was not yet indexed → `None` → a **404 `photo.not-found`**
  even though `PhotoUploaded` + `PhotoLinked` had been persisted (the write
  side raced the read side; the Flutter client then surfaced #513's generic
  "could not be saved" fallback).
- The handler now builds the 201 `PhotoView` entirely from the
  dispatch/command output: the generated `photo_id`, the request
  `content-type`/`size_bytes`, the `AggregateVersion` echo from
  `PhotoCommands::upload`, and the three `Pending` variants / `exif_stripped_at:
  None` / `binding` per the `PhotoUploaded` event contract (the thumbnail saga
  has not run yet). No photo-projection read-back remains on the upload path, so a
  lagging photo projector can never turn a successful write into a 404.
- Regression: `upload_costume_photo_returns_201_despite_projection_lag` in
  `handler_authz_batch2.rs` — an authorized upload returns **201** (with the
  response asserting it derives solely from the recorded `UploadPhoto`
  command) while `FakePhotoRepo::find_by_id` still returns not-found,
  simulating a frozen photo projector. This test fails on the pre-fix handler
  (404) and passes after.
- No wire-contract/API-surface change (`PhotoView` response schema
  unchanged; `openapi.yaml` untouched). Rides with the open 0.11.0 MINOR; no
  additional bump.

### Added — `AiConfigView` exposes the stored prompt texts (issue #490)

- The `AiConfigView` response schema now includes `prompts`
  (`{string: string}`, keys `script`/`schedule`) alongside `prompt_kinds`,
  so the configured/edit form renders the stored prompt texts and an
  untouched save preserves them. Additive wire field — `/v1` path version
  stays (ADR-021 D3); `openapi.yaml` regenerated.
- **MINOR bump (ADR-020 D2):** new required response field on
  `AiConfigView` plus re-pinned `breakdown_core` 0.12.0 / `infra` 0.17.0:
  **0.10.0 → 0.11.0**.

## [0.10.0] - Unreleased

### Added — AI-config dialog defaults + suggestion contract (issue #471)

- New `GET /v1/ai-import/defaults` reads the deployment's single-source
  prompt defaults (`infra::ai::default_prompts()`, honoring
  `AI_IMPORT_DEFAULT_PROMPTS_PATH`) and serves `{ script, schedule }`
  (`AiImportDefaults`). Gated exactly like the provider/model catalog reads:
  credential-role policy (403 `ai-config.forbidden`) + `AI_IMPORT_ENABLED`
  (404 `ai-import.disabled`) — no new registry codes.
- `GET /v1/ai-import/providers/{key}/models` now flags the curated
  recommendation on each `ModelInfo.recommended` (additive, `#[serde(default)]`
  response field, so pre-flag backends deserialize it as `false`), giving the
  dialog a deterministic suggested model to preselect.
- The defaults endpoint treats a broken/absent `AI_IMPORT_DEFAULT_PROMPTS_PATH`
  (or invalid built-in TOML) as a deployment fault: the prompt-file read/parse
  error is mapped to 500 `http.internal-error` (`map_prompt_defaults_error`,
  reason is log-only), never a client 422; the route's OpenAPI responses
  declare 500 and 503 (the gate's transient membership-repo failure).
  Wire-level authz tests for the defaults gate (allow/deny/repo-failure,
  success shape) in `handler_ai_import_authz.rs`; `openapi.yaml` regenerated
  (new route + `ModelInfo.recommended`).
- **No additional bump:** additive route + additive response field — rides
  with the open 0.10.0 MINOR (same convention as #470/#481).

### Added — scoped AI-import/AI-config error codes for the client's non-forbidden switches (issue #481)

- The AI import upload handlers (`upload_ai_script`, `upload_ai_schedule`,
  and the shared `enqueue_ai_upload` content-type fallback) now reject an
  unsupported document `Content-Type` with the new scoped code
  `ai-import.unsupported-media-type` (415, `ApiError::AiImportUnsupportedMediaType`)
  instead of the generic `http.unsupported-media-type`.
- A missing/oracle-hidden AI import job (`get_ai_import_job`,
  `get_ai_import_preview`, `apply_ai_import`) surfaces the new scoped code
  `ai-import.not-found` (404, `ApiError::AiImportNotFound`) instead of
  `domain.not-found`.
- A stale optimistic-lock `version` on `PATCH /ai-import/config/{id}` /
  `POST /ai-import/config/{id}/revoke` emits the new scoped code
  `ai-config.version-mismatch` (409, `ApiError::AiConfigVersionMismatch`)
  with the typed `expected_version`/`current_version` extensions preserved
  — translated from `DomainError::VersionConflict` at the API edge — instead
  of the generic `concurrency.version-mismatch`.
- The 413 oversize-document surface is intentionally still the generic
  `http.payload-too-large`: the shared pre-handler `Bytes`/body-limit
  extractor rejects an oversized request before the handler runs, so a
  scoped code there would be unreachable in production (client aligns,
  not scoped).
- Wire-level tests: `upload_ai_script`/`upload_ai_schedule` wrong
  content-type → `ai-import.unsupported-media-type`; missing job →
  `ai-import.not-found`; config edit version conflict →
  `ai-config.version-mismatch` (+ extensions) in
  `handler_ai_import_ports.rs`.
- **No additional bump:** additive `ApiError` variants + registry codes —
  rides with the open 0.10.0 MINOR (same convention as #470).

### Added — create-with-repertoire-season costume flow (issue #453)

- `POST /v1/costumes` body extends from empty `{}` to
  `{ season_id: Option<SeasonId> }`: when present, the costume joins that
  season's costume stream while unassigned — the API edge resolves the
  `series_id` audit metadata from the season projection (404 on an unknown
  season, mirroring `create_character`). Combined with the widened
  `list_by_season` union (#453, infra) this restores the UI path to a
  costume's first assignment that the Flutter widget contract
  (`assign-costume-<id>-none` rows) already assumes.
- **No additional bump:** request-body extension (optional field, old
  clients sending `{}` keep working) — rides with the open 0.10.0 MINOR.

### Added — deterministic fault injection for E2E tests (issue #443)

- New cfg-gated module `fault_injection`: a process-global one-shot latch
  armed via `POST /v1/__faults/block-conflict` (test-support builds only)
  short-circuits the FIRST `POST /v1/blocks` with the REAL registry problem
  (409 `block.number-already-exists`) rendered through the standard
  `ApiError` path — byte-identical to the advisory pre-check's conflict.
  The in-session retry passes through to the real handler.
- Entire module (middleware + control route) lives behind
  `#[cfg(feature = "test-support")]` — compile-time absence in release
  binaries. The control route is deliberately NOT in the utoipa derive
  (`openapi_drift` guards this) and the auth requirement classification
  (`/__faults` → `Authenticated`) costs production nothing.
- Motivation: the season-setup-wizard Gherkin partial-failure scenario
  previously arranged failure only client-side; the wizard derives block
  numbers from the projections (`max + 1`), so a real deterministic 409
  needs an injectable server-side failure point.
- 3 latch unit tests + 5 router-integration tests
  (`--features test-support --test fault_injection_test`).
- **No additional bump:** dev/test-only surface with no public API change —
  rides with the open 0.10.0 MINOR.

### Fixed — graceful shutdown joined AI workers twice (found via issue #428)

- `shutdown_ai_import` re-awaited each worker `JoinHandle` after the bounded
  join-budget timeout had already polled it to completion — a completed
  `JoinHandle` re-poll panics the main task ("JoinHandle polled after
  completion"), so every graceful shutdown that joined a worker normally
  (Ctrl-C with AI import enabled) crashed the API instead of exiting cleanly.
  The post-abort join (issue #214 permit-drop proof) is unchanged and still
  happens — only on the abort path, where the handle is genuinely unpolled.
- The join loop is extracted into `join_worker_with_budget` with three
  regression tests (normal completion, worker panic, stuck-worker abort).
- Found while wiring the dev AI-import one-liner (issue #428), which makes
  AI import trivially reachable in host-run dev sessions.
- **No additional bump:** behavior bugfix with no public API change — rides
  with the open 0.10.0 MINOR.

### Added — `ApiError::FeatureDisabled` variant + `ai-import.disabled` code (issue #422)

- The AI import endpoints (`POST /ai-import/{scripts,schedules}`, provider
  and model discovery) return 404 `ai-import.disabled` instead of the
  overloaded generic `domain.not-found` when `AI_IMPORT_ENABLED` is unset —
  the client can now branch on the stable `code` and render a dedicated
  "not enabled here" state without a futile retry affordance (issue #422).
- New `ApiError::FeatureDisabled(&'static str)` variant maps to the new
  registry code through the single problem builder; the three handler call
  sites switched, the disabled-state test now asserts the code, and
  `openapi.yaml` declares the 404 on the two discovery routes (regenerated,
  drift-checked).
- **No additional bump:** additive public-API extension — rides with the
  open 0.10.0 MINOR.

### Added — scoped forbidden `ApiError` variants for the AI/settings gates (issue #470)

- Three new `ApiError` variants map the handler-internal authz-gate denials
  through the single problem builder to scoped per-aggregate codes instead
  of the generic `domain.forbidden`: `AiConfigForbidden` →
  `ai-config.forbidden` (AI-config management create/get/list/update/revoke
  + provider/model discovery, credential-role gates), `AiImportForbidden` →
  `ai-import.forbidden` (AI import job upload block-scope / status / preview
  / apply season-role and ownership gates), and `SettingsForbidden` →
  `settings.forbidden` (settings-credential create/rotate/update/revoke,
  credential-role gates). `forbidden_ai_config()` now renders
  `ai-config.forbidden`; a new `forbidden_ai_job()` renders
  `ai-import.forbidden`; the five settings credential handlers switched to
  `SettingsForbidden`. The `list_ai_import_jobs` visibility filter matches
  the new `AiImportForbidden` variant (foreign/scope-denied jobs are still
  skipped, not surfaced).
- Handler-level tests now assert the scoped codes (issue #470 req. "wire
  contract can't drift again") in `handler_ai_import_authz.rs`,
  `handler_ai_import_ports.rs`, `handler_authz_batch2.rs` and the
  `ai_import_tests.rs` unit; `openapi.yaml` `x-code-registry` refreshed.
- **No additional bump:** additive public-API extension — rides with the
  open 0.10.0 MINOR.

### Fixed — OpenAPI nullability for optional `Decimal` / `NaiveDate` fields (issue #423)

- Regenerated `backend/openapi.yaml` after the core fix (issue #423):
  `CharacterMeasurements` (all seven properties) and `BlockView` /
  `CreateBlock` / `UpdateBlockTimeSpan` date fields now render as
  `type: [string, 'null']` and are no longer listed under `required` —
  the wire contract now matches the runtime serialization (`None` → JSON
  `null`). The previously dishonest, non-nullable contract broke the
  generated Dart client on every character list read with unset
  measurements.
- The regenerated `vendor/breakdown_api` Dart client (frontend-flutter)
  now declares `String?` for all affected fields and omits nulls on
  serialize.
- **No additional bump:** artifact + generated-client change only — the
  public Rust API is unchanged; rides with the open 0.10.0 MINOR.

### Added — `GET /v1/ops/projector-health` ops endpoint (issue #409)

- New deployment-scoped ops surface over the #37 dead-letter + checkpoint
  tables: returns `ProjectorHealthSnapshot` (`dead_letter_count`,
  `dead_letters` bounded by `limit` 1–500 default 100, `checkpoints`).
- Authorization (the #409 decision): handler-internal `// AUTHZ-GATE:` via
  `AuthorizationPolicy::authorize_ops` — active `ops_admin` membership in any
  block **or** the `OPS_ADMIN_SUBS` bootstrap allowlist (comma-separated
  trusted OIDC subs, resolved once at state construction; empty by default).
  Route classified `Authenticated` (`requirement_for("/ops")`); failures map
  to existing registered codes (`domain.forbidden`, `http.bad-query-param`,
  `http.internal-error`) — no new problem codes.
- Ops escalation guard: `invite_member` / `grant_role` reject
  `role: ops_admin` from callers without ops access (403) — block-scoped
  costume roles can never self-escalate into the ops capability.
- `Ports` gains `ProjectorHealthRepo` (+ accessor); `test-support` fakes
  updated. utoipa schemas registered; `openapi.yaml` regenerated.
- Rides with the open 0.10.0 MINOR; no additional bump.

### Fixed — 409 pre-checks for cross-aggregate uniqueness invariants (issue #404)

- `POST /shooting-days/{day_id}/scenes/{scene_id}/scene-shoots`,
  `POST /seasons`, `POST /blocks`, `POST /episodes`: the handlers now check
  the corresponding read-model lookup **before** dispatch (the only
  legitimate CQRS consumer — AGENTS.md §1) and answer a violation with a
  clean 409 (`scene-shoot.pair-already-exists`,
  `season.number-already-exists`, `block.number-already-exists`,
  `episode.number-already-exists`) instead of the old 2xx whose
  `*Created`/`SceneShootPlanned` event became a projector-killing poison
  event (23505). Pre-checks are advisory — the projection unique
  constraints remain authoritative against races. Fluent texts in both
  locales, golden snapshots updated.
- Rides with the open 0.10.0 MINOR; no additional bump.

> **Note (release owner):** this section bundles the entries that accumulated
> under `[Unreleased]`. Two of them were written as “no version bump”
> (#29, test-only) / “PATCH bump” (#270); they ship with the **D3 cascade**
> that the series-scoped audit gate (#342) triggers from `core` 0.10.0, so the
> released version is **0.8.1 → 0.9.0**. The per-entry notes below keep their
> original reasoning. Issue #337 below adds new public routes on top, moving
> the release to **0.10.0**.

### Added — `GET /v1/seasons` series-scoped seasons list (issue #377)

- `list_seasons` serves `SeasonRepository::list_by_series` when `series_id`
  is given and the new `SeasonRepository::list_all` port otherwise, over a
  dedicated `SeasonListParams` (`limit`/`offset` + optional `series_id`;
  sibling scopes stay out of the contract, issue #377 review). Negative
  `limit`/`offset` fail with `400 http.bad-query-param` at the API edge
  (documented as `minimum: 0` in the spec) instead of reaching the
  projection query. No scope parameter is required —
  unlike the episode/scene lists — so the client's parameterless
  `fetchSeasonsList()` reconciliation confirms a created id regardless of
  the series it was filed under, and the full-snapshot cache write
  (`applySnapshot`, which deletes missing ids) stays coherent. The route
  keeps the `Authenticated`-only requirement (`/seasons` prefix already
  classifies that way); no handler-internal auth gate applies, matching the
  sibling collection lists.
- `backend/openapi.yaml` regenerated (`operationId: list_seasons`). The
  wire contract is additive, so the `/v1` path version stays (ADR-021 D1).
  The generated Dart client regenerates Flutter-side (unblocks the client's
  `seasonsListFetch` seam and the 4.1 on-device smoke below seasons).
- New `crates/api/tests/handler_season_list.rs`: unscoped list returns every
  series, `series_id` narrows + number ordering, and an `api_doc()`
  assertion that `GET /v1/seasons` exposes `series_id`. `FakeSeasonRepo`
  gains a map-backed `seasons` store so `list_all`/`list_by_series`
  filter/sort/paginate like the production projector queries.
- Rides with the open 0.10.0 MINOR; no additional bump.

### Fixed — `PATCH /v1/shooting-days/{id}` explicit date/label clear (issue #372)

- `UpdateShootingDayRequest.date` / `.label` are presence-tracked
  (`Option<Option<..>>` with `#[serde(default, deserialize_with = …)]`): an
  absent field means "no update", an explicit JSON `null` (`Some(None)`)
  clears the value (unschedule / rename-to-null), and a value
  (`Some(Some(v))`) sets it. Previously both fields were plain `Option<T>`,
  so serde collapsed explicit `null` and absent identically to `None` and
  every clear fell through to `422 no update field provided` — the
  unschedule/rename-to-null affordance was inexpressible end to end. The
  handler dispatches `Some(date)` (including `None`) to `reschedule` and
  `Some(label)` (including `None`) to `rename`; `order_key` is unchanged.
- `backend/openapi.yaml` regenerated: `date` / `label` are nullable
  (`type: [string, 'null']`), optional, with the three-state semantics in the
  schema description, so the regenerated Dart client can express the clear
  (client regeneration itself stays Flutter-side, per the issue non-goals).
- New `crates/api/tests/handler_shooting_day.rs`: serde three-state cases
  plus handler dispatch cases (reschedule with date, unschedule with explicit
  null, rename with label, rename-to-null, and the 422 no-field case).
- Rides with the open 0.10.0 MINOR; no additional bump.

### Added — AI import discovery routes + typed preview (issue #337)

- `GET /v1/ai-import/config`: the caller's configs, newest-first
  (`ListParams` pagination), behind the credential-role `// AUTHZ-GATE:`.
- `GET /v1/ai-import/jobs`: the caller's jobs, newest-first (`ListParams`
  pagination), owner-scoped with per-row season-gate filtering (denied rows
  are skipped, infra errors propagate).
- `GET /v1/ai-import/jobs/{id}/preview` now serves the typed
  `AiImportPreviewResponse` envelope (`script` / `schedule` / `merged`
  union); corrupt blobs are `422 domain.validation`.
- **MINOR bump (ADR-020 D2):** new public routes + response type:
  **0.9.0 → 0.10.0**.

### Fixed — AI import review follow-ups (issue #337)

- `GET /v1/ai-import/jobs` paginates the gate-filtered (visible) rows: the
  per-row season gate now runs before `LIMIT`/`OFFSET`, so denied rows ahead
  of the window can no longer punch holes into (or empty out) the page. The
  store is scanned in bounded 100-row windows until the visible window is
  full or exhausted.
- `GET /v1/ai-import/jobs` and `GET /v1/ai-import/config` return
  `Cache-Control: no-store` via the shared `no_store_json` helper, matching
  the single-item AI endpoints (`GET …/jobs/{id}`, `…/preview`).
- `GET /v1/ai-import/jobs/{id}/preview` declares the reachable `422
  domain.validation` response for corrupt preview blobs in `openapi.yaml`
  (the Dart client regenerates byte-identical: error-only changes emit no
  client code).
- Rides with the 0.10.0 MINOR above; no additional bump.

### Fixed — Dev-auth fallback gated on OIDC_ISS absence (issue #270)

- `AuthState::from_env_or_dev()` no longer falls back to unverified-token dev
  mode on a partial/misconfigured OIDC config. Dev mode is now entered only
  when `OIDC_ISS` is absent **and** `DEV_AUTH_SUB` is present; when `OIDC_ISS`
  is set, a missing `OIDC_AUDIENCE`/`OIDC_JWKS_URL` fails the boot loudly
  instead of silently disabling token verification. PATCH bump (ADR-020 D2).

### Added — OpenAPI review artifact & drift check (issue #29)

- **Test-only:** `crates/api/tests/openapi_drift.rs` renders `api_doc()` as
  canonical YAML and diffs it against the checked-in review artifact
  `backend/openapi.yaml` (`UPDATE_OPENAPI=1` regenerates). No public API
  change; no version bump.

### Added — `GET /v1/episodes` accepts an optional `block_id` filter (issue #335)

- A dedicated `EpisodeListParams` type carries an optional
  `block_id: Option<BlockId>` query parameter for `list_episodes` only, so
  sibling list operations no longer advertise a filter they ignore (issue
  #335 review). `list_episodes` serves it from the existing
  `EpisodeRepository::list_by_block` port (limit/offset apply per block);
  without `block_id` the handler keeps requiring `series_id` and serving
  `list_by_series`, so existing callers (no filter, `series_id`) are
  unaffected. Missing both `block_id` and `series_id` still fails with
  `400 http.bad-query-param`.
- `backend/openapi.yaml` regenerated (`block_id` is documented only on
  `GET /v1/episodes`). The wire contract is additive, so the `/v1` path
  version stays (ADR-021 D1). No crate version bump.

### Changed — `PlanSceneShootRequest` drops redundant path identifiers (issue #346)

- `POST /v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots` no longer
  takes `scene_id` / `shooting_day_id` in the request body: both identifiers
  come from the path only, and the two body/path equality checks (plus the
  `400` mismatch response they produced) are removed. The body is now
  `{ planned_order }` only. The core `PlanSceneShoot` command is unchanged —
  it still carries both ids, populated at the API edge from the path.
- `backend/openapi.yaml` regenerated and
  `frontend-flutter/vendor/breakdown_api/` regenerated (only
  `plan_scene_shoot_request.{dart,g.dart}` change).
- **Pre-release-cleanup exception to ADR-021 (no `/v2`):** the route family
  was only just exported in #344 (issue #333) and no shipped client sends
  these fields yet, so there is no deployed consumer to protect with a
  deprecation window. Once a client ships against a contract, ADR-021
  D2/D3 apply in full. No crate version bump beyond the open 0.10.0.

### Changed — `GET /v1/audit` is series-scoped, not block-scoped (issue #342)

- **Authorization classification (behavior change):** `requirement_for()` now
  returns `Authenticated` for the exact path `/audit`. The journal is filtered
  by the `series_id` **query parameter**, so the caller's active block
  (`X-Active-Block`) is unrelated to the series being read and the previous
  `BlockMember` classification gave false assurance: any caller with an
  active membership in *any* block could read the journal of *any* series.
- `get_audit_history` now performs the membership check itself behind an
  `// AUTHZ-GATE:` comment — `MembershipRepository::has_active_membership_in_series`
  — and returns `403 domain.forbidden` on denial. It fails closed: a
  repository error denies. The predicate is role-agnostic: any *active*
  membership in the series grants access.
- The block-scoped twin `/blocks/{id}/audit` keeps `Requirement::BlockMember`.
- `backend/openapi.yaml` regenerated: the operation documents the `400`
  (missing `series_id`) response alongside `403`, and both descriptions now
  name the actual condition. Additive contract change — the `/v1` path
  version stays (ADR-021 D1).

### Changed — Version cascade (ADR-020 D3)

- **MAJOR (cascade):** re-pinned to `breakdown_core` 0.10.0 and `infra`
  0.15.0; `api` bumps **0.8.1 → 0.9.0**. On its own this change would need no
  bump at all (behaviour + additive contract), but D3 makes every consumer of
  the broken `core` API carry a MAJOR.

### Fixed — Export the served scene-shoot / continuity-photo / wrap / JSON-report routes (issue #333)

- `backend/openapi.yaml` was missing 19 served, `#[utoipa::path]`-annotated
  operations: the `SceneShoot` execution endpoints (plan / replan / get /
  list / start / actual-order / finish / skip), the scene-shoot note endpoints,
  the continuity-photo endpoints, `POST /shooting-days/{id}/wrap`, the three
  JSON report routes (`dispo`, `shoot-day`, `soll-ist`) and `GET /v1/audit`.
  They are now registered in `ApiDoc`'s `paths(...)`/`components(schemas(...))`,
  so the generated Dart client (`vendor/breakdown_api/`) covers them.
- Declared path parameters for all operations whose handler uses a
  single-value `Path(id): Path<Newtype>` extractor (utoipa only infers tuple
  `Path` extractors): this also completes the four pre-existing report routes
  (`dispo.pdf`, `shoot-day.pdf`, `planned-vs-actual.pdf`, `report/archive`).
  `VersionRequest` now derives `IntoParams` so `Query<VersionRequest>` handlers
  document their `version` query parameter.
- **Authorization classification (behavior change):** `requirement_for()` now
  returns `Authenticated` for the JSON report routes (matching their `.pdf`
  twins, which already relied on the handlers' internal `AUTHZ-GATE`) and for
  the continuity-photo routes (they spell the segment `/continuity-photos`,
  which the `contains("/photos")` test missed, so they fell through to
  `BlockMember` although their handlers follow the authenticated-only +
  handler-internal-gate pattern mandated by AGENTS.md §7).
- No Rust public API change; the wire contract is additive, so the `/v1` path
  version stays (ADR-021 D1). No crate version bump.

### Fixed — `POST /v1/costumes/{id}/unassign` declares `VersionRequest` body (issue #336)

- The `unassign_costume` handler deserializes `VersionRequest` (`version` only)
  but the `#[utoipa::path]` annotation declared `UpdateCostumeNotesRequest`
  (`notes` + `version`), forcing generated clients to send a meaningless
  `notes` echo. The annotation now references `VersionRequest`;
  `backend/openapi.yaml` regenerated. No Rust public API change; the wire
  contract sheds an ignored required field, so the `/v1` path version stays
  (ADR-021 D1). No crate version bump.

### Added — Per-operation RFC 9457 error responses in the OpenAPI contract (issue #343)

- Every operation now declares its failure surface with `body = ProblemDetails`
  (rewritten to `application/problem+json` by `api_doc()`), following per-verb
  minimum sets: 422+409 for POST creates, 404+422+409 for PATCH/PUT, 404+409
  for DELETE, 404 for id-addressed GETs, 400 for collection GETs with required
  query params, 403 where an `AUTHZ-GATE` exists. Collection list operations
  also carry an operation `description` naming the conditional scope-parameter
  requirement (`series_id`/`season_id`/`episode_id`; `series_id` only without
  `block_id` on `GET /v1/episodes`).
- New `openapi_drift` regression test: every operation must document at least
  one non-2xx `application/problem+json` response typed as `ProblemDetails`,
  and every declared non-2xx response must carry that typed body.
- `backend/openapi.yaml` regenerated. Docs-only: no Rust public API change,
  no wire behavior change (generated Dart client byte-identical), so the
  `/v1` path version stays (ADR-021 D1). No crate version bump.

## [0.8.0] - 2026-08-23

### Changed — Bump MSRV to 1.98 (issue #257)

- **Breaking (MAJOR, ADR-020 D2/D3):** `rust-version` raised from `1.94` to `1.98` (workspace floor + Dockerfile builder `rust:1.98-bookworm`). Re-pinned to `breakdown_core` 0.9.0 and `infra` 0.14.0 (cascade).

## [0.7.1] - 2026-08-13

### Changed — Publish documentation assets via draft release (immutable releases)

- Re-release to attach the versioned architecture PDF/HTML to the GitHub
  Release: `docs.yml` now creates the release as a draft with the assets
  attached inline and publishes afterwards (`gh release edit --draft=false`),
  because GitHub immutable releases (2025+) reject post-hoc asset uploads
  (HTTP 422) and lock the tag once published. No code changes; version bump
  only (ADR-020 D6, PATCH).

## [0.7.0] - 2026-08-13

### Added — RFC 9457 problem-detail error surface (issue #230)

Every error response is now an `application/problem+json` document with a
stable `{context}.{reason}` code, `trace_id`, typed S0/S1 extension fields
and an `Accept-Language`-localized `detail` (Fluent, `de` default / `en`).
Handlers propagate with `?`; status mapping lives in the single problem
builder (`crates/api/src/problems`) fed by the registry
(`crates/core/src/error_registry.rs`, 73 codes).

- **Breaking:** response bodies change from `{message}` to the problem
  envelope; domain-validation failures return 422 instead of 400 (ADR-031).
  Clients must branch on `code` — see `docs/errors/` for the migration
  guide and the full code catalogue.
- New runtime deps: `fluent`, `fluent-bundle`, `unic-langid`,
  `accept-language` (server-side i18n; core stays dependency-free);
  `indexmap` (registry-woven OpenAPI docs); `http-body-util` promoted from
  dev-dependencies (the `Json` extractor collects limited request bodies).
- Bundle-coverage lint + golden snapshots enforce the surface; the S2
  ast-grep rule bans person identifiers in problem-builder code.
- **Breaking (cascade):** re-pinned to `breakdown_core` 0.8.0 (ADR-020 D3);
  api bumps 0.6.1 → 0.7.0.

## [0.6.1] - Unreleased

### Changed — Persist the declared AI import source format (issue #221)

- `POST /ai-import/schedules` persists the upload's declared format
  (`text/csv` → `csv`, `application/pdf` → `pdf`, `text/plain` →
  `plain_text`) on the job. The schedule worker now routes CSV natively and
  PDF/plain-text through the LLM extraction path; PDF schedules are extracted
  to text before the LLM call, so `application/pdf` schedule uploads work
  end-to-end for the first time.

### Changed — Wire the AI concurrency limiter into the composition root (issue #214)

`main.rs` now constructs the AI import concurrency limiter and workers when
`AI_IMPORT_ENABLED` is set, so the `AI_IMPORT_MAX_CONCURRENT_JOBS_*` ceilings
are actually enforced at runtime and jobs consume capacity through
`AiWorkerRuntime`.

- `PgAiConcurrencyLimiter` is built from `AiImportBounds`, `.spawn_reclaimer()`
  is called, and the `PermitReclaimer` is held for the process lifetime.
- The script + schedule import worker loops are spawned and their
  `JoinHandle`s stored.
- Graceful shutdown is added: `axum::serve(...)` uses `with_graceful_shutdown`
  driven by SIGTERM/SIGINT. On signal the process signals the workers to stop,
  runs the bounded `AiWorkerRuntime::drain()` (bounded by `DRAIN_TIMEOUT`, 15s),
  joins the worker tasks (aborting any that exceed the join budget), drops all
  limiter clones, then awaits `PermitReclaimer::shutdown()`. The whole sequence
  is bounded so shutdown cannot hang.
- The whole path is gated behind `AI_IMPORT_ENABLED`; the default deployment
  is unaffected.

### Changed — No in-memory AI payload store in the composition root (issue #181)

- `main.rs` no longer constructs a `MemoryAiPreviewStore`. When AI payload
  storage is unconfigured (only reachable with AI import *disabled* — the boot
  gate from #174 already refuses the enabled-without-storage combination), the
  AI payload ports are filled with `infra::ai::UnconfiguredAiPayloadStore`,
  which refuses every operation with `503`. The in-memory store accepted
  payloads and dropped them on restart, so a persisted job row could outlive
  its own payload.
- The job-status response can now carry `"payload_unavailable"` for a job whose
  durable payload is gone. Applying such a job already returned `409` (apply
  requires `succeeded`); this makes the reason visible to the client instead of
  it appearing as a generic dead-letter.

### Changed — Re-pin `infra` to 0.12.0

- Consumes the new AI import permit-reconciliation API — `AiImportQueue`'s
  `claim_next_reconciling` / `attach_permit` / `release_claim` and the
  `run_once_with_permit` worker entry points (issue #180). No public API
  change.

## [0.6.0] - Unreleased

### Changed — Idempotent scene scheduling (issue #179)

- `POST /scenes/{id}/shooting-days` now returns `200 OK` with the unchanged
  aggregate version when the scene already links the given shooting day; it
  previously returned `409 Conflict`. This follows the Scene aggregate becoming
  state-idempotent for `ScheduleSceneOnShootingDay`, which is what lets a
  crashed AI schedule-apply converge on retry instead of stranding its
  idempotency mapping. A **stale** `version` still returns `409`, so
  optimistic-concurrency clients are unaffected.
- No `api` code change otherwise: the new `AiImportMappingRepository::reserve`
  method is consumed entirely inside `infra`'s `ScheduleApplyWorker`; only the
  test fake implements it.

### Changed

- Re-pins `breakdown_core` to 0.7.0 and `infra` to 0.11.0 (AI import worker
  leases + owner-fenced lifecycle writes, issue #177). No `api` code change:
  the composition root keeps building `PgAiImportQueue::new` (which now reads
  the lease window from `AI_IMPORT_LEASE_SECS`), and the AI handlers only call
  `record_telemetry`, which is not owner-fenced. The MINOR bump reflects the
  `AiImportQueue` port change surfacing through `Ports::AiImportQueue`: any
  external `Ports` implementor with its own queue must add the `worker_id`
  parameter.

## [0.5.0] - Unreleased

### Changed

- **Breaking (source):** `Ports` now exposes the AI import dependencies
  through the hexagonal seam (issue #176). Seven associated types
  (`AiConfigCommands`, `AiConfigRepo`, `AiImportQueue`, `AiImportMappingRepo`,
  `AiPreviewStore`, `AiDocumentStore`, `AiDocumentSource`) and their accessors
  were added, so every `Ports` implementor must supply them. The three payload
  types are `?Sized` so production keeps its boot-time
  `Arc<dyn AiPreviewStore>` choice (durable S3 vs. in-memory) behind one port.
  The command ports used by the AI apply workers (`SceneCommands`,
  `ShootingDayCommands`, `SceneShootCommands`) gained a `+ Clone` bound —
  the handlers hand owned clones to `ApplyWorker` / `ScheduleApplyWorker`.
- **Breaking (source):** `ProductionPorts::new` takes a single `AiPorts` value
  instead of the seven trailing AI parameters. `AiPorts` is a pure parameter
  bundle (no behavior, no defaults); the composition root in `main.rs` is the
  only caller and behavior is unchanged.
- All twelve AI import handlers (`upload_ai_script`, `upload_ai_schedule`,
  `get_ai_import_job`, `get_ai_import_preview`, `apply_ai_import`,
  `create_ai_config`, `get_ai_config`, `update_ai_config`, `revoke_ai_config`
  and the internal `authorize_ai_block` / `authorize_ai_job` /
  `enqueue_ai_upload` helpers) are now generic over `P: Ports` instead of
  being hard-wired to `AppState<ProductionPorts>`. The routes bind
  `::<ProductionPorts>` explicitly, matching every other handler. Tests can
  now drive the AI routes with fakes — no PostgreSQL-backed adapter required,
  including `apply_ai_import` (the handler that clones the command ports into
  `ApplyWorker` / `ScheduleApplyWorker` and holds the cross-block IDOR gate).
- Removed the inherent `ProductionPorts::ai_*` getters; they are superseded by
  the `Ports` trait accessors of the same names.
- AI import authorization gates (`authorize_ai_block`, `authorize_ai_job`,
  `credential_role_gate`, `list_ai_providers`, `list_ai_models`) now route
  through the `AuthorizationPolicy` held by `AppState` instead of calling
  `membership_repo()` directly (issue #175). `AppState` gains a public
  `authorization_policy: Arc<dyn AuthorizationPolicy>` field, constructed
  once from the membership read model; `main.rs` shares it with the
  middleware instead of rebuilding a second policy. Behavior is preserved:
  `403` on denial, `// AUTHZ-GATE:` comments retained, and read-model
  failures stay mapped errors (never silent denial).
- Re-pins `breakdown_core` to 0.6.0 (fallible policy checks, issue #175).

## [0.4.7] - Unreleased

### Changed

- The `REQUIRE_IN_TRANSIT_TLS` startup gate (ADR-024) now also validates the
  AI payload storage link: `AI_PAYLOAD_S3_ENDPOINT` must use `https://` and,
  when it does, `AI_PAYLOAD_S3_TLS_ROOT_CERT` must be set so the OpenDAL
  client is pinned to the internal step-ca root (issue #201).

## [0.4.6] - Unreleased

### Changed

- Re-pins `infra` to 0.10.0 (AI payload cleanup worker; issue #198).

## [0.4.5] - Unreleased

### Changed

- AI import upload handlers now use `AiDocumentStore::put_source` for
  storing source documents, separating them from preview payloads.
- Re-pins `infra` to 0.9.0 (consumes the new `AiDocumentStore` trait and
  `OpenDalAiPayloadStorage`; under major-zero semver this is a MINOR bump,
  ADR-020 D2/D3).

## [0.4.4] - Unreleased

### Changed

- `list_ai_providers` and `parse_ai_provider` now delegate to the
  centralized provider registry (`infra::ai::provider_registry`). The
  duplicated provider metadata in handler code is removed; adding a
  provider no longer requires touching the API handler module.
- Re-pins `infra` to 0.8.0 (consumes the new `provider_registry` module;
  under major-zero semver this is a MINOR bump, ADR-020 D2/D3).

## [0.4.3] - Unreleased

### Changed

- Ships the CQRS-safe merge refactor (issue #172) in the `api` image:
  `core` is re-pinned to 0.5.0 and `infra` to 0.7.0. The AI merge worker
  no longer queries read-model projections; scene context is prepared as an
  immutable `MergeInput` at the API boundary. PATCH release (ADR-020 D6):
  no crate API or HTTP wire-contract change; HTTP path version stays `/v1`
  (ADR-021 D2).

## [0.4.2] - 2026-08-07

### Fixed

- Ships the AI import telemetry fix (issue #171) in the `api` image: `core`
  is re-pinned to 0.4.0 and `infra` to 0.6.0, which record never-applied
  jobs with `edit_distance = NULL` (`NotApplied`) instead of a misleading
  `0`, while applied zero-edit outcomes keep `edit_distance = 0`. PATCH
  release (ADR-020 D6): no crate API or HTTP wire-contract change
  (`ApplyAiImportRequest` still carries `accept_as_is` + `edit_distance`);
  HTTP path version stays `/v1` (ADR-021 D2).

## [0.4.1] - 2026-08-06

### Fixed

- Ships the AI import transport security fix (issue #170) via the `api`
  image: `infra` is re-pinned to 0.5.0, which enforces an HTTPS-only policy
  for hosted AI providers, restricts Ollama to local addresses, and adds a
  DNS-rebinding guard (hosted destinations must resolve to globally routable
  addresses; validated addresses are pinned). PATCH release (ADR-020 D6):
  no crate API change, HTTP path version stays `/v1` (ADR-021 D2).

### Internal

- Follow-up refinements to the ADR-020/ADR-021 path-versioning rollout
  (versioning layer, route wiring, auth test coverage).

### Dependency updates (ADR-020 D7 bookkeeping)

- sha2 0.10 → 0.11 (plus workspace-level bumps released with `infra` 0.5.0:
  aes-gcm, base64, getrandom, opendal, rand_core, redis, schemars, serde)
