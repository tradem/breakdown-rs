<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gpt-5.6-luna (opencode-go) -->

# Agent Guidelines for breakdown-rs

You are the primary coding agent for `breakdown-rs` – a collaborative costume scheduling app. Your goal is to implement features securely, test-driven, and with clean architecture.

> **Layout of this file / on-demand instructions:** It contains only the **core rules** (always
> loaded). Long-form rationale and reference material live as glob-scoped rule files:
> backend-scoped rules in `backend/.github/instructions/`, repo-level rules (workflows, root
> scripts) in the monorepo-root `../.github/instructions/` — see the §6 register. pi-rules
> resolves the project root **per read file** (first `Cargo.toml` / `.git` marker walking up), so
> backend rules fire for `backend/**` reads regardless of where pi was launched. `/rules` lists
> only always-on rules — glob rules appear attached to the file reads they match. Section
> numbers (§1–§5, §7) and titles are **stable**: source-code comments and CI workflows
> reference them (`AGENTS.md §1`, `§3`, `§4`).

## 1. Architecture & Core Patterns
- **Hexagonal Architecture / Poor Man's DI:** No DI frameworks. External dependencies are defined as traits (ports) in `core` and manually injected in the composition root (`main.rs`).
- **CQRS & Event Sourcing:** All state changes occur via **Commands** sent to **Aggregates** (which validate and emit **Events**; state is rebuilt by replay). **Queries** read from flat PostgreSQL **Projections**; event handlers update projections asynchronously. Never query aggregates directly for views.
- **CQRS Boundary (hard rule):** Write-side code (Command adapters, Sagas, Aggregates) must **never** query a read-model projection (`*Repository::find_by_id`) to resolve audit/derived context (e.g. `series_id`) — that context comes from **event data** or a **command field** populated at the API edge (the only legitimate read-model consumer). Exceptions only with `// ast-grep-ignore: cqrs-boundary` + justification (rule `backend/rules/cqrs-boundary.yml`, job `cqrs-boundary`). Audit metadata must never block command processing: resolve best-effort, `None`/default on projection misses. → Long form: `.github/instructions/architecture-hard-rules.instructions.md`
- **kameo_es (Actors):** Event-sourced aggregates are `kameo::Actor`s implementing `kameo_es::Entity`; commands act as `kameo_es::Command` (see §5).

## 2. Workspace Structure
- **`crates/core`:** Pure domain logic — Commands, Events, Aggregates, Read-Model DTOs, Port Traits. **No dependencies** on `sqlx`, `axum`, or infrastructure.
- **`crates/infra`:** Infrastructure — EventStore integrations, Projectors, `sqlx` queries.
- **`crates/api`:** Axum web server — HTTP → Core Commands (Write) / Infrastructure Queries (Read).

**Domain map (production hierarchy, ADR: introduce-season-block-episode-hierarchy):**
`Series` (opaque `SeriesId` seam, no aggregate yet) → `Season` → `Block` → `Episode` → `Scene`; `Character` scoped to a Season, `Costume` bound to a Character. Core modules: `season`, `block`, `episode`, `scene`, `scene_shoot`, `shooting_day`, `character`, `costume`, `costume_category`, `shared`. The `calculation` context was removed — do not reintroduce it.
Aggregate details and invariants (`shooting_day`/`wrapped_at`, `scene_shoot` lifecycle & pair-uniqueness, `costume_category` seeding saga, `photo` bounded context with sagas) → long form: `.github/instructions/domain-model.instructions.md` and `.github/instructions/photo-context.instructions.md`

