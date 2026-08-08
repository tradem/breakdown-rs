<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->
<!-- Co-authored-by: longcat-2.0-free (opencode) -->

# Changelog

All notable changes to the `api` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

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
  now drive the AI routes with fakes — no PostgreSQL-backed adapter required.
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
