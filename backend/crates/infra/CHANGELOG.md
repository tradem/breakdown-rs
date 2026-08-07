<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (opencode-go) -->

# Changelog

All notable changes to the `infra` crate are documented here. Versioning
follows per-crate Semantic Versioning (ADR-020 D2); this changelog is the
crate-level companion to the release notes generated from conventional
commits (ADR-020 D5).

## [0.10.0] - Unreleased

### Added — AI payload cleanup worker (issue #198)

- New `ai::payload_cleanup` module with periodic garbage collection for
  AI import payloads in Garage. Deletes source documents and preview
  payloads for terminal-state jobs (succeeded/failed/dead_letter) after
  a configurable grace period (default: 7 days).
- Advisory-locked sweep prevents concurrent cleanup runs.
- Dry-run mode for safe initial rollout (`AI_PAYLOAD_GC_DRY_RUN=true`).
- History table `projection_ai_payload_gc_run` tracks cleanup runs.
- New `AiPayloadGcConfig` type for cleanup configuration.
- Environment variables: `AI_PAYLOAD_GC_ENABLED`, `AI_PAYLOAD_GC_INTERVAL_SECS`,
  `AI_PAYLOAD_GC_MAX_AGE_SECS`, `AI_PAYLOAD_GC_BATCH_SIZE`, `AI_PAYLOAD_GC_DRY_RUN`.

### Added — Durable AI payload storage (issue #174)

- New `ai::payload_storage` module with `OpenDalAiPayloadStorage` adapter
  that stores source documents and preview payloads in S3-compatible
  object storage (Garage). Replaces `MemoryAiPreviewStore` in production.
- New `AiDocumentStore` trait with `put_source`, `get_source`,
  `delete_source` methods for storing source documents separately from
  preview payloads.
- Source documents and preview payloads now survive API restarts: pending
  jobs can resume, retries can reload source documents, and succeeded
  jobs continue serving previews.
- Environment variables: `AI_PAYLOAD_S3_ENDPOINT`, `AI_PAYLOAD_S3_ACCESS_KEY`,
  `AI_PAYLOAD_S3_SECRET_KEY`, `AI_PAYLOAD_S3_BUCKET`, `AI_PAYLOAD_S3_TLS_ROOT_CERT`.
- Integration test `ai_payload_storage_round_trip` verifies restart-recovery
  behavior and payload lifecycle.

## [0.8.0] - Unreleased

### Added — Centralized LLM provider metadata (issue #173)

- New `ai::provider_registry` module with an exhaustive `PROVIDER_REGISTRY`
  table that maps each `LlmProvider` variant to its canonical key and
  supported aliases. Adding a provider now requires exactly one entry here
  plus a matching arm in core's `as_str` match — no other files change.
- `ai::list_providers()` returns curated provider info for the
  `/ai-import/providers` endpoint.
- `ai::resolve_provider(value)` resolves a user-supplied key or alias to
  its canonical `LlmProvider` variant.
- `ai::curated_models()` and `ai::curated_model_ids()` moved from the
  module-level `curated_models` function into the registry (re-exported
  from `ai`).
- Unit tests covering registry completeness, canonical-key resolution,
  alias resolution, unknown-value rejection, list ordering, model
  coverage, and alias-vs-key non-collision.

### Changed — AI merge worker no longer queries read-model projections (issue #172)

- `QueueMergeWorker` simplified from `QueueMergeWorker<Q, E, S, P>` to
  `QueueMergeWorker<Q, P>`: removed `EpisodeRepository` and `SceneRepository`
  generic parameters. The worker now reads an immutable `MergeInput` blob
  (schedule + pre-loaded scenes) from the preview store and calls
  `merge_from_input()` — never querying a read-model projection at runtime.
- Re-pins `breakdown_core` to 0.5.0 (consumes the new `MergeInput` type;
  under major-zero semver this is a MINOR bump, ADR-020 D2/D3).

## [0.6.0] - 2026-08-07

### Fixed — AI import telemetry: never-applied jobs have NULL edit_distance (issue #171)

