<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Proposal: Expose the AI configuration centrally from the Settings screen (issue #643)

## Why

`AiConfigScreen` is reachable only from the AI-import flow (season setup
wizard info card, import-submit app-bar action). A user who wants to view
or edit the AI provider configuration without starting an import has no
entry point. The main Settings screen is the natural central home for it.

## Decision (authorization behavior, recorded via ask-user handshake)

**Show the entry only when the role resolves.** The tile is visible only
while the client-side membership gate resolves to an active costume-dept
role — the existing D2/D3 resolution chain, no new provider and no new
API surface:

```
activeBlockProvider (sticky scope)        // lib/auth/active_block.dart
  → currentMembershipProvider(scope.seasonId)
  → visible iff AsyncData && hasActiveCostumeRoleInSeason
```

- No active-block scope, a pending membership, or a membership error →
  the entry is **absent** (a pending fetch hides, never denies — D3;
  the tile IS the affordance, so a pending state renders nothing).
- Dev-auth mode short-circuits to the permissive membership inside
  `membershipFetchProvider` (existing), so the entry is visible in dev.
- The server stays authoritative: the AI-config handlers are
  handler-internally gated by `has_active_credential_role`
  (`costume_designer`/`costume_assistant`, any active membership). The
  season-scoped predicate the client reads
  (`hasActiveCostumeRoleInSeason`) is deliberately wider (adds
  `wardrobe_supervisor`), so a supervisor-only member may see the tile
  and then hit the **localized 403 narrative** rendered by
  `AiConfigScreen` (its documented D4 exception). That is honest
  degradation — never a bypass, and no invented client-side predicate
  (the exact global credential predicate is not on the wire and the
  issue forbids new API surface).
- The tile carries the `// AUTHZ-GATE:` comment (`grep AUTHZ-GATE`
  contract) referencing the server-side gate and the D4 exception.

## What Changes

- `SettingsScreen` gains an AI-configuration tile in the **general**
  section (every flavor), pushing the existing `AiConfigScreen` — no new
  screen, no new controller, no new API surface.
- New copy keys `settings.aiConfig` / `settings.aiConfigSubtitle`
  (de + en ARB catalogs, glossary row, icon `psychology_alt_outlined`
  per the existing glossary entry).
- Design docs updated first: `docs/design/screens/settings.md`
  (wireframe + component table + interactions + tests) and
  `docs/design/glossary.md`.
- Widget tests (visible / hidden-unresolved / hidden-denied / push) and
  a visible-entry golden pair; the existing four Settings goldens stay
  valid because the entry is hidden whenever no active-block scope is
  set (the golden harness never sets one).

## Impact

- No API / wire-contract change; no generated-client regen; no
  `pubspec.yaml` change.
- Touch target ≥ 48×48 dp by construction (`ListTile`).
- Existing `AiConfigScreen` tests unchanged.

## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | bump `0.4.0-alpha.18+69` → `0.4.0-alpha.19+70` | New custom feature (release mechanics per ADR-033) |
| `frontend-flutter/CHANGELOG.md` | Unreleased entry added | Version-bump documentation convention |
| `breakdown_api` (`vendor/breakdown_api/`) | (none) | `backend/openapi.yaml` unchanged |
| `*.g.dart` / `*.freezed.dart` | (none) | No codegen annotation changed (the gate reuses existing providers) |
