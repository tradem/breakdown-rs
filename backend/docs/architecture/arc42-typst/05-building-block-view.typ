// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Building Block View

== Level 1: Monorepo Overview

The Breakdown RS monorepo splits into the event-sourced Rust backend
(`backend/`), the Flutter client (`frontend-flutter/`), and the shared OpenAPI
wire contract (`backend/openapi.yaml`).

#diagram("workspace-structure", caption: [Monorepo subsystems, Rust crates, Flutter layers, and contract seam])

== Level 2a: Backend Workspace (`backend/crates/*`)

#table(
  columns: 3,
  table.header([Crate], [Responsibility], [Key Dependencies]),
  [`crates/core`], [Commands, events, aggregates, port traits, read DTOs, `error_registry.rs`], [`serde`, `uuid`, `jiff`, `thiserror` (zero infra crates)],
  [`crates/infra`], [SierraDB adapters, reservation reaper, projectors, `sqlx` queries, `db_time`, OpenDAL photo/payload stores, Typst reports, AI workers, Vault client], [`sqlx`, `kameo_es`, `opendal`, `typst`, `reqwest`, `jiff-sqlx`],
  [`crates/api`], [Axum `/v1` handlers, OIDC + AuthZ middleware, RFC 9457 builder, `main.rs` composition root], [`axum`, `utoipa`, `core`, `infra`],
  [`crates/architecture`], [Source-level boundary tests (`rust_arkitect`, #adr-ref(num: "017", slug: "architecture-testing-strategy", title: "Architecture Testing"))], [`core`, `infra`, `api`],
  [`crates/integration-tests`], [Black-box Tier 1–4 tests against live PostgreSQL and SierraDB containers], [`testcontainers`, `core`, `infra`],
  [`crates/test_support`], [Shared deterministic test context helpers (`make_ctx`)], [`core`],
  [`crates/fuzz-targets`], [Nightly `cargo-fuzz` targets for request deserialization], [`libfuzzer-sys`, `api`, `core`],
)

== Level 2b: Core Domain Modules (`crates/core`)

Each module in `crates/core` owns its commands, events, aggregate state, and
read DTOs. Modules interact across boundaries only through `UUIDv7` identifiers
and port traits.

#diagram("core-modules", caption: [Bounded contexts inside crates/core])

#diagram("core-domain-model", caption: [Core aggregate roots and value objects])

=== Production Hierarchy

- *Hierarchy chain*: `ProjectId` (opaque tenant seam, #adr-ref(num: "035", slug: "production-kind-flexible-hierarchy", title: "Production-Kind-Flexible Hierarchy")) → `season` → `block` → `episode` → `scene`.
- *Season lifecycle*: `ArchiveSeason` sets a terminal `archived` flag. Archived
  seasons reject mutations with `409 season.archived`, keep their number
  reserved, and stay readable.
- *Shooting days and continuity*: `shooting_day` tracks calendar days per
  episode and sets `wrapped_at` on `WrapShootingDay`. `scene_shoot` tracks one
  scene execution on one shooting day with `planned_order` (`Soll`),
  `actual_order` (`Ist`), notes, and continuity photos.

=== Wardrobe Domain (`piece` and `outfit`)

- *Piece (fundus garment)*: `PieceAggregate` owns a name, an optional
  `costume_category` reference, descriptive details, photos, and an `m:n`
  season repertoire (`PieceAggregate.seasons`). A piece has no character owner.
- *Outfit (character look)*: `OutfitAggregate` belongs to one mandatory
  `character`, groups `0..n` ordered `PieceId` entries (layering permitted),
  and supports copy-on-write forks (`variant_of`).
- *Scene casting*: `SceneAggregate` casts outfits per character as ordered
  `SceneOutfitBeat` records. Scenes never cast bare pieces.
- *Category seeding*: `SeasonSeedingSaga` reacts to `SeasonCreated` and creates
  default categories from `config/default_costume_categories.toml` once per
  season.

=== Photo Context

`PhotoAggregate` records metadata and variant states for three `PhotoBinding`
variants: `Piece`, `Outfit`, and `Continuity` (#adr-ref(num: "019", slug: "costume-photo-storage", title: "Costume Photo Storage")).
OpenDAL writes image bytes to Garage. Four reactive tasks manage lifecycle work:
`PhotoThumbnailSaga`, `PhotoDeletionSaga` (refcounted across pieces and
outfits), `ContinuityDeletionSaga`, and `PhotoBytesCleanupSaga`, backed by an
advisory-locked orphan garbage collector.

=== Access, Credentials, Audit, and Reporting

- *Authorization scopes*: `membership` manages block-scoped roles, while
  `project_membership` manages project-scoped costume roles bootstrapped on
  season creation.
- *Secrets bindings*: `settings` binds owner-scoped external credentials stored
  in HashiCorp Vault (#adr-ref(num: "027", slug: "secrets-vault-for-external-credentials", title: "Secrets Vault"), #adr-ref(num: "028", slug: "settings-aggregates-access-control", title: "Settings Access Control")).
- *Audit and reporting*: `audit` projects an insert-only event log. `reporting`
  renders deterministic PDFs in-process with Typst (`Dispo`, `Shoot Day`, and
  day/episode/season `Soll-Ist`) and archives day reports through OpenDAL (#adr-ref(num: "022", slug: "pdf-reporting-and-archival", title: "PDF Reporting")).

=== AI Import Context

`ai` runs as an operational queue in the `ai_import` PostgreSQL schema rather
than as an event-sourced aggregate (#adr-ref(num: "030", slug: "ai-import-bounded-context", title: "AI Import")).
Workers store source and preview blobs in Garage and enforce circuit breakers
and owner-fenced leases. They stream progress over a PostgreSQL `NOTIFY` SSE
hub (#adr-ref(num: "038", slug: "ai-import-sse-progress-and-event-hub", title: "AI Import SSE Progress"))
and apply approved previews through domain commands.

== Level 2c: Flutter Client (`frontend-flutter/`)

#table(
  columns: 2,
  table.header([Directory], [Responsibility]),
  [`lib/core/`], [Framework-free `Result`/`Either` pipelines, `ProblemError` routing, and value objects.],
  [`lib/auth/`], [OIDC PKCE client, `flutter_secure_storage` tokens, and `currentMembershipProvider` gates.],
  [`vendor/breakdown_api/`], [Rebuild-only `dio` client outside `lib/`, generated from `backend/openapi.yaml` (`regen-client.sh`).],
  [`lib/data/`], [Repositories that wrap `breakdown_api` and update the local Drift SQLite read cache.],
  [`lib/domain/`], [Use-case orchestration, optimistic overlays, and bounded-retry projection-lag sync.],
  [`lib/features/`], [One feature folder per aggregate boundary with `@riverpod` controllers and Material 3 screens.],
  [`lib/design/` + `lib/l10n/`], [Design tokens, reusable widgets, and ARB localization catalogs (`de` and `en`).],
)

== Persistence Layout

#table(
  columns: 4,
  table.header([Data Class], [Primary Store], [Read / Cache Store], [Update Mechanism]),
  [Domain aggregates], [SierraDB stream per category + UUIDv7], [`projection_*` tables in PostgreSQL], [`PostgresProcessor` projectors],
  [Uniqueness claims], [SierraDB `reservation` streams (`seasnum-*`, `blocknum-*`, `epnum-*`, `sspair-*`)], [`projection_number_reservation`], [Command adapter + reservation reaper],
  [Photo and AI blobs], [Garage buckets (`costume-photos`, `ai-import-payloads`)], [`projection_photo` / `ai_import` metadata], [OpenDAL CRUD + cleanup sagas / GC],
  [AI import jobs], [PostgreSQL `ai_import.ai_import_job`], [SSE Event Hub (`LISTEN/NOTIFY`)], [Owner-fenced worker updates],
  [External secrets], [HashiCorp Vault (Transit + KV-v2)], [`projection_settings` (`vault_key_id` only)], [`SettingsAggregate` + Vault client],
  [Client read views], [Backend PostgreSQL projections], [Local Drift SQLite on device], [TTL + on-write invalidation + refetch],
)

#important[
  Projections stay flat and query-optimized. Write-side sagas and adapters must
  never read projections to fill in audit fields (`cqrs-boundary` CI rule).
]
