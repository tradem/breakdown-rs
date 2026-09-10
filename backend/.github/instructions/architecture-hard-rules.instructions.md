---
description: Long form of the architectural hard rules (CQRS boundary, no panics, SQL, authz, error surface, reliability) - loaded when reading backend Rust files.
applyTo:
  - "crates/**/*.rs"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Hard-Rules — Langfassung und Begründung

Kompakte Einzeiler-Fassung und Enforcement-Zeiger stehen in `AGENTS.md` §1–§3;
dieser Text ist die vollständige Begründung mit Beispielen.

## CQRS-Boundary (hard rule)

**CQRS Boundary (hard rule):** Write-side code — Command adapters
(`*CommandsImpl`), Sagas, Aggregates — must **never** query a read-model
projection (`*Repository::find_by_id`) to resolve audit/derived context such
as `series_id`. Such context must come from the **event data itself**
(e.g. `SeasonCreated.series_id`) or from a **command field** populated at the
API edge. The API layer (handlers) is the *only* legitimate consumer of
read-model queries and may enrich commands before dispatch. Violating this
creates a hidden coupling to projector presence and projection lag that
breaks tests and, in production, risks silent audit gaps when a parent
projector lags. The `cqrs-boundary` job in `architecture-checks.yml`
enforces this mechanically for `crates/infra/src/event_store/`,
`crates/infra/src/sagas/`, and `crates/infra/src/photo/sagas/` via the
AST-based ast-grep rule `backend/rules/cqrs-boundary.yml` (issue #148).
A non-audit read-model lookup (e.g. the `ExpectedVersion` concurrency guard
in the photo deletion sagas) is permitted only with an explicit
`// ast-grep-ignore: cqrs-boundary` suppression on the call line, carrying
a justification comment above it.

**Audit metadata must never block command processing:** resolve it
best-effort, returning `None`/default on projection misses.

## Cross-aggregate invariant doctrine (issues #404, #37)

Per-stream optimistic concurrency of the event store **cannot** enforce global
(cross-aggregate) invariants such as uniqueness — that is inherent to ES+CQRS,
not a defect. The failure mode observed in #404 arises one step later: an
invariant was silently delegated to a projection unique constraint **without
designing its failure path**. Consequence: the write path accepts the violating
command with **2xx** (the event sits in SierraDB and permanently violates the
invariant), the event becomes unprocessable for the projector (permanent 23505),
and — before the #37-minimal fix — panics the projector worker/coordinator.
From the user's perspective this is silent data loss: the write succeeded, the
read model (dispo/soll-ist reports) never updates.

**Doctrine — every cross-aggregate invariant must specify three things:**

1. **Authoritative enforcement point.** A projection unique constraint
   (`uq_projection_*`) is a legitimate backstop and remains the authority
   against races. It is the *last* line of defense, never the *only* one.
2. **Client-facing 409 via API-edge pre-check.** The handler (the only
   legitimate read-model consumer per the CQRS boundary) checks the invariant
   before dispatching the command and returns a clean 409 with a registered
   problem code (ADR-031: entry in `problem_codes!`, Fluent text in
   `crates/api/locales/<lang>/errors.ftl`). Pre-checks are advisory; the
   constraint remains authoritative against races.
3. **Projector failure behavior.** A permanent constraint violation reaching a
   projector must never panic-kill the worker/coordinator. Target state
   (#37, Launch-Blocker there): the event is classified and skipped into a
   durable poison/dead-letter table with a health signal. **State shipped
   with #404 (minimal path): log-only skip — no durable poison tracking and
   no health signal yet;** the only trace of a skipped violation is the
   `tracing::warn!` line (`constraint = ...`, issue #404 marker). Anything
   asserting durable tracking refers to the #37 target, not the shipped
   behavior.

**Known instances (see #404 — closed by the #404 fix; pre-checks are advisory, the constraints stay authoritative):**

| Invariant | Projection constraint | Status |
|---|---|---|
| SceneShoot pair-uniqueness `(scene_id, shooting_day_id)` | `uq_projection_scene_shoot_pair` | closed: API-edge 409 (`scene-shoot.pair-already-exists`) + projector savepoint-skip |
| Season numbering `(series_id, number)` | `idx_projection_season_series_number` | closed: API-edge 409 (`season.number-already-exists`) + projector savepoint-skip |
| Block numbering `(series_id, number)` | `idx_projection_block_series_number` | closed: API-edge 409 (`block.number-already-exists`) + projector savepoint-skip (same class, fixed with #404) |
| Episode numbering `(series_id, number)` | `idx_projection_episode_series_number` | closed: API-edge 409 (`episode.number-already-exists`) + projector savepoint-skip (same class, fixed with #404) |

The projector skip lives in `crates/infra/src/projectors/invariant_skip.rs`: a 23505 on
exactly these constraints is a *permanent* violation, isolated in a SAVEPOINT (a failed
statement aborts the batch transaction), logged with `tracing::warn!`, and the event is
acknowledged — the projection keeps the authoritative row. **The #404 path provides no
durable poison/dead-letter record and no health signal — that is the #37 scope.**

**Replay of pre-#404 gift events (no manual checkpoint reset needed):** a pre-#404
coordinator died *at* the poison event, so its `sierradb_event_checkpoints` checkpoint
never advanced past it. After deploying this fix, a plain **restart** of the API makes the
projector re-process the stuck event, skip it (warn log), and advance the checkpoint.
Verify catch-up by (a) the warn backlog draining — each skipped event logs exactly once
per projector pass, so repeated identical warns across restarts mean the checkpoint is
still stuck — and (b) the projection containing the authoritative row (first event) for
the violating pair/number. Later events of a skipped duplicate stream are harmless by
construction: their handlers are `UPDATE ... WHERE id = $1` statements that affect 0 rows
and cannot create a projection row (regression test tracked in the #404 follow-up).

**Gift-record cleanup (upgrade path, #404):** deployments that ran a pre-#404 build may
hold invariant-violating events. **Dev:** volume reset (`docker compose -f
docker-compose.dev.yml down -v`) is sufficient. **Prod/upgrade:** after deploying this fix
a plain API restart replays the stuck checkpoint and the projectors skip the violating
events (warn log per skipped event — grep for "skipped invariant-violating event"; see
`docs/operations/runbooks.md` → "Replaying pre-#404 invariant-violating events" for the
procedure and the catch-up checks). The projection keeps the first (authoritative) row;
the duplicate stream sits in the event store unreferenced by the projection and is inert
for reports. A physical cleanup of duplicate event streams is optional and belongs with
the #37 DLQ design (do not ad-hoc delete events).

**Known non-issues (do not "fix"):** `projection_audit.event_key` dedup
(`ON CONFLICT (event_key) DO NOTHING` ✓), `dedup_key` job tables (report_ops /
ai_import — job queues are a Postgres strength, not an ES deficiency),
projector version guards (`WHERE version < $N` — standard at-least-once
idempotency).

**ES-native alternative (design follow-up, ADR-worthy — do not adopt ad hoc):**
reservation streams. The command first writes a reservation event to a
synthetic key stream (`scene_shoot_pair:{hash(scene_id, day_id)}`,
`season_number:{series_id}:{n}`) with `ExpectedVersion::Empty`; a competing
command fails the version condition **in the event store** and maps to a clean
409 *before* touching the aggregate stream. Uses only per-stream concurrency
(SierraDB-capable). Trade-offs: reservation release/compensation on
delete/archive, one extra stream per entity.

## No panics in production code (hard rule)

Panics are the "safe" equivalent of `unsafe` for crashing production: they
bypass structured error handling (`?` / `DomainError`/`anyhow`), produce no
tracing span, and (in spawned tasks like projectors and sagas) silently kill
the worker — defeating the entire tracing/audit effort.
**`unwrap()` / `expect()` / `panic!()` / `unreachable!()` / `todo!()` are
forbidden** in production code paths (adapters, sagas, projectors, handlers,
`main.rs`). Use `?` with `DomainError`/`anyhow`, or `match` with an explicit
fallback. The workspace clippy lints `clippy::unwrap_used`,
`clippy::expect_used`, `clippy::panic` are `deny` (CI-enforced via
`-D warnings`). `#[allow]` is only acceptable for (a) const-time
construction from a known-valid literal (e.g. `LexicalSortKey::from_static`)
or (b) test code — both must carry a justification comment
(rule `backend/rules/allow-panic-lint-justification.yml`).

## No string-interpolated SQL (hard rule)

Every SQL statement passed to `sqlx::query(...)`, `sqlx::query_as(...)`, or
`sqlx::query_scalar(...)` must be a static `&str` literal (or `r#"..."#`).
All dynamic values go through `.bind()`. Identifiers (column/table names,
`ORDER BY` column) must come from a hardcoded allowlist, **never** from
request input — Postgres cannot bind identifiers. The CI job
`no-string-interpolation-sql` in `architecture-checks.yml` enforces this
mechanically. See `docs/security/README.md` for detailed safe patterns.

## Authorization — handler-internal auth gates (photo handlers)

Handlers gated only by `Requirement::Authenticated` (e.g. photo endpoints
under `/costumes/*/photos*`) do **not** receive block-scoped membership
enforcement from the middleware. Every such handler MUST call the relevant
`AuthorizationPolicy` method (e.g. `has_active_costume_role_in_season`)
*inside the handler body* and return `403` on denial.

All three photo handlers (`upload_costume_photo`, `get_costume_photo_bytes`,
`delete_costume_photo`) are annotated with `// AUTHZ-GATE:` comments marking
their handler-internal authorization check. Any new handler under an
`Authenticated`-only route that performs a privileged action MUST follow the
same pattern — add a `// AUTHZ-GATE:` comment and call the appropriate policy
method. Reviewers `grep` for `AUTHZ-GATE` to verify no handler has missed
its gate.

Continuity photo handlers under
`/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos`
follow the same pattern (season-scoped membership via the
shooting_day → episode → block → season chain).

## HTTP error surface (ADR-031)

Every HTTP failure is an RFC 9457 `application/problem+json` document built
by the single problem builder (`crates/api/src/problems`) from the code
registry (`crates/core/src/error_registry.rs`). The registry is a
single-source `problem_codes!` macro: each entry expands to its `pub const`
*and* its `PROBLEM_CODES` array slot from one list, so a code that is not
registered cannot exist — a standalone `pub const ...: ProblemCode` outside
the invocation is rejected by the `problem-code-registry` CI job, and a
compile-time assertion keeps the registry count in sync (issue #232). New
codes MUST be added as entries in that invocation, never as a standalone
`pub const`. Handlers return `Result<_, ApiError>` and propagate with `?` —
there is no per-handler HTTP status mapping and no `map_err`-to-response
conversion. Clients branch on the stable `code` (`{context}.{reason}`),
never on `detail` text. Extension fields are whitelisted per code and
classified S0/S1/S2: S1 fields are emitted only after the handler's
`AUTHZ-GATE` has run; S2 data (OIDC `sub`, e-mail) is structurally banned.
`detail` is localized server-side via Fluent
(`crates/api/locales/<lang>/errors.ftl`, `de` default) — never build
client-facing error strings with `format!` in core. Golden snapshots
(`crates/api/tests/problem_golden.rs`), the bundle-coverage lint
(`crates/api/tests/bundle_coverage.rs`), and the `s2-extension-ban`
ast-grep rule enforce the surface mechanically. See `docs/errors/`.

## Reliability & error handling (issue #165 review lessons)

- **Never discard fallible results with `let _ = <call>`** in production
  code: a swallowed error defeats `retry_transient` and ack-after-success
  redelivery (a delete that never ran is acknowledged and lost). Propagate
  (`?` / `.map_err`), handle explicitly (`if let Err(e) = ... { warn!(...) }`),
  or suppress with `// ast-grep-ignore: discard-result` + justification. The
  `discard-result` rule in `architecture-checks.yml` enforces this.
- **Classify transient storage errors:** map OpenDAL errors with
  `is_temporary() == true` to `DomainError::ServiceUnavailable` so the saga
  `retry_transient` loop retries them in-loop; map permanent errors to
  `ValidationError` (reach ack-after-success redelivery). Ignore only
  not-found errors in delete paths.
- **Couple config invariants in code:** when two constants must stay ordered
  (e.g. batch size vs. subscription window), derive both from one shared
  named constant and add a compile-time assertion
  (`const _INVARIANT: () = assert!(...)`).
- **Flush partial batches on graceful shutdown:** any ack tracker must
  flush its final partial batch before `run()` returns `Ok(())`.