- The `ai_import.ai_import_job.edit_distance` column is now **nullable**
  (migration `20260807000001_ai_import_not_applied`). Jobs that never reach
  apply are recorded with `accept_as_is = NULL` and `edit_distance = NULL`;
  an applied job accepted with zero edits keeps `edit_distance = 0` — the two
  outcomes are no longer conflated, so acceptance/edit-rate calculations can
  exclude `NotApplied` jobs.
- The script/schedule/merge workers record `TelemetryApplyState::NotApplied`
  at preview time; the apply path records `Applied { accept_as_is,
  edit_distance }` via the API edge.
- `record_telemetry` binds the apply state as `Option<bool>` / `Option<i32>`
  (NULL for `NotApplied`).

### Changed

- Re-pins `breakdown_core` to 0.4.0 (consumes the new `Telemetry`
  apply-state contract; under major-zero semver this is a MINOR bump,
  ADR-020 D2/D3).

## [0.5.0] - 2026-08-06

### Security fix — AI import provider transport (issue #170)

- Hosted AI providers (OpenAI-compatible) are now reachable over **HTTPS
  only**, and the Ollama endpoint is restricted to **local addresses**.
  Outgoing requests carry a curated redirect policy
  (`curated_provider_redirect_policy`) that blocks redirects to
  non-`https:` hosts for hosted providers and to non-local hosts for Ollama,
  preventing SSRF / credential-exfiltration via redirects.
- **DNS-rebinding guard (hosted regime):** every hosted destination is
  resolved before connecting and rejected unless **all** resolved addresses
  are globally routable — private, loopback, link-local, unique-local,
  CGNAT, multicast, documentation, the 0.0.0.0/8 "this network" range,
  the RFC 2544 benchmarking range (198.18.0.0/15), the Class E reserved
  range (240.0.0.0/4) and the deprecated site-local prefix fec0::/10 are
  blocked even when the hostname and scheme are otherwise allowed;
  IPv4-compatible IPv6 forms (`::a.b.c.d`) are classified by the IPv4 policy
  (`transport::validate_public_resolution`). The validated addresses are
  pinned for the whole request chain (initial request + same-origin
  redirects) via `ClientBuilder::resolve_to_addrs` and system proxies are
  disabled on the hosted client (they would resolve the CONNECT target
  outside the pin) (`transport::build_hosted_client`) — a rebinding attacker
  cannot point the connection at an internal service after validation.
- `OpenAiCompatibleModelCatalog::new` now builds its own HTTP client with the
  redirect policy and a fixed 30-second request deadline. **Breaking change:**
  the `new(http: reqwest::Client) -> Self` signature was replaced by
  `new() -> Result<Self, DomainError>` (under major-zero semver this is
  released as a minor bump; no in-tree caller used the old signature). A
  test seam `with_http(client)` remains for injected clients.
- `OpenAiCompatibleChatClient::new` is now **`async`** (it performs the
  resolution guard and pins the validated provider address). **Breaking
  change:** `new(provider, api_key, timeout)` must now be awaited.

### Added (additive public API)

- New `ai::transport` module with the redirect-policy constructors
  `curated_provider_redirect_policy`, `hosted_provider_redirect_policy` and
  `ollama_redirect_policy` (re-exported from `ai`).
- New `ai::transport::validate_public_resolution` (async DNS resolution
  guard for the hosted regime) and `ai::transport::build_hosted_client`
  (validated + pinned hosted client builder).

### Internal

- Follow-up refinements to the ADR-020/ADR-021 versioning rollout: projector
  `projector_version` guards, event/wire fixture contract tests and
  integration-test fixtures aligned with the released projection schema.

### Dependency updates (ADR-020 D7 bookkeeping)

- opendal 0.52 → 0.58 (S3 / GDrive storage)
- aes-gcm 0.10 → 0.11, base64 0.22 → 0.23, getrandom 0.3 → 0.4,
  rand_core 0.6 → 0.10, redis 1.4 → 1.5, schemars 1.2.1 → 1.2.2,
  serde 1.0.228 → 1.0.229, sha2 0.10 → 0.11
