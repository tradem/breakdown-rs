<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->
<!-- Co-authored-by: hy4-preview (opencode-go) -->

# Changelog

All notable changes to the `api` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.9.0] - Unreleased

> **Note (release owner):** this section bundles the entries that accumulated
> under `[Unreleased]`. Two of them were written as “no version bump”
> (#29, test-only) / “PATCH bump” (#270); they ship with the **D3 cascade**
> that the series-scoped audit gate (#342) triggers from `core` 0.10.0, so the
> released version is **0.8.1 → 0.9.0**. The per-entry notes below keep their
> original reasoning.

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
