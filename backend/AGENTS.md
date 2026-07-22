# Agent Guidelines for breakdown-rs

You are the primary coding agent for `breakdown-rs` – a collaborative costume scheduling app. Your goal is to implement features securely, test-driven, and with clean architecture.

## 1. Architecture & Core Patterns
- **Hexagonal Architecture / Poor Man's DI:** No DI frameworks. External dependencies are defined as traits (ports) in `core` and manually injected in the composition root (`main.rs`).
- **CQRS & Event Sourcing:**
  - **Write Side:** All state changes occur via **Commands** sent to **Aggregates**. Aggregates validate commands and emit **Events**. State is never updated directly; it is rebuilt by replaying past events.
  - **Read Side:** **Queries** read from flat PostgreSQL **Projections**. Event Handlers asynchronously update these projections when new events occur. Never query aggregates directly for views.
- **kameo_es (Actors):** We use `kameo_es` for Event-Sourced aggregates. Each aggregate is a `kameo::Actor` implementing `kameo_es::Entity`. Commands act as `kameo_es::Command`.

## 2. Workspace Structure
- **`crates/core`:** Pure domain logic. Contains Commands, Events, Aggregates, Read-Model DTOs, and Port Traits. **No dependencies** on `sqlx`, `axum`, or infrastructure.
- **`crates/infra`:** Infrastructure implementations. Contains EventStore integrations, Projectors (Read-Model updaters), and `sqlx` queries.
- **`crates/api`:** Axum web server. Translates HTTP requests to Core Commands (Write) or Infrastructure Queries (Read).

### Production hierarchy (ADR: introduce-season-block-episode-hierarchy)
The domain models a four-level production hierarchy:
`Series` (opaque `SeriesId` only — no aggregate yet) → `Season` → `Block` → `Episode` → `Scene`.
`Character` and `Costume` are scoped to a `Season` (`Character.season_id`) / scope-free (`Costume` is bound only to a `Character`).
Core modules: `season`, `block`, `episode`, `scene`, `shooting_day`, `character`, `costume`, `costume_category`, `shared`.
The `calculation` context was removed; do not reintroduce it.
`shooting_day` is an Episode-scoped `Drehtag` aggregate. It carries a `label`, a `LexicalSortKey`
fractional-ordering value (`shared`), an optional `date`, a `ShootingDaySource` provenance
discriminator (Manual | AiExtracted), and an `archived` flag. Scenes link to ShootingDays via a
many-to-many join (`Scene.schedule_on_shooting_day`) kept on the Scene aggregate; the read model
mirrors it in `projection_scene_shooting_day`. Archived days are excluded from the picker query
`ShootingDayRepository::list_by_episode`.
`SeriesId` is an opaque UUIDv7 seam for a future additive `Series` aggregate — hierarchy entities reference it but no `Series` aggregate exists yet.
`costume_category` is a **season-scoped vocabulary** aggregate (`CostumeCategory`, category `"costume_category"`)
that classifies costume parts (e.g. Oberteil/Unterteil/Schuhe). It carries `season_id`, `name`, a
`LexicalSortKey` order_key, an `archived` flag, and a version. Seeding is a projector-driven **saga**:
on every `SeasonCreated` the `SeasonSeedingSaga` dispatches `CreateCostumeCategory` for the season's
default categories (config `config/default_costume_categories.toml`), guarded by
`CostumeCategoryRepository::count_for_season` so replays never double-seed. `CostumeDetail` is
enriched with optional `subject` and `category_id`; the costume projector resolves `category_name`
from `projection_costume_category` at read time. The command API lives at
`POST/GET /seasons/{season_id}/costume-categories` (and `PATCH`/`POST .../archive` by id);
`POST /costumes/{id}/details` now accepts the enriched `CostumeDetail`.

`photo` is a bounded context (category `"photo"`) that tracks the lifecycle of costume photos
(ADR-019). The `Photo` aggregate is event-sourced in SierraDB and stores photo metadata
(content-type, size, variant statuses). The actual image bytes live in **Garage** (S3-compatible
object store) accessed via OpenDAL. The `PhotoStorage` port is a **non-CQRS-split CRUD port**
for byte storage (read and write on the same store), distinct from the command/repository split
used by other aggregates. Three sagas react to photo events:
- `PhotoThumbnailSaga` — on `PhotoUploaded`, fetches original bytes, decodes+re-encodes
  EXIF-stripped, generates Thumb (200×200) and Medium (800×800) variants.
