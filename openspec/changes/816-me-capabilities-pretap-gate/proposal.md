<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Proposal: the global capability route makes the credential gate exact on the client (issue #816, C3b of #809)

## Why

#809 shipped C1 (`Ki entry always rendered`) + C2 (`backend reachability stated
visually`) + C3a (`server-authoritative denial rendered inside the screen`) and
deliberately deferred C3b. The consequence is still visible in the running app:
the client cannot say "Keine Berechtigung" **before** the tap.

The gate the AI-configuration handlers enforce is
`AuthorizationPolicy::authorize_credential_role` →
`MembershipRepository::has_active_credential_role`
(`backend/crates/core/src/membership/ports.rs:145`), a **deployment-scoped**
predicate that is not on the wire. The only membership signal the client does
have is season-scoped, and it is the wrong tool twice over: it is a superset
(it also grants `wardrobe_supervisor`) and it is ambient (a stale scope reads as
a denial — exactly the failure #809 had to tolerate). So every AUTHZ-GATE mirror
for a credential-scoped surface stays an approximation, and the entry cannot
pre-state the true permission.

## Decision

Publish the **enforcement** predicate as a self-report, not a second policy.

- **`GET /v1/me/capabilities`** returns the two **global** predicates as
  booleans: `has_active_credential_role` and `has_active_ops_role`. The handler
  resolves them through the **injected `AuthorizationPolicy`**
  (`AppState::authorization_policy` — the very instance the middleware uses), so
  the answer cannot drift from enforcement: the ops arm includes the
  `OPS_ADMIN_SUBS` bootstrap allowlist, and a read-model failure surfaces as a
  server error instead of a fabricated `false`.
- **200 with booleans, not 403.** A capability *self-report* that 403s on
  denial could not answer the question it exists for (it would be a second form
  of the C3a server denial, and the client would again be interpreting an error
  status). There is no privileged action on this route, so the handler carries
  an `// AUTHZ-GATE:` comment documenting that it **reports** the decision
  instead of enforcing one — it resolves both predicates handler-internally,
  never through the block-scoped middleware.
- **`Authenticated` at the middleware.** No block membership, no tenant data;
  `X-Active-Block` says nothing about a deployment-scoped capability. The route
  is the first member of a `/me` namespace (the work-order note in
  `docs/planning/2026-11-house-keeping-work-order.md` flags that namespace
  decision explicitly), classified narrowly (`path == "/me/capabilities"`, like
  `/audit` and `/series/{id}/membership`) so no future `/me/*` route inherits
  `Authenticated` silently.
- **The client mirror becomes exact, and it is a gate.** The entry renders
  "Keine Berechtigung" when the resolved answer denies, and the AI-config
  discovery dispatch is short-circuited in that case — no request is issued. The
  suppression lives in the discovery seam (`aiConfigDiscovery`), the single place
  where `GET /v1/ai-import/config` is dispatched, and is keyed on a
  **client-detected** problem code (`ai_config.capability_denied`, the established
  `ai_import.scope_missing` / `ai_config.decision_key_missing` pattern) so the
  screen path stays identical to a real server denial: same narrative, no retry
  affordance. Unknown (probe in flight, transport failure, 5xx) is never a
  denial — the request proceeds and the server stays authoritative.

### Deliberately out of scope

- No season-scoped predicate is added or widened (ADR-035 B2): this route
  carries the *global* credential gate only.
- No polling. The probe is one-shot with an explicit Retry, exactly like the
  #809 reachability probe; the drawer health pill remains the only periodic
  probe.
- `has_active_ops_role` is published (the issue asks for both predicates) but
  no client surface consumes it yet — the ops surfaces are authenticated-route
  + handler-gated today, and a pre-tap ops gate is its own change.

## What Changes

**Backend**

- `backend/crates/api/src/me.rs` (new): `MyCapabilitiesResponse` (utoipa
  `ToSchema`) + `get_my_capabilities<P: Ports>` handler; both predicates via
  `state.authorization_policy`, `// AUTHZ-GATE:` comment on the resolution.
- `crates/api/src/handlers/mod.rs`: mount `/me/capabilities`.
- `crates/api/src/lib.rs`: `pub mod me;` + `paths(...)` entry.
- `crates/api/src/auth/authorization.rs`: `requirement_for` arm —
  `/me/capabilities` ⇒ `Requirement::Authenticated` (narrow equality).
- `crates/api/tests/route_coverage.rs` (112 → 113 routes + table row),
  `crates/api/src/auth/authorization/authorization_test.rs` (allowlist),
  `crates/api/tests/handler_authz.rs` (401 without token, 200 without block
  membership), new case file `crates/api/tests/handler_me_capabilities.rs`
  (granted / none / ops-only / predicate failure) wired into the `handlers`
  harness.
- `backend/openapi.yaml` regenerated (`UPDATE_OPENAPI=1 cargo test -p api --test
  contract openapi_drift`); `api` crate MINOR bump + CHANGELOG.

**Client**

- `frontend-flutter/vendor/breakdown_api/` regenerated by
  `scripts/regen-client.sh` (no hand edits); `CLIENT_VERSION` 1.4.0 → 1.5.0
  (additive wire).
- `lib/data/capabilities_repository.dart` (new) + provider seam
  `myCapabilitiesProvider` (`lib/auth/capabilities_providers.dart`), testable by
  overriding the repository like every other `data/` boundary.
- `lib/features/settings/settings_screen.dart`: the AI entry gains the
  resolved-denial subtitle (`settings.aiConfigDenied` = "Keine Berechtigung"),
  ranked below "unreachable" and above the ordinary subtitle; it stays tappable
  (state, not absence — #809's rule).
- `lib/features/ai_import/ai_config/ai_config_controller.dart`: `aiConfigDiscovery`
  short-circuits on a resolved denial (no request).
- `lib/features/ai_import/ai_config/ai_config_state.dart`:
  `ai_config.capability_denied` → `aiConfigErrorAdmin` copy and
  `isAiConfigAuthzDenied` membership (same rendering as the server 403).
- ARB de/en (`settingsAiConfigDenied` + client-code entry), `flutter gen-l10n`,
  `build_runner` for the new providers.
- Widget tests: entry states granted / denied / pending / error with the fetch
  seam injected; discovery-dispatch suppression in the AI-config tests.
- Docs: `docs/design/screens/settings.md`, `docs/design/glossary.md`,
  `frontend-flutter/AGENTS.md` §1; `openspec/specs` delta for
  `flutter-client-authz` (+ `api-authorization` for the new route).

## Impact

- One new wire route and one new namespace (`/me`); no existing route, schema or
  problem code changes. `openapi.yaml` gains one path + one schema; the Dart
  client gains one operation + one model.
- No projector, aggregate, event or migration: the route reads two existing
  predicates.
- Flutter: one new `data/` repository + provider, two touched feature files, one
  new ARB key per locale.

## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `api` (`backend/crates/api`) | MINOR `0.63.0` → `0.64.0` | New public route + response schema |
| `core` / `infra` | none | Predicates and policy port already exist |
| `backend/openapi.yaml` | regenerated | Code-first contract (ADR-006) |
| `breakdown_api` (`vendor/breakdown_api`) | regenerated, `1.4.0` → `1.5.0` | Additive operation + model |
| `frontend-flutter` (`pubspec.yaml`) | `0.4.0-beta.45+137` → `0.4.0-beta.46+138` | New custom feature (ADR-033) |
| `*.g.dart` / `lib/l10n/generated/*` | regenerated | New `@riverpod` providers + ARB key |
