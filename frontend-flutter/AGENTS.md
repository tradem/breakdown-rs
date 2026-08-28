<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Agent Guidelines for the Flutter App (`frontend-flutter/`)

> **This is `design.md` for the `add-flutter-app-foundation` OpenSpec change.
> During the foundation apply step (Task 1.2 of `tasks.md`) it is copied
> verbatim to `frontend-flutter/AGENTS.md` and the two are kept
> byte-identical thereafter.** The OpenSpec artifact is the source of truth;
> the on-disk `AGENTS.md` is the convenience copy consumed by coding agents
> working inside `frontend-flutter/`.

You are the primary coding agent for the Flutter client of `breakdown-rs` —
a collaborative costume scheduling app whose Rust backend is CQRS /
event-sourced. Android is the first target; macOS is explicitly later. Your
goal is to implement features securely, test-driven, and with clean
architecture, mirroring the backend `AGENTS.md` in spirit and adapting its
hard rules to the Flutter/Dart ecosystem where a 1:1 translation exists,
and documenting the gaps honestly where it does not.

The backend `AGENTS.md` is the authoritative reference for the server side;
this document is authoritative for the client side. Where the two disagree on
a server-owned concern (API shape, error surface, auth), the backend wins.

---

## 1. Architecture & Core Patterns

- **Layered + CQRS-aware client:** The app is split into `core/` (pure,
  framework-free: `Result`/`Either`, `ProblemError`, value objects),
  `data/` (repositories wrapping the generated OpenAPI client + the Drift
  cache), `domain/` (use-case orchestration, projector-lag reconciliation),
  and `features/` (one folder per aggregate boundary, one screen per
  read-model query). Widgets are presentation-only adapters — they render
  and dispatch, never branch on domain semantics.
- **Riverpod as the sole composition mechanism (Decision D3):**
  `flutter_riverpod` + `riverpod_generator` is the **only** state-management
  and dependency-injection mechanism. Providers are declared via codegen
  (`@riverpod`); widgets consume via `ref.watch` / `ref.read`. No competing
  container (Bloc, GetIt, MobX, scoped `InheritedWidget` graphs) is
  introduced.
  - This is a **deliberate departure** from the backend's "no DI framework"
    ethos: Riverpod is compile-safe and its `override` system is honest DI
    (not a hidden service locator), which is accepted as the cost of
    widget-test velocity. A hidden `GetIt.I<…>()` locator in `build()` is
    the direct analog of the backend's forbidden audit-metadata coupling —
    a hidden dependency you cannot see at the call site — and is rejected
    for the same reason.
- **CQRS on the client (Decision D2):**
  - **Write side:** Commands are `POST` to resource/collection routes
    (`POST /seasons`, `POST /costumes/{id}/assign`, …). The client treats
    the HTTP response as command acknowledgement (immediate) and reconciles
    the eventual projection update with an optimistic state update +
    bounded-retry refetch (see §4). The client is **resource-REST**, not a
    stylized `POST /commands/{aggregate}/{action}` command bus — this
    corrects the sketch in ADR-007 §"CQRS-Aware API Design" against the
    actual checked-in `backend/openapi.yaml`.
  - **Read side:** Screens read flattened projection DTOs via `GET` routes.
    The client never queries aggregates directly (there is no aggregate API
    to query) and never reconstructs aggregate state client-side.
  - **CQRS boundary on the client (mirror of the backend hard rule):** The
    client must never derive audit/derived context (`series_id`, etc.) from
    a *different* read-model projection call to "fill in" a command. Such
    context comes from the command's own payload (populated at the API edge
    by the backend handler) or from the read DTO the user is acting on —
    never from a second projection lookup. The same hidden-coupling /
    projection-lag risk the backend rule exists to prevent applies here.
- **EventStorming mapping (ported):** Event → Command → Aggregate still
  applies as a *reading* tool for the client, but the client's生成 is the
  *command*, and its consumption is the *read DTO*. A "Create Season"
  button yields a `CreateSeasonCommand` payload; the resulting
  `SeasonCreated` event is something the client only observes indirectly
  via the projection refresh.