## 3. Workflow & Best Practices
- **EventStorming Mapping:** **Event** (past tense, e.g. `SceneCreated`) → `enum` in `core`; **Command** (imperative, e.g. `CreateScene`) → `struct` in `core`; **Aggregate** (noun) → state `struct` in `core`.
- **Open-Spec / API First:** API contract is authored **code-first** via `utoipa` derives (ADR-006); the checked-in **`backend/openapi.yaml`** is the review artifact and MUST be kept in sync (`UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`); CI fails on drift. Map exact types using `serde`.
- **ID Generation:** Strictly **UUIDv7** (`uuid::Uuid::now_v7()`) for all entities and events. No UUIDv4.
- **Security:** Never hardcode secrets. Your code must pass `gitleaks`. Authoritative threat model / authorization architecture: `docs/security/security-architecture.md` — keep it in sync when touching auth/authz code (issue #85).
- **No panics in production code (hard rule):** `unwrap()`/`expect()`/`panic!()`/`unreachable!()`/`todo!()` forbidden in production paths (adapters, sagas, projectors, handlers, `main.rs`). Use `?` with `DomainError`/`anyhow` or `match` with explicit fallback. Clippy `unwrap_used`/`expect_used`/`panic` are `deny`; `#[allow]` only for const-time construction from known-valid literals or test code, each with justification comment.
- **No string-interpolated SQL (hard rule):** SQL passed to `sqlx::query*/query_as*/query_scalar*` must be static `&str` literals; dynamic values via `.bind()`; identifiers only from a hardcoded allowlist, never request input. Enforced by job `no-string-interpolation-sql`. Safe patterns: `docs/security/README.md`.
- **Handler-internal auth gates (hard rule):** Handlers gated only by `Requirement::Authenticated` get no middleware membership enforcement — they MUST call the relevant `AuthorizationPolicy` method *inside the handler body* (403 on denial) and carry an `// AUTHZ-GATE:` comment. Reviewers `grep` for `AUTHZ-GATE`.
- **HTTP error surface (ADR-031):** Every HTTP failure is RFC 9457 `application/problem+json` from the single problem builder (`crates/api/src/problems`) over the `problem_codes!` registry (`crates/core/src/error_registry.rs`). New codes only as entries in that macro — never standalone `pub const ProblemCode` (job `problem-code-registry`, non-suppressible). Handlers return `Result<_, ApiError>` and use `?` — no per-handler status mapping. Clients branch on stable `code`, never `detail`. Extension fields per code (S0/S1/S2); S2 data (OIDC `sub`, e-mail) structurally banned; `detail` localized via Fluent (`crates/api/locales/<lang>/errors.ftl`), never `format!` in core. → `docs/errors/`
- **Reliability (issue #165):** Never discard fallible results (`let _ = <call>` → rule `discard-result`); classify transient OpenDAL errors → `ServiceUnavailable` (in-loop retry), permanent → `ValidationError`; ignore only not-found in delete paths; couple ordered config constants via a shared constant + `const _INVARIANT` assert; flush partial batches before `run()` returns `Ok(())`. → Long form: `.github/instructions/architecture-hard-rules.instructions.md`
- **Handoff-Prompt / Task-Spec Architecture Review (pre-implementation checklist):** Every handoff prompt or task spec MUST pass this review **before** dispatch to an agent; any "yes" means rewrite first (issues #147/#148):
  - [ ] Write-side queries a read-model projection? (CQRS violation — reject unless at the API edge.)
  - [ ] `unwrap`/`expect`/`panic` in hot paths (adapters, sagas, projectors, handlers)?
  - [ ] Test-only helpers called from production spawn paths?
  - [ ] Audit metadata (`series_id`) coupled to projector presence?
  - [ ] Fallible result discarded with `let _ = <call>`?
  - [ ] Test-only helper (`*_for_test`) without `#[cfg(feature = "test-support")]` gating?

## 4. Testing & Guardrails
- **Unit/Integration Tests:** Deterministic tests for domain logic in `core`. **Timing-safe:** never gate on wall-clock timing or sleep-with-jitter budgets — compute the worst case analytically.
- **Mutation Testing:** CI-only — **do NOT run locally** (saturates CPU/memory for hours; local feedback via `cargo llvm-cov` / `cargo tarpaulin`). Config lives in `.cargo/mutants.toml` (a top-level `.mutants.toml` is silently ignored). `cargo mutants --in-diff` for changed code only.
- **Architecture Tests:** `rust_arkitect` + `cargo-deny` (ADR-017). Run `cargo test -p architecture_tests` and `cargo deny check bans` — core must not depend on infra/api.
- **Mechanical Guardrails (CI):** `architecture-checks.yml` + `backend/rules/*.yml` (ast-grep) enforce: CQRS boundary (`cqrs-boundary`), no-string-interpolation-SQL, test-shim leak (`test-shim-leak`), error hygiene (`discard-result`, `test-helper-gate`), problem-code registry (non-suppressible), UUIDv7-only, reqwest TLS/auth security rules (Layer 9, ADR-024: rustls + pinned CAs). Suppression only via `// ast-grep-ignore: <rule-id>` with a justification comment. `backend/git-hooks/pre-commit` mirrors these on staged files; CI is authoritative. → Job/rule detail: `.github/instructions/ci-hardening.instructions.md`
- **Integration Tests:** Black-box E2E in `crates/integration-tests` (tiers 1–4, testcontainers, ADR-016). The crate consumes only the `pub` API of `core`/`infra`. → Tiers, local execution, troubleshooting, gotchas: `.github/instructions/integration-tests.instructions.md`
- **CI hardening (hard rule):** SHA-pin third-party actions (40-char SHA + `# vX` comment); never interpolate `${{ github.event.* }}` into `run:` — pass via `env:`. → Workflow detail: `../.github/instructions/workflow-hardening.instructions.md`

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

## 6. Reference Register (on-demand instructions)
Detailed documentation lives as glob-scoped rule files (Markdown with YAML frontmatter,
frontmatter aliases `globs`/`paths`/`applyTo`), loaded by `pi-rules` when a file is read that
matches the rule's globs; `read`/`edit`/`write` are the tracked tools. Bodies are capped at
12k chars per rule, 40k per tool result. `/rules` lists only always-on rules — glob rules
appear attached to the file reads they match. **Placement follows pi-rules' per-target project
root:** the first marker (`Cargo.toml`, `.git`, …) walking up from the read file decides which
level's instructions fire: `backend/**` files discover `backend/.github/instructions/`,
repo-level files (workflows, root scripts) discover the root `.github/instructions/`.
Keep the split discipline when moving or adding rules: **normative stays in this file,
descriptive goes to the instruction that scopes it** — backend-relative globs for files under
`backend/.github/instructions/`, repo-relative for the root.

| File | Scope (repo-root-relative globs) | Content |
|---|---|---|
| `backend/.github/instructions/architecture-hard-rules.instructions.md` | `backend/crates/**/*.rs` | Hard-rules long form (CQRS boundary, no panics, SQL, AUTHZ-GATE, ADR-031, reliability) |
| `backend/.github/instructions/domain-model.instructions.md` | `backend/crates/{core,infra,api}/src/**` | Domain model: hierarchy, aggregates, invariants, seeding saga |
| `backend/.github/instructions/photo-context.instructions.md` | `backend/crates/*/src/photo/**`, backend compose/scripts | Photo bounded context, sagas, Garage/S3 env, GC |
| `backend/.github/instructions/ai-import.instructions.md` | `backend/crates/*/src/ai/**`, `backend/config/default_ai_prompts.toml` | AI import: env, concurrency permits, payload storage/GC, restart recovery |
| `backend/.github/instructions/integration-tests.instructions.md` | `backend/crates/integration-tests/**` | Tiers, local execution, troubleshooting, gotchas, CI prerequisites |
| `backend/.github/instructions/local-dev-runtime.instructions.md` | backend compose/scripts/`.env*`/dev-certs | Dev runtime, boot sequence, env vars, OIDC/dev-auth, IdP overlay |
| `backend/.github/instructions/ci-hardening.instructions.md` | `backend/rules{,-tests}/**`, `backend/scripts/**` | Guardrail ast-grep rule + job detail |
| `.github/instructions/workflow-hardening.instructions.md` | `.github/workflows/**`, `.github/dependabot.yml` | SHA-pinning, Dependabot, script-injection hygiene |
| `.github/instructions/local-dev-root.instructions.md` | root `scripts/**`, root `.env*` | Pointer to the local-dev-runtime documentation for root dev assets |

Further references: `docs/security/security-architecture.md` (threat model),
`docs/errors/` (problem codes, ADR-031), `backend/openapi.yaml` (API contract), ADRs.

## 7. Licensing & Headers
- **License:** AGPL-3.0 (see `LICENSE`)
- **SPDX Headers:** Run `./scripts/add-spdx-headers.sh [dir]` to add headers to `.rs`, `.typ`, `.sh` files
- **Format:** `// SPDX-License-Identifier: AGPL-3.0` + `// Copyright (C) 2024 Breakdown RS Contributors`
- **Co-authors:** Add one `// Co-authored-by: <model> (<provider|tool>)` line per contributor, directly under the Copyright line. Use a **separate line per author** (not a comma-separated list) — this matches the git `Co-authored-by` trailer convention, is greppable (`grep "Co-authored-by: <model>"`), and keeps diff-based attribution stable. Values come from `$PI_MODEL` and `$PI_PROVIDER` (e.g. `// Co-authored-by: glm-5.2 (neuralwatt)`). Append, don't duplicate — if an author line already exists, don't re-add it.

*When in doubt about the domain logic or workflow, ask questions before generating code.*
