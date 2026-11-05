<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 823 — The plus action is destination-scoped, and the AI-import jobs screen owns an Import action

## Why

Issue #612 introduced the shell plus action as ONE Spotify-style extended FAB on
the shell `Scaffold`, and #624 made its sheet context-sensitive (Szene/Drehtag
only for the active episode of the active season). That was a deliberate
over-correction of "scattered create entry points": today the FAB renders on
**all three destinations in all three morphologies** and on every route pushed
inside a tab — including the two destinations that have nothing to create from
it (Cast = roster/pieces, Schedule = day board), and including the AI-import
jobs screen's own stack, where the generic sheet implies four choices but only
`Import` belongs to that surface.

Meanwhile the AI-import jobs screen (issue #672 made it a directly reachable
operational screen) has no create affordance of its own: its only "start a new
import" path is the empty-state CTA `ai-jobs-empty-cta`, which disappears as
soon as the list has rows. A user with 40 past imports has **no** way to start
the 41st from that screen.

## Decision

- **D1 — the plus action renders on exactly two surfaces.**
  - **Script destination** (`state.selectedIndex == kScriptTabIndex`, all three
    morphologies, including routes pushed inside that destination's navigator —
    a destination, not a route, is the scoping unit): the existing
    `shellQuickCreateActions` list unchanged, with the existing
    episode-scope guard (Szene/Drehtag only when the active episode belongs to
    the active season).
  - **`AiImportJobsScreen`**: one entry, `Import`, pushing
    `AiImportSubmitScreen`.
  - **Cast and Schedule destinations: nothing** — no FAB and no reserved
    space.
- **D2 — the compact bottom clearance follows the same predicate.** The 80 dp
  band exists only because the docked extended FAB would cover the last list
  row (#623). It is now applied with `showsPlusAction`, not with `canCreate`,
  so the two destinations without a FAB lose the dead band. Medium/expanded
  stay at 0 (the FAB floats over the content's bottom-right corner where no tab
  list ends).
- **D3 — the sheet stays data-driven; the jobs screen gets its own list.** The
  reporter considered and accepted a sheet with a single entry. So
  `showQuickCreateSheet` / `QuickCreateSheet` are reused unchanged, and
  `quick_create_sheet.dart` gains a second factory next to
  `shellQuickCreateActions` — the Import entry is built by ONE shared helper so
  the two lists can never drift, only their list lengths differ.
- **D4 — own test key, own label.** The jobs-screen FAB is `ai-jobs-plus-fab`
  (the shell keeps `shell-plus-fab`; "one FAB" assertions must stay
  unambiguous per surface) and its label is `navAiImport` („Import") — the
  action is named after what it does, not after the generic „Erstellen". A
  shared `PlusActionFab` design component carries the accessible BUTTON role
  (#623: `FloatingActionButton.extended` exposes the tap action but not the
  semantics button flag) so the rationale is stated once instead of twice.
- **D5 — the AUTHZ-GATE comment travels.** The session gate for the sheet
  (`Requirement::Authenticated`; the backend create/import handlers are
  auth-gated server-side) moves into the shared FAB's contract AND is restated
  at each call site, because `grep AUTHZ-GATE` is the review contract and the
  two sites can be gated independently. A signed-out/unresolved session renders
  neither FAB.
- **D6 — the jobs screen's empty-state CTA is dropped.** With an always-visible
  FAB on the same screen the CTA is a second path to the identical flow
  (reporter decision, option "drop it"): the empty state becomes plain
  narrative, `aiJobsEmptyCta` leaves both ARB catalogs, and the FAB is the
  screen's single create affordance in every list state (empty, loading, data,
  error, stale).

## Alternatives rejected

- **Returning the FAB to the Cast/Schedule destinations for symmetry.** Both
  destinations have per-screen FABs for the thing they actually create
  (`character-add-fab`/`piece-add-fab`, `shooting-day-add-fab`); a generic
  "Erstellen" next to them advertises flows that do not apply.
- **A property/setter on the shell for the jobs screen to "own" the plus
  action.** The jobs screen is pushed inside a tab navigator, not a shell
  destination — a shell flag would have to be set on push and cleared on pop
  (route-lifecycle coupling, stale on a hot restart). The screen renders its own
  `Scaffold`, so it renders its own affordance.
- **Making the jobs-screen action a plain `FilledButton` in the app bar.** It
  is the same plus action as the shell's and must read as one; the issue's
  decision is a FAB with a one-entry sheet.
- **Keeping the generic „Erstellen" label on the jobs screen.** A FAB that says
  „Erstellen" and then offers exactly one thing is a lie about the choice; the
  label is the honest entry name (`navAiImport`).
- **Duplicating the FAB + `Semantics(button: true)` at the second site.** Two
  copies of the same a11y rationale drift; the shared component keeps one.

## Impact

- `lib/design/components/plus_action_fab.dart` (new) — the button-role FAB.
- `lib/features/shell/quick_create_sheet.dart` — `aiImportJobsQuickCreateActions`
  plus the shared Import-entry helper the shell list also uses.
- `lib/features/shell/app_shell.dart` — `showsPlusAction`, clearance predicate,
  comments (the #612 "all three morphologies" rationale is superseded).
- `lib/features/ai_import/import_jobs/jobs_screen.dart` — the screen's own FAB +
  AUTHZ-GATE comment; the empty-state CTA and its now-unused import go away.
- `lib/l10n/app_{de,en}.arb` — remove `aiJobsEmptyCta`; regenerate
  `lib/l10n/generated/`. No new copy keys: the FAB label and the entry copy
  already exist (`navAiImport`, `quickCreateAiImportSubtitle`,
  `quickCreateTitle`).
- Tests: `test/features/shell/app_shell_test.dart` (the #612 group flips to the
  destination scope, plus a dead-band test),
  `test/features/ai_import/jobs_screen_test.dart` (FAB + single-entry sheet +
  routing + session gate; the empty-state CTA test becomes a plain narrative
  assertion), `test/features/shell/quick_create_sheet_test.dart` (the new
  factory).
- Goldens: the six shell goldens re-baseline (the default destination is Cast,
  which no longer carries a FAB) and the four `ai_jobs_*` goldens re-baseline
  (the screen gains a FAB).
- Docs: `docs/design/screens/navigation-shell.md`, `ai-import-jobs.md`,
  `script-view.md`, `docs/design/glossary.md` (+ the jobs wireframe).

## Non-goals

- The per-screen FABs (`season-add-fab`, `block-add-fab`, `episode-add-fab`,
  `scene-add-fab`, `character-add-fab`, `piece-add-fab`,
  `shooting-day-add-fab`, `category-add-fab`) are untouched.
- The other entries into `AiImportSubmitScreen` (production overview, setup
  wizard last step, seasons empty state, apply recovery) are untouched.
- No change to what the quick-create entries DO — only to where the plus action
  is offered.

## Follow-ups (not this change)

- The pushed-inside-the-Script-destination case keeps the FAB over a pushed
  screen's own content (e.g. the scene detail's save bar). Whether a pushed
  detail screen should hide the destination-level plus action is a navigation
  design question, not a scoping bug; it never applies to Cast/Schedule
  anymore because they carry no FAB at all.