- **kameo_es (no client analog):** The actor/event-sourcing machinery is
  server-owned. The client models async state with Riverpod's `AsyncValue`
  (`loading` / `data` / `error`); projector-lag windows are explicit
  `AsyncValue` transitions, not hidden. See §4.

## 2. Workspace Structure

- **`frontend-flutter/`** sits at the monorepo root, sibling to `backend/`
  and `frontend-web/`. It is created by this change's follow-up scaffold
  task; until then, only `AGENTS.md` (a copy of this `design.md`) and the
  OpenSpec artifacts exist.
- **`lib/` tree (target layout):**
  ```
  frontend-flutter/
  ├── AGENTS.md                 # copy of this design.md
  ├── pubspec.yaml
  ├── analysis_options.yaml     # `breakdown_lints` analyzer-plugin rules (analysis_server_plugin, see §5)
  ├── lib/
  │   ├── main.dart             # composition root: ProviderScope, flavor wiring
  │   ├── app.dart              # MaterialApp.router root
  │   ├── core/                 # Result/Either, ProblemError, value objects
  │   ├── auth/                 # OIDC client, secure token store, currentMembershipProvider
  │   ├── api/                  # ← generated/ (breakdown_api) — rebuild-only
  │   ├── data/                 # repositories: wrap API client + Drift cache
  │   ├── domain/               # use-cases, projector-lag reconciliation
  │   ├── features/             # one folder per aggregate boundary
  │   │   ├── seasons/  blocks/  episodes/  scenes/
  │   │   ├── shooting_days/  scene_shoots/   (Soll/Ist reports)
  │   │   ├── costumes/  characters/  photos/ (capture/upload, continuity)
  │   │   └── costume_categories/
  │   ├── design/               # theme tokens, Material 3 components
  │   └── routing/
  ├── test/                     # unit + widget tests
  ├── integration_test/         # on-device E2E (flutter integration_test)
  ├── features-spec/            # Gherkin .feature files (see §6)
  └── .pi/skills/               # ported pi-code skills (see §9)
  ```
- **Generated vs hand-written (hard rule):** `lib/api/generated/` is
  rebuild-only. Hand-edits are forbidden; the folder is regenerated from
  `backend/openapi.yaml` (see §3). The same rule applies to Drift's
  `.g.dart` files, Riverpod's `.g.dart`, and freezed/json_serializable
  outputs: regenerate, never edit.

### Production hierarchy (mirrors backend)
The client models the same four-level hierarchy as the backend:
`Series` (opaque id) → `Season` → `Block` → `Episode` → `Scene`, with
`SceneShoot` per `ShootingDay` and `Character`/`Costume` scoped to a
`Season`. The `features/` tree **is** the navigation tree of the app: one
feature folder per aggregate boundary, one screen per read-model query.
Costume categories are season-scoped; continuity photos bind to scene
shoots; the photo bounded context's `binding` discriminator
(`Costume {| Continuity}`) is surfaced in the photos feature.

## 3. OpenAPI Contract & Drift Discipline

- **Code-first, drift-checked (Decision D1, D8):** The checked-in
  `backend/openapi.yaml` is the single source of truth for the API surface.
  The typed Dart client is generated into `lib/api/generated/` (package
  `breakdown_api`) via `openapi-generator-cli` (or `dart pub run
  build_runner build`). This mirrors the backend's ADR-006 code-first +
  `UPDATE_OPENAPI=1 openapi_drift` discipline.
- **Drift check in CI:** A PR that changes `backend/openapi.yaml` must
  regenerate the Dart client and commit the diff. CI regenerates into a
  throwaway, diffs against the committed tree, and fails on difference with
  a regenerate instruction. A PR that hand-edits `lib/api/generated/`
  fails the same check.
- **Never manually type API responses.** Always consume the generated types.
  The downstream of every API call is a generated DTO; mappers to domain
  entities live in `data/` and are unit-tested in isolation.

