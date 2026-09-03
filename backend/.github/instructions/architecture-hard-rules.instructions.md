---
description: Long form of the architectural hard rules (CQRS boundary, no panics, SQL, authz, error surface, reliability) - loaded when reading backend Rust files.
applyTo:
  - "crates/**/*.rs"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

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