- `PhotoDeletionSaga` — on `PhotoUnlinked` (costume stream), checks refcount via
  `COUNT(*)` on `projection_costume_photo`; dispatches `DeletePhoto` when zero.
- `PhotoBytesCleanupSaga` — on `PhotoDeleted`, removes all variant bytes from Garage.

A periodic `PhotoGcSweepTask` (advisory-locked) reconciles Garage objects against
`projection_photo` and deletes orphans older than `PHOTO_GC_MAX_AGE_SECS`.

## 3. Workflow & Best Practices
- **EventStorming Mapping:** 
  1. **Event** (Past tense, e.g., `SceneCreated`) -> `enum` in `core`
  2. **Command** (Imperative, e.g., `CreateScene`) -> `struct` in `core`
  3. **Aggregate** (Noun) -> State `struct` in `core`
- **Open-Spec / API First:** Define the API in the OpenAPI spec before writing code. Map exact types using `serde`.
- **ID Generation:** Strictly use **UUIDv7** (`uuid::Uuid::now_v7()`) for all entities and events. No UUIDv4.
- **Security:** Never hardcode secrets. Your code must pass `gitleaks`.

## 4. Testing & Guardrails
- **Unit/Integration Tests:** Write deterministic tests for domain logic in `core`.
- **Mutation Testing:** Run `cargo mutants` ([crate](https://crates.io/crates/cargo-mutants) • [GitHub](https://github.com/sourcefrog/cargo-mutants)). Improve test coverage if mutants survive. Use `cargo mutants --in-diff` to only test changed code. The mutation configuration lives in `.cargo/mutants.toml` — a top-level `.mutants.toml` is **not** read by cargo-mutants, so any settings placed there are silently ignored.
- **Architecture Tests:** We use `rust_arkitect` (source-level) and `cargo-deny` (dependency-level) to enforce boundary rules (ADR-017). Run `cargo test -p architecture_tests` and `cargo deny check bans` to ensure core does not depend on infra/api.

### Integration tests

End-to-end, black-box integration tests live in the dedicated workspace member `crates/integration-tests`. They exercise the full `command → event → event-store → projector → projection` chain against ephemeral containers managed by [`testcontainers`](https://crates.io/crates/testcontainers).

- **Tiers 1–3 (Postgres-only)**: projector and repository tests against an ephemeral PostgreSQL container.
- **Tier 4 (full round-trip, ADR-016)**: `command → SierraDB event persisted → PostgresProcessor catches up → read via *Repository adapter asserts the projection row`, against ephemeral SierraDB (`tqwewe/sierradb:0.3.1`) **and** Postgres containers, with bounded-retry eventual-consistency handling. A second variant verifies projector idempotency under redelivery.
- **How to run locally**: `cargo test -p integration-tests` (requires Docker or a compatible container runtime; Tier-4 tests additionally require network access to pull the SierraDB image).
- **Boundary**: The crate consumes only the `pub` API of `core` and `infra`. It is excluded from the `cargo-mutants` surface — only whitebox `#[cfg(test)]` modules are mutated.
- **CI trigger**: The integration-test job runs on pull requests touching `backend/crates/{core,infra,api,integration-tests}/**`. CI starts both the Postgres and SierraDB containers.
- **Container policy**: Each test gets fresh containers by default. Optional local container reuse is documented in the harness module docs, but CI always uses fresh containers.

### Integration-test Gotchas

When writing Tier-4 integration tests that emit events directly via `eappend`
instead of through the command pipeline, keep these pitfalls in mind:

1. **Missing projectors cause FK violations.** The `projection_costume` table
   has `character_id UUID REFERENCES projection_character(id)`. If a test writes
   a `CharacterCreated` event but does not spawn a character projector, the
   costume projector's INSERT fails silently (the transaction rolls back, the
   supervisor restarts, budget is exhausted). Always spawn projectors for every
   entity type referenced by FK constraints.

2. **Events on the same stream are separate transactions.** A `CostumeCreated`
   event (0 details) and a subsequent `DetailAdded` event are processed in
   different worker transactions. A helper like `await_costume_found` that
   returns on the first successful read may see the row before the detail is
   projected. Use `await_costume_with_details` or equivalent polling helpers
   that check the full expected state, not just existence.

3. **`await_costume_detail_category_name` must retry on `NotFound`.** When the
   costume-category projector hasn't caught up yet, `find_by_id` returns
   `NotFound`. Propagating this as an immediate failure causes flaky tests.
   Always retry on `NotFound` within the deadline, matching the pattern used by
   `await_costume_found`.

### CI prerequisites

The integration-test workflow (`.github/workflows/integration-tests.yml`, ADR-014 / ADR-016) runs on `ubuntu-latest` and requires:

- **Docker** (or a compatible container runtime) available on the runner. The workflow verifies `docker info` and fails loudly if it is missing.
- **Network access to Docker Hub** — the Tier-4 tests pull `tqwewe/sierradb:0.3.1` (in addition to the Postgres image) via `testcontainers`. No manual image preload is required; `testcontainers` pulls automatically.
- No service containers are declared in the workflow — `testcontainers` provisions both tiers per test, so the only host prerequisite is Docker + Hub connectivity.

### CI hardening: SHA-pinning and script-injection hygiene

All GitHub Actions workflows must follow these rules:

- **SHA-pin third-party actions.** Never use a moving tag (`@v7`, `@v2`, `@stable`)
  directly. Always pin to a 40-character commit SHA with a trailing `# v7` comment for
  readability. Dependabot (configured in `.github/dependabot.yml`) opens weekly PRs to
  bump SHAs automatically.
- **Script-injection avoidance.** Never interpolate `${{ github.event.* }}` or other
  expression values directly into a `run:` shell command. Pass them through `env:`
  injection instead (GitHub docs: *Security hardening for GitHub Actions*).

## 5. Code Example: kameo_es Aggregate
```rust
#[derive(Actor, Default)]
pub struct CostumeAggregate { id: Uuid, is_assigned: bool }

impl Entity for CostumeAggregate {
    type ID = Uuid; type Event = CostumeEvent; type Metadata = ();
    fn category() -> &'static str { "costume" }
}

impl Command<CostumeAggregate> for AssignCostume {
    type Reply = Result<(), DomainError>;
    fn execute(self, state: &CostumeAggregate) -> Self::Reply {
        if state.is_assigned { return Err(DomainError::AlreadyAssigned); }
        Ok(CostumeEvent::CostumeAssigned { id: state.id })
    }
    fn apply(event: Self::Event, state: &mut CostumeAggregate) {
        if let CostumeEvent::CostumeAssigned { .. } = event { state.is_assigned = true; }
    }
}
```

## 6. Local Dev Runtime

v1 ships a **Postgres-only** dev compose. SierraDB is not included; the live `command → SierraDB → projector → PG` round-trip is deferred to the `sierradb-runtime-and-round-trip` follow-up change.

### Prerequisites
- Docker (or a compatible container runtime) for the dev database **and** the SierraDB event store.

### Start the dev runtime (both tiers)
The dev compose starts the full two-tier stack from ADR-015 / ADR-016:
Postgres (read model / projections) **and** SierraDB (event store, RESP3).
From the `backend/` directory run:

```bash
docker compose -f docker-compose.dev.yml up -d
```

This starts:
- **Postgres** on `localhost:5432` — user `postgres`, password `postgres`, database `breakdown`.
- **SierraDB** on `localhost:9090` (RESP3) — pinned to `tqwewe/sierradb:0.3.1`.

### Apply migrations and run the API (full boot sequence)
1. Start both tiers (above).
2. Apply Postgres projection migrations + boot the API, pointing at both tiers:

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 \
cargo run -p api
```

`main.rs` runs `sqlx::migrate!("../infra/migrations")` at boot, opens a RESP3
connection to SierraDB, builds a live `CommandService` (write path), and spawns
the four `PostgresProcessor` projectors that subscribe to SierraDB and update
the Postgres projections. Tests that use `infra::testing::spawn_postgres()`
apply the same migration set automatically.

### Environment variables used by the API binary
- `DATABASE_URL` – Postgres connection string (default: `postgres://postgres:postgres@localhost:5432/breakdown`)
- `SIERRADB_URL` – SierraDB RESP3 connection string (default: `redis://127.0.0.1:9090/?protocol=resp3`). SierraDB speaks RESP3 only — keep `?protocol=resp3` (ADR-016).
- `BIND_ADDR` – HTTP bind address (default: `0.0.0.0:3000`)
- OpenAPI/Swagger UI is served at `http://localhost:3000/swagger-ui`

#### Photo storage (Garage / S3)
- `S3_ENDPOINT` – Garage S3 API endpoint (e.g. `http://garage:3900`)
- `S3_ACCESS_KEY` – Garage access key
- `S3_SECRET_KEY` – Garage secret key
- `S3_BUCKET` – S3 bucket name (default: `costume-photos`)
- `PHOTO_MAX_SIZE_MB` – maximum upload size in MB (default: `20`)
- `PHOTO_GC_ENABLED` – enable periodic orphan GC (default: `true`)
- `PHOTO_GC_INTERVAL_SECS` – GC sweep interval (default: `3600`)
- `PHOTO_GC_MAX_AGE_SECS` – only sweep orphans older than this (default: `86400`)
- `PHOTO_GC_BATCH_SIZE` – max orphans per run (default: `1000`)
- `PHOTO_GC_DRY_RUN` – log-only mode (default: `false`; set `true` for first rollout)

> **Boot sequence**: Garage must be up and provisioned (bucket + access key) before the API
> starts. See `docker-compose.dev.yml` for the internal-only Garage service. During first
> rollout set `PHOTO_GC_DRY_RUN=true` to observe orphan detection logs before enabling deletion.

#### OIDC / authorization (added by `add-oidc-auth-and-membership`)
- `OIDC_ISS` – IdP issuer URL (expected `iss` claim). Production-only; when
  absent **and** `DEV_AUTH_SUB` is set, the API runs in **dev auth mode** (see below).
- `OIDC_AUDIENCE` – resource indicator / expected `aud` claim for this API.
- `OIDC_JWKS_URL` – IdP JWKS document URL used to fetch RSA signing keys.
- `AUTHZ_ENFORCE` – `false`/`0` disables authorization enforcement
  (denials are logged, requests allowed — staged rollout / log-only); any other value
  (or unset) enforces, returning `403` for non-members. **Dev auth mode defaults
  enforcement OFF** so local development works without seeded membership.
- `DEV_AUTH_SUB` – when set (and `OIDC_ISS` unset), auth runs in dev mode:
  tokens are NOT verified and a fixed dummy `CurrentUser` (`sub = DEV_AUTH_SUB`)
  is injected. **Never set in production.** `DEV_AUTH_EMAIL` optionally supplies the
  dummy user's email.

> Dev auth mode is an explicit, env-gated bypass used only for local development
> and tests. `main.rs` only ever enters it when `OIDC_ISS` is absent and
> `DEV_AUTH_SUB` is present; production deployments set `OIDC_ISS` and therefore
> can never reach dev mode.

### Optional: Local IdP for OIDC Development

For auth-related work, you can boot a self-hosted Logto IdP using the IdP overlay. **This is dev-only**; production IdP runtime is governed by ADR-010 (Logto Cloud first, Zitadel migration later) and is not provided by this dev overlay.

```bash
# Boot the full stack with IdP
docker compose -f docker-compose.dev.yml -f docker-compose.idp.yml up -d

# Seed the OIDC application (generates .env.idp)
./scripts/seed-logto-dev.sh
```

This starts:
- **Logto OIDC** on `http://localhost:3301` — issuer URL for OIDC flows
- **Logto Admin UI** on `http://localhost:3302` — admin console and Admin API
- **logto-db** — dedicated Postgres for Logto state (isolated from breakdown read-model)

After seeding, the `.env.idp` file contains:
- `OIDC_ISS` — Issuer URL (e.g., `http://localhost:3301`)
- `OIDC_AUDIENCE` — Resource indicator for your API (e.g., `https://api.breakdown.local`)
- `OIDC_JWKS_URL` — JWKS endpoint for key discovery (e.g., `http://localhost:3301/.well-known/jwks`)

**Dev ≠ Prod IdP:** The backend validates standard OIDC JWTs and is IdP-agnostic. Dev uses self-hosted Logto for convenience; production may use Logto Cloud or Zitadel per ADR-010. No code changes are needed to switch IdPs — only the environment variables change.

**Frontend note:** Local frontend dev should configure the OIDC client to point to `http://localhost:3301` for the issuer.

## 7. Licensing & Headers
- **License:** AGPL-3.0 (see `LICENSE`)
- **SPDX Headers:** Run `./scripts/add-spdx-headers.sh [dir]` to add headers to `.rs`, `.typ`, `.sh` files
- **Format:** `// SPDX-License-Identifier: AGPL-3.0` + `// Copyright (C) 2024 Breakdown RS Contributors`

*When in doubt about the domain logic or workflow, ask questions before generating code.*