## 4. CQRS on the Client — Optimistic Updates & Projector-Lag Reconciliation

The backend's projector lag is a **first-class concern** the client must
model. A successful command `POST` ≠ a refreshed projection; the read model
updates asynchronously.

- **Optimistic update:** On a successful command acknowledgement, the
  provider inserts/updates the affected DTO in the local state
  optimistically (status: `processing`, etc.).
- **Reconciliation:** The provider kicks off a bounded-retry refetch of the
  affected read projection; on success it swaps the optimistic entry for
  the projected one. On timeout (bounded retries exhausted) the optimistic
  entry is retained with a stale indicator; the user can pull-to-refresh.
- **No silent discard:** A failed refetch is surfaced as `AsyncError`,
  never swallowed. This is the client-side analog of the backend's
  `discard-result` rule (see §5).
- **Stream where helpful:** For photos (variants processing → uploaded),
  `ref.read(photoRepositoryProvider).watch(id)` exposes a `Stream`; the
  provider terminates the watch when the variant reaches terminal state.

## 5. Security, Reliability & Hard Rules

These mirror the backend hard rules, translated to Dart/Flutter.

- **No `throw` in `data/` or `domain/` (analog of "no panics in prod"):**
  Fallible operations return `fpdart`'s `Result`/`Either` (or an equivalent
  `Result` type); errors are values. Widgets/providers translate `Err` into
  `AsyncError`. The analyzer's `discard-result`-equivalent rule
  (`breakdown_lints`) forbids `let _ = <fallible call>` (an un-awaited
  `Future`, a discarded fpdart `Result`/`Either`, a swallowed `Future`
  returned from a function). Enforced in IDE/LSP via `analysis_server_plugin`
  and in CI via the custom lint runner (issue #299).
  `Result`, a swallowed `Future` returned from a function). Either propagate
  (`?`-style via `match`), handle explicitly, or suppress with a
  justification comment (`// lint-ignore: discard-result` + reason above).
  This is the client-side twin of the backend `error-hygiene` job.
- **Client-side AUTHZ-GATE (Decision D6):** Every screen route is gated by
  auth state, and every call to a handler-internal-authz-gated backend
  endpoint (photo upload, photo byte fetch, photo delete, continuity-photo
  handlers) runs a **client-side role/membership check** via
  `currentMembershipProvider` *before* any network call. This mirrors the
  backend's `// AUTHZ-GATE:` handler-internal authorization pattern. A new
  handler call without a `// AUTHZ-GATE:` comment and a
  `currentMembershipProvider` check is rejected at review — `grep AUTHZ-GATE`
  verification applies. Client-side denial shows a localized 403 narrative
  and never issues the request.
- **OIDC token storage & cert pinning:** OIDC tokens live in
  `flutter_secure_storage` (never plaintext preferences). The HTTP client
  pins TLS roots matching the backend's pinned-CA stance (ADR-024),
  configured per-flavor via `--dart-define`. No
  `danger_accept_invalid_certs`-equivalent in any code path (the client
  uses a pinned-CA `HttpClient`/`dio` config). Dev trusts go into the dev
  flavor's pinned CA set, never into a disable-verification switch.
- **No hardcoded secrets:** No OIDC client secrets, API keys, or Garage
  credentials in the Flutter tree. Environment-specific values are supplied
  via `--dart-define` from CI secrets at build time. `gitleaks` scans
  `.dart`, `.yaml`, and `.arb` files (the backend's gitleaks config is
  extended to cover `frontend-flutter/`).
- **Problem Details JSON (RFC 9457):** Errors are consumed from the backend
  as `application/problem+json`. The widget branches on the stable `code`
  (`{context}.{reason}`), never on `detail` text (the backend localizes
  `detail` server-side via Fluent). The generated client surfaces `code`;
  the UI explains per `code` with localized copy of its own. Never build
  client-facing error strings with `format!` / string interpolation from
  backend `detail` — localize client-side, keyed on `code`.
- **HTTP error surface is server-owned:** The client does not invent HTTP
  status mappings; it consumes what the backend emits. A `409` is a `409`;
  the actionable branch is the `code` field.

