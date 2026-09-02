<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Shoot-Day Execution (Soll/Ist + Continuity) — Phase 2b (BLOCKED)

> **Status: contract-blocked.** The backend router serves the route
> family (`/v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots…`
> incl. plan / replan / get, start, actual-order, finish, skip, notes,
> continuity-photos upload/list/unlink, and `/v1/shooting-days/{id}/wrap`)
> but the checked-in `backend/openapi.yaml` — the single source of
> truth for the generated Dart client — does not contain them. Per the
> never-retrotype-DTOs hard rule, no client implementation may begin
> until the backend re-exports the spec and `scripts/regen-client.sh`
> runs. This change is created now to spec the UX and test tiers so
> implementation can start the moment the contract lands
> (unblock gate: GitHub issue #333).

## Why
This is the costume department's on-set daily reality: on a shooting
day, the team works the Soll (planned scene shoots) vs Ist (actual
execution — started, finished, skipped, actual order, wrap) and pins
continuity (Anschluss) photos to the shoot. `flutter-costume-domains`
covered everything route-realized; this change covers the execution
surface the backend already implements but has not exported to the
OpenAPI contract.

## What changes (when unblocked)
- `features/scene_shoots/` — day-board screen: the day's scene shoots
  in sequence (planned order vs actual order once execution begins),
  per-shoot start/finish/skip actions, actual-order reordering,
  replan, and the day's wrap, all on the real routes with the
  version-echo/optimistic/reconciliation discipline of the reference
  pattern.
- Scene-shoot notes (add/update/remove) with the same discipline.
- Continuity photos: the capture pipeline from
  `flutter-costume-domains` re-targeted for the continuity endpoints
  (upload with optional costume link, list, unlink) — AUTHZ-GATE
  (`upload_continuity_photos` capability) before every call.
- The two designated Gherkin critical scenarios deferred from Phase 2:
  the **continuity photo capture** end-to-end feature (gate → upload →
  projector-lag reconciliation → thumb appears) and the **Soll-Ist
  execution** feature (plan → start → actual-order → finish; skip +
  wrap flags reflected in the Ist state).

## Capabilities
- `flutter-scene-shoots-screen` (new)

## Dependencies
- **Depends on:** `flutter-costume-domains` (shooting-day screens,
  capture pipeline, membership gates), `flutter-login-and-app-shell`.
- **Blocked on:** backend issue for the missing OpenAPI routes
  (tracked by Phase 2 change task 0.1 — GitHub issue #333) +
  client regen
  (`scripts/regen-client.sh`); unlocking requires no other client
  change.

## Non-goals
- Reports/PDF (Phase 4 `flutter-reports`); no in-flight rescheduling
  disputes; no offline execution queue (online-first).

## Design Decisions
- **D1 — Spec against the router-served paths, not improvised ones.**
  The spec text references the route family the backend actually
  mounts (above); the client consumes them ONLY after they appear in
  the regenerated Dart client. No interim manual DTOs, no fetch-by-
  other-route workarounds.
- **D2 — Ist state is server-owned.** Moved/missing/skipped/reshot
  flags and `final`-from-`wrapped_at` semantics live in the read
  model; the client renders, never derives, them (CQRS boundary).
- **D3 — Wrap is a guarded day-level action.** Wrapping requires a
  confirm dialog naming the consequence (the day becomes immutable
  for execution); undo does not exist in the contract — the copy says
  so instead of hiding it.
