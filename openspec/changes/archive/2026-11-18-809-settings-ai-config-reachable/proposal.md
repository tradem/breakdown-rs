<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Proposal: A configuration entry point renders its state, never hides (issue #809)

## Why

`AiConfigScreen` became unreachable from Settings in the running app: the
`_AiConfigEntryTile` rendered `SizedBox.shrink()` whenever the sticky
active-block scope was unset (`activeBlockProvider` is in-memory and starts
`null` on every cold start) or the season-scoped membership had not resolved
to an active costume-dept role. Both are ambient-scope states, not
permissions — and after a dev data reset the persisted season anchor resolves
to no row while the persisted per-season block scopes point at deleted blocks,
so the entry vanished exactly when the user needed it. A backend that is not
reachable yet (the normal state right after a reset or an API restart) was
visually indistinguishable from "you have no permission" and from "this build
has no such screen".

The screen itself was never the defect: it already distinguishes
feature-disabled, authz-denied and failed discovery. The defect is that the
denial/absence decision was made by *hiding an entry* instead of by *rendering
a state*.

## Decision

Invert the rule for Settings **configuration** entry points: render the entry,
then render the state inside it.

- **C1 — never hide on an unresolved scope.** The AI section always contains
  the entry; its subtitle states what the client knows ("Zugriff wird
  geprüft…" while the one-shot reachability probe is in flight, the plain
  "KI-Anbieter und Modelle für den KI-Import verwalten." once the backend
  answered, "Backend noch nicht erreichbar" plus a Retry action when it did
  not). Tapping always pushes `AiConfigScreen`, whose existing cards carry
  the authoritative server answer. `#643`'s "a pending fetch hides, never
  denies" (D3) stays correct for *acting on domain data* and is explicitly
  superseded here for a *settings entry point*: hiding is indistinguishable
  from absence and fails precisely in the unknown/stale state.
- **C2 — show backend reachability first, visually.** The entry reuses the
  existing health seam (`backendHealthProbeProvider` → `GET /v1/health`,
  public, never throws, maps any failure to `BackendHealthUnreachable`) as a
  **one-shot** probe with an explicit Retry — no polling (the drawer pill
  already polls) and no second probe implementation. A failed read is never
  rendered as "no configuration exists".
- **C3a — server-authoritative denial, no new API surface.** The client gate
  stays where it belongs: the AI-config handlers are handler-internally gated
  by `has_active_credential_role` (deployment-scoped). The exact global
  predicate is not on the wire, and the season-scoped approximation the tile
  used is *why* a stale scope looked like a denial. So the entry is not
  pre-gated at all; a 403 renders the existing localized administrator
  narrative inside the screen (the documented D4 exception), with no retry
  affordance.
- Inside `AiConfigScreen` the same "backend not reachable" state is rendered
  from the screen's **own** authoritative signal — a discovery failure whose
  stable code says no answer was produced (`transport.connectionError` /
  `transport.*Timeout` / `transport.unknown`) — replacing the generic
  discovery-error card for that case. No proxy probe is added to a screen
  that already owns the real call.

### Deliberately out of scope

- **C3b — precise pre-tap permission.** `GET /v1/me/capabilities` (returning
  the global `has_active_credential_role` / `has_active_ops_role`) does not
  exist in `backend/openapi.yaml`; adding it is a backend + wire-contract
  change, not a Flutter fix. Follow-up issue.
- **C4 — evicting a dead persisted season anchor.** The entry tolerates the
  stale state by construction after C1 (`activeSeasonResolution` may still
  resolve `null`). Eviction inside the shell/seasons cache is its own change
  with its own blast radius. Follow-up issue.

## What Changes

- `lib/features/settings/settings_screen.dart`: `_AiConfigEntryTile` loses the
  ambient-scope/membership gate and gains the reachability states
  (`settings-ai-config` tile, `settings-ai-config-retry` action).
- `lib/features/ai_import/ai_config/ai_config_reachability.dart` (new): the
  one-shot probe provider `aiConfigReachabilityProvider` reusing
  `backendHealthProbeProvider`.
- `lib/features/ai_import/ai_config/ai_config_state.dart`:
  `isBackendUnreachable(ProblemError)` classifies the "no answer" transport
  codes.
- `lib/features/ai_import/ai_config/ai_config_screen.dart`: the
  `ai-config-backend-unreachable` card (title + body + Retry) for that
  classification, ahead of the generic `ai-config-discovery-error` card.
- New copy keys `settings.aiConfigChecking`, `settings.aiConfigUnreachable`,
  `aiConfig.backendUnreachableTitle`, `aiConfig.backendUnreachableBody`
  (de template + en catalog); `common.retry` is reused.
- `frontend-flutter/AGENTS.md` §1 records the rule: a configuration entry
  point is never hidden by an unresolved scope; it renders its state.
- Design docs first: `docs/design/screens/settings.md` (layout, components,
  states, interactions, tests) and `docs/design/glossary.md` (copy rows).

## Impact

- No API / wire-contract change; no `vendor/breakdown_api/` regen.
- One new Riverpod codegen annotation → `ai_config_reachability.g.dart`.
- The three `'hidden …'` tests in `test/features/settings/settings_screen_test.dart`
  are replaced by state-rendering tests; new goldens cover the four entry
  states so a hidden entry cannot silently return.
- The string `zuletzt geprüft` / reachability copy is client-localized; no
  server `detail` is ever rendered (AGENTS.md §5).

## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | bump `0.4.0-beta.34+126` → `0.4.0-beta.35+127` | New custom feature (ADR-033 release mechanics) |
| `frontend-flutter/CHANGELOG.md` | Unreleased entry added | Version-bump documentation convention |
| `breakdown_api` (`vendor/breakdown_api/`) | (none) | `backend/openapi.yaml` unchanged |
| `*.g.dart` / `*.freezed.dart` | regenerated (`ai_config_reachability.g.dart`, `lib/l10n/generated/*`) | New `@riverpod` provider + four new ARB keys |