## 6. Testing & Guardrails

### Test pyramid (4 tiers)

```
                         ┌───────────────────────────────┐
   Tier 4 (CI)           │  integration_test on device   │  a few: full screen flows
                         │   (emulator, _test.yaml)      │     against a real or mocked API
                         └───────────────────────────────┘
                       ┌───────────────────────────────────┐
   Tier 3 (CI)         │  Gherkin .feature (business-     │  hybrid: only designated
                       │  critical acceptance scenarios)  │  critical flows
                       └───────────────────────────────────┘
                     ┌─────────────────────────────────────┐
   Tier 2 (CI/local) │  widget tests (flutter_test) +       │  bulk: per-screen,
                     │  golden tests (matchesGoldenFile)    │  per-component
                     └─────────────────────────────────────┘
                   ┌───────────────────────────────────────┐
   Tier 1 (fast)   │  unit tests (pure domain/data logic)   │  no Flutter imports
                   └───────────────────────────────────────┘
```

- **Unit tests** cover pure logic in `core/` + `data/` + `domain/` (mappers,
  use-cases, `Result` pipelines, problem-code routing) with no Flutter
  imports.
- **Widget tests** are the bulk, per-screen and per-component, built on
  semantic finders (`find.text` / `byKey` / `byType`). Never `find.byType`
  alone for layout — pair with a `find.text` / golden so a tree-shuffled
  widget still fails the test.
- **Golden tests** (`matchesGoldenFile`) are required for any non-trivial
  widget (stateful, renders domain state). They catch logic/rendering drift
  a plain assertion misses.
- **Integration tests** (`integration_test`, on device/emulator) cover a few
  full screen-flow scenarios against a real or mocked API.
- **Err-branch assertions:** Every `Result`-returning repo/use-case test
  must assert both `Ok` and `Err` branches. An unmatched `Err` variant is a
  visible coverage hole. (Backend analog: explicit error-path tests.)

### Hybrid Gherkin (Decision Q2 → c)

Gherkin (`.feature` files under `features-spec/`) is used **only** for
business-critical acceptance scenarios, driven via `flutter_gherkin` on
device. Designated critical scopes (minimum):

- **Soll-Ist report** (scene_shoot reports: planned vs actual,
  moved/missing/skipped/reshot flags, `final` from `wrapped_at`).
- **Continuity photo capture** (end-to-end: AUTHZ-GATE → multipart upload →
  projector-lag reconciliation → thumb appears).
- **Costume assignment** (command → optimistic update → projection refresh;
  role denial on the costume stream).

A `.feature` for a non-critical screen is not forbidden, but reviewers
challenge it; the default is a widget test. Steps must run on device via
`flutter_gherkin` — a step whose body only calls a pure function belongs in
the unit-test tier, not in `features-spec/`.

### Mutation-testing gap (honest, Decision D5)

**No mutation-testing gate exists for Dart/Flutter.** There is no maintained
production-grade mutator comparable to Stryker or `cargo-mutants`; nothing
wired into CI would produce signal rather than noise. This is a known gap
versus the backend's `cargo-mutants` gate (CI-only). Compensation is
enforced via four compositional substitutes:

1. **`coverde` line+branch coverage threshold** on changed code (CI gate).
2. **Golden tests** for non-trivial widgets.
3. **Explicit Err-branch assertions** on every `Result`-returning repo/use-case.
4. **Semantic-finder widget tests** (never `find.byType` alone for layout).

If a maintained mutator emerges, it is scoped to `lib/domain/` + `lib/data/`
only (never widgets, never goldens — mutating rendered pixels produces
chaos, not signal). Mutation testing is **not** codified as a rule with no
tool behind it; cargo-culting the backend gate here would be dishonest.

### Deterministic tests

