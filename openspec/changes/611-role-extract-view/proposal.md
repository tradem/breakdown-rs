<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Proposal: Role-extract view — all scenes & costumes of one character in scene order (issue #611)

## Problem

The Cast view's deep content is the **role extract**: for each character,
one screen that reads like the traditional physical ring binder/Register
per role — every scene the character appears in, in script order, with
that character's costume per scene.

Characters list + character detail (contacts, measurements, category row)
already exist as entry points. The gap is a per-character read-model
route: `GET /v1/scenes/{id}/characters` is per-*scene*; building the
extract client-side would mean fan-out queries per scene (N scenes → N
calls) — neither deterministic nor projector-lag-friendly for a primary
navigation view. Per the CQRS discipline (client never aggregates
projections itself), this needs a backend read-model first.

## What Changes

- **Navigation seam (this change):** the Cast view's character row tap
  opens a new `RoleExtractScreen` — the entry point is already the
  extract, never the bare detail (decision A, confirmed with the user).
- **Degraded fallback (this change):** the per-character appearances read
  model (`GET /v1/characters/{id}/appearances`, backend issue #621) does
  not exist yet, so the screen renders the character detail as today
  (list-only fallback, no client-side fan-out). The route seam makes the
  future swap body-only: no call site or test key changes when the
  backend ships.
- **On-device Gherkin (this change, @pending):** a role-extract feature
  file + step (`I open the role extract for character … in season …`)
  wired against a stable route key `role-extract-<characterId>`;
  promotes into the on-device pass when backend #621 lands.
- **Screen spec (this change):** `docs/design/screens/role-extract.md`
  (Soll layout + degraded state), and the Cast view spec's navigation
  row updated.

## Non-Goals (backend half tracked separately)

- The per-character appearances read model + projection index — backend
  issue **#621**; the client change consumes the generated type only
  after it ships (`scripts/regen-client.sh`).
- l10n keys for extract rows/chips — arrive with the backend read model
  (no new user-facing copy in the degraded state; key parity enforced by
  CI).

## Impact

- **Affected specs:** no **existing** capability spec changes. This
  change ADDS the `flutter-role-extract` delta spec
  (`specs/flutter-role-extract/`): the Cast-entry requirement (route key
  `role-extract-<characterId>`), the degraded no-client-side-aggregation
  fallback, and the pending on-device Gherkin step. The human-readable
  surface is the screen spec
  (`docs/design/screens/role-extract.md`).
- **Affected code:**
  - `lib/features/characters/role_extract_screen.dart` (new)
  - `lib/features/characters/characters_screen.dart` (push target)
  - `integration_test/gherkin/steps/common_steps.dart` +
    `configuration.dart` (new @pending step)
  - `features-spec/role_extract.feature` (new, @pending)
  - `test/features/characters/characters_screen_test.dart` (new group)
  - `docs/design/screens/role-extract.md` (new) +
    `docs/design/screens/cast-view.md` (navigation row)
