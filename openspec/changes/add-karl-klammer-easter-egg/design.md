<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Design: add-karl-klammer-easter-egg (issue #516)

## Context

The settings live in `SettingsDialog` (`lib/features/app_info/settings_dialog.dart`),
opened from the Mehr tab tile `mehr-settings`. The dialog mixes
flavor-visible read-only info with a dev-only backend-URI override
editor (`validateApiBase`, `SessionReset.switchBackend` /
`resetBackendToDefault`, `ApiBaseOverrideStore` in
`flutter_secure_storage`). There is no general-settings section, no
Easter-egg mechanism, and the AI Import view (`lib/features/ai_import/`
— `ai_config/`, `import_jobs/`) has no assistant layer. Navigation is
plain `Navigator.push` + `MaterialPageRoute` (no go_router). The seasons
screen (`lib/features/seasons/`) is the reference pattern: `ConsumerWidget`
screen + `@riverpod` controller + Result-typed repository + AUTHZ-GATE
comments + four-tier tests.

## Goals / Non-Goals

**Goals**
- Full-screen settings with a general (all flavors) vs. development
  (dev-only) section separation; feature-loss-free migration of the
  dialog dev flow.
- A persistent, immediately-effective Easter-eggs toggle as the
  foundation for future Easter eggs.
- Karl Klammer as the first Easter egg: a deterministic, non-modal,
  fully hideable assistant in the AI Import view.

**Non-Goals**
- Offline command queue, go_router migration, new general settings
  beyond the toggle (structure only).
- Signed-out reachability of the settings screen: the only entry point
  remains the authenticated Mehr tab (Q4 — decided out of scope; the
  auth shell already owns all post-login destinations; revisit if a
  signed-out settings path is ever required).
- Any change to `backend/openapi.yaml` or `info_dialog.dart`.

## Decisions

### D1 — Persistence: `shared_preferences` (resolved Q1)
The Easter-eggs flag is a non-secret boolean; `flutter_secure_storage`
would misuse the secure enclave. A new `shared_preferences` dependency
(the first-party plugin, no transitive surprises) is fit for purpose.
The store mirrors `ApiBaseOverrideStore`'s shape: Result-typed
read/write, `ProblemError` codes `settings.easter_eggs_read_failed` /
`easter_eggs_write_failed`, no `throw` in `data/`. *Alternative
considered:* reusing secure storage for consistency — rejected
(overkill for a boolean; contradicts the "not a secret" honesty rule).

### D2 — Karl Klammer asset: self-drawn CustomPainter (resolved Q2)
The hanger is drawn with `CustomPainter`/`Clippers`, geometrically based
on the Material Symbols `checkroom` glyph (Apache-2.0, the same source
as the launcher icon — verified by `gen-app-icon.sh`); the figure itself
and its animation are our AGPL-3.0 work. Colors come from
`lib/design/` tokens. *Alternatives:* Rive/Lottie (adds runtime package
+ authored asset), icon-only figure (cheapest, least charm). The
programmatic approach gives state-driven poses (swing/droop/pride) with
zero package growth.

### D3 — Settings provider architecture
`easterEggsEnabledProvider` — a `@riverpod` `Notifier<bool>` (default
`true`) that hydrates from the store on init and flips immediately on
`toggle()`. AI Import screens `ref.watch` it; the overlay disappears
immediately on `false`. The settings screen's dev section reuses the
existing providers (`appConfigProvider`, `runtimeApiBaseProvider`,
`sessionResetProvider`) — no new state machinery for the migration.

### D4 — Karl Klammer trigger logic (resolved Q3 — tone & triggers)
Pure function `clippyTipFor(ImportFlowState state, int visitCount)` in
`lib/features/ai_import/` (unit-testable, deterministic): maps the AI
Import flow state to a tip/pose. Triggers:
- **No AI config** → the "It looks like you're writing a letter…" allusion,
  offering the AI-config entry (`aiImport.clippy.noConfig`).
- **Import job running** → excited swing/wobble pose
  (`aiImport.clippy.running`).
- **Error** → droop pose, consoling copy keyed on the ProblemDetails
  `code` (`aiImport.clippy.error`).
- **Success** → proud "wearing the result" pose (`aiImport.clippy.success`).
- **Idle** → occasional Clippy-canon joke via an injectable idle-clock
  (`aiImport.clippy.idle.*`, small fixed set) — never wall-clock or
  random in tests; the clock is a test-injected fake.
No network calls, no tracking. Placement: bottom-leading overlay above
content, never over primary CTAs (verified in goldens); tap dismisses
for the session.

### D5 — Prod visibility (resolved Q5)
The development section is dev-flavor-only; in `prod` the read-only
server address + flavor rows (with the explanatory prod note) remain on
the settings screen — exactly the previous dialog's prod surface,
unhidden.

## Risks / Trade-offs

- [New dependency `shared_preferences` in the tree] → first-party,
  no secrets stored; gitleaks coverage already scans `.dart`/`.yaml`.
- [Easter-egg toggle read failure on a broken device store] → store is
  Result-typed; fallback is default ON plus a visible error state on the
  screen — no silent failure (mirrors the `discard-result` rule).
- [Karl Klammer overlaying CTAs on small screens] → bottom-leading
  placement + golden assertions that primary CTAs remain hit-testable;
  character is tap-dismissable.
- [Dialog → screen migration losing test coverage] → the existing
  `settings_dialog_test.dart` scenarios are ported to
  `settings_screen_test.dart` in the same change; dialog tests deleted
  with the dialog.

## Migration Plan

1. Author `docs/design/screens/settings.md` + glossary/ARB keys
   (Task 1) — before implementation.
2. Land the settings screen + store + toggle (Tasks 2–4), keeping the
   screen's dev flow byte-behavioral-identical to the dialog's.
3. Land Karl Klammer (Tasks 5–6).
4. Delete `SettingsDialog`/`showSettingsDialog` and their tests, update
   the Mehr tile (single task to avoid a dual entry point window).
Rollback: revert the commit series; the screen is additive until the
dialog deletion, which is one atomic commit.

## Open Questions

None — Q1–Q5 resolved as D1 (user-confirmed), D2 (user-confirmed),
D4, non-goal (signed-out reachability), and D5 respectively.