Never gate a test on wall-clock timing or sleep-with-jitter budgets (direct
port of the backend's "deterministic tests" rule). Compute the worst case
analytically against the test budget instead; use fake clocks / controllable
`StreamController`s for projector-lag reconciliation tests rather than real
`Future.delayed`.

### CI quality gates (Decision D8)

CI runs:
- `dart format --set-exit-if-changed`
- `flutter analyze` (standard analyzer/lint rules)
- `breakdown_lints` custom lint runner (`tool/breakdown_lints_runner`) — enforces
  the four custom rules (`discard_result`, `no_throw_in_data_domain`,
  `no_insecure_tls`, `no_hardcoded_secrets`) using the `analyzer` package
  directly, because the `analysis_server_plugin` package only loads in
  IDE/LSP mode and the batch CLI does not load plugins (issue #299)
- `flutter test --coverage` + `coverde` threshold gate on changed code
- OpenAPI-client drift check (§3)
- `gitleaks` on `.dart` / `.yaml` / `.arb`
- SHA-pinned GitHub Actions following the backend's CI-hardening rules (no
  moving `@v4` tags; Dependabot bumps SHAs)

## 7. Local Dev Runtime

- **Backend dev runtime:** The Flutter app points at the backend dev
  compose (Postgres + SierraDB + API on `:3000`, optional Logto IdP on
  `:3301`). Start the backend first:
  ```bash
  cd backend && docker compose -f docker-compose.dev.yml up -d
  DATABASE_URL=postgres://postgres:postgres@localhost:5432/breakdown \
  SIERRADB_URL=redis://127.0.0.1:9090/?protocol=resp3 \
  cargo run -p api
  ```
  The API serves Swagger UI at `http://localhost:3000/swagger-ui`.
- **Flutter run (dev flavor):**
  ```bash
  cd frontend-flutter
  flutter run --flavor dev --dart-define=API_BASE=http://localhost:3000 \
    --dart-define=OIDC_ISS=http://localhost:3301
  ```
- **Regenerating the Dart client:** (run from `frontend-flutter/`; the
  generator version comes from the committed
  `frontend-flutter/openapitools.json` — do not pass a different version on
  the CLI)
  ```bash
  npx @openapitools/openapi-generator-cli generate \
    -i ../backend/openapi.yaml \
    -g dart -o lib/api/generated \
    --additional-properties=pubName=breakdown_api
  ```
- **Flavors:** `dev` (localhost backend, optional Logto, dev-pinned CA set)
  and `prod` (deployed edge, Logto/Zitadel cloud, pinned prod CA,
  `REQUIRE_IN_TRANSIT_TLS`-grade posture). No other flavors without a
  change proposal.
- **Dev auth mode:** When the backend runs in dev auth mode
  (`DEV_AUTH_SUB` set, `OIDC_ISS` absent), the client treats the dummy user
  as authenticated; `currentMembershipProvider` returns a permissive
  membership for local development. **Never set `DEV_AUTH_SUB` in a prod
  build.**

## 8. Offline Scope (Decision Q1 → b)

- **Online-first with read-projection cache:** Commands are always
  dispatched over the network and never queued offline. A failed command
  returns `Err` to the provider; the widget surfaces a retry affordance. No
  local command persistence, no sync/conflict resolution, no offline
  audit-metadata reconstruction (which would violate the backend's
  CQRS-boundary hard rule if reconstructed client-side).
- **Drift cache:** Read projections are cached locally in **Drift**
  (type-safe, codegen-friendly SQLite) for fast boot, "last seen" state on
  cold start, and brief-connectivity-drop read-only survival. Drift tables
  mirror the read-projection DTOs (not the event-store schema). Cache
  invalidation is TTL + on-write-invalidate (a successful command that
  mutates a projection triggers a refetch of the affected read). The cache
  is a performance/offline-tolerance layer only — it never holds state the
  server does not also hold.
- **A projection DTO shape change** requires a Drift migration in the same
  PR, so the cache never silently drops a field.
- **Offline writes deferred to a later change:** A future change proposal
  may introduce an offline command queue with replay; this requires solving
  sync/conflict semantics and offline `series_id` resolution and is out of
  scope for the foundation.

## 9. Design System & Code Generation

- **Material 3 + theme tokens:** Reusable components live under
  `lib/design/`; theme tokens are the single source for colors, type, and
  spacing. No hardcoded colors/styles inline in widgets.
- **Codegen conventions:** `build_runner`, `freezed`, `json_serializable`,
  `riverpod_generator`, `drift_dev`, `openapi_generator`. Generated files
  (`.g.dart`, `.freezed.dart`, `lib/api/generated/`) are read-only —
  regenerate, don't edit.
- **`flutter/genui` (Decision Q4 → defer-ban):** Not adopted as a
  prescribed drafting workflow. The conventions here are opinionated enough
  that genui output is an 80%+ rewrite (StatefulWidget+setState rejected,
  http replaced by generated client, throw→Result, missing AUTHZ-GATE
  retrofit). A frontier coding assistant that has read these specs produces
  convention-conformant code in a single deterministic pass — strictly
  superior to genui-as-intermediate. Re-evaluation possible only with
  reliable Android-fleet on-device LLM availability + tooling constrained
  to emit Riverpod/OpenAPI/Result-conformant code. A PR that ships
  genui-generated widget code is challenged at review; recurring misuse
  upgrades this from SHOULD-NOT to MUST-NOT (hard ban).

## 10. Licensing & Headers

- **License:** AGPL-3.0 (same as the backend).
- **SPDX headers:** `// SPDX-License-Identifier: AGPL-3.0` +
  `// Copyright (C) 2024-2026 Breakdown RS Contributors` on every `.dart`,
  `.feature`, `.yaml` file. Run the backend's `./scripts/add-spdx-headers.sh`
  (extended to cover `frontend-flutter/`) to add headers.
- **Co-authors:** Same convention as backend — one
  `// Co-authored-by: <model> (<provider|tool>)` line per contributor
  (values from `$PI_MODEL` / `$PI_PROVIDER`), directly under the Copyright
  line. Separate line per author (not comma-separated); greppable; append,
  don't duplicate.

---

## Ported pi-code Skills (`frontend-flutter/.pi/skills/`)

Skills are ported from `flutter/agent-plugins` and `dart-lang/skills` where
applicable to the project's conventions, and live at
`frontend-flutter/.pi/skills/` (parallel to `backend/.pi/skills/`). Each
port carries an SPDX header and is regenerated if upstream changes
materially. Portable subset:

- **Lint/analysis guidance** → maps to `analysis_options.yaml` + the
  `breakdown_lints` analyzer-plugin package (built on `analysis_server_plugin`)
  for IDE/LSP enforcement, plus the `breakdown_lints_runner` custom lint runner
  for CI enforcement (issue #299); the skill wraps "apply these lints, explain
  the fix."
- **Testing recipes** → widget test scaffolding, golden setup,
  integration_test harness — portable as skills.
- **Codegen conventions** → freezed / json_serializable / riverpod_generator
  / build_runner workflows — portable.
- **Material 3 / ThemeData** patterns — portable as a design skill.

The skills-ported directory is created by a follow-up scaffold task, not by
this foundation change.

---

## Cross-references

- **Locked decisions (D1–D8)** and **resolved questions (Q1–Q4)** live in
  `openspec/changes/add-flutter-app-foundation/proposal.md`.
- **Delta specs** (`flutter-openapi-client`, `flutter-state-management`,
  `flutter-test-pyramid`, `flutter-client-authz`, `flutter-offline-scope`,
  `flutter-gherkin-hybrid`, `flutter-openspec-home`, `flutter-genui-policy`)
  are the machine-checkable encoding of the rules above; this document is
  the prose explanation a coding agent reads first.
- **OpenSpec canonical root** (Decision Q3 → c) is the monorepo-root
  `/openspec/`; the `migrate-openspec-to-monorepo-root` follow-up has landed,
  so this change's artifacts now live at
  `/openspec/changes/add-flutter-app-foundation/` and validate against the
  monorepo root.

*When in doubt about the backend contract, read `backend/AGENTS.md` and the
referenced ADRs before generating client code.*
