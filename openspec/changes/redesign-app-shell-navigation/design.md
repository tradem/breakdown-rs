<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

Post-login UI today: `AuthGate` → `SeasonsScreen` as root, every
further screen reached by `Navigator.push` (season rows to Blocks,
season-tile ICON buttons to Costumes/Characters/Categories,
AppBar overflow for AI import/settings). No shell, no tab semantics,
deep back-stack. Research report §4.1 diagnosed this as the app's
primary UX defect; team decision 1 selected the 4-tab layout
(Season | Planen | Kleidung | Mehr). Constraints: Riverpod-only
(AGENTS.md D3), no new routing package (flutter-hierarchy-navigation
spec: "no new routing package", go_router explicitly forbidden),
generated OpenAPI client, AUTHZ-GATE discipline, four-tier test
pyramid;  breaks widget tests/goldens that use the season-row icon
keys. This change is sequenced after `add-dtcg-design-tokens`
(shell styling uses tokens) and `establish-design-doc-workflow`
(screen spec for the shell is part of that workflow).

## Goals / Non-Goals

**Goals:**
- Adaptive shell (NavigationBar/Rail/Drawer) with 4 labeled tabs.
- Per-tab state preservation + sane back behavior.
- Migration of entry points: costume domains via Kleidung tab,
  secondary destinations via Mehr tab; removal of season-row icon
  buttons.
- Retrofit of existing controllers/screens into the shell with
  minimal semantic change (list controllers stay as-is).

**Non-Goals:**
- Deep-linking / URL routing (no routing package, no go_router).
- Redesigning the Seasons list content itself (next change
  `redesign-seasons-home` — P2 of the roadmap).
- Setup wizard (separate change `add-season-setup-wizard`).
- Any backend/API change.
- Reports redesign (reports live in Mehr as-is).

## Decisions

### D1 — Shell composition: custom adaptive shell, no new packages
New `lib/features/shell/` with `AppShell` (ConsumerWidget) that
resolves window size class from `MediaQuery`/`LayoutBuilder and
builds `NavigationBar`, `NavigationRail` + content row, or
`NavigationDrawer` variants. M3's canonical breakpoints (600/840)
are encoded in one place (`design/` tokens or a shell constant —
referencing the token dimension set if feasible).

*Alternative:* `flutter_adaptive_scaffold` / NavigationSuite port
packages rejected: new dependency for logic we can express with
Material primitives; the CI-hardening and dependency-policy specs
favor zero-dep solutions here.

### D2 — Tab content: per-tab nested `Navigator` via `IndexedStack`
Each tab hosts a private `Navigator` (restorable, own observers);
an `IndexedStack` keeps all four alive so switching preserves
position (charts, scroll, drilled stack) without re-fetch. Riverpod
`@riverpod` `shellController` holds the selected index (and only
that). System back is intercepted per-tab via the inner navigators:
inner `maybePop` first; inner root → outer `PopScope` handles
exit-once semantics (D3).

*Alternative:* `PageView`+state hoisting rejected (lose deep-trees
cheapness); single shared Navigator with route names rejected (re-
introduces pseudo-router and tab-back-hopping bugs the spec forbids).

### D3 — Back behavior: within-tab only, then exit
Android predictive-back compatible: inner navigator pops; at tab
root, `PopScope` bubbles to the OS (app exit intent via
`SystemNavigator.pop` on the initial flow only — no synthetic tab
hopping). Rationale: tab switches are user-model 'jump' actions, not
history steps; making back hop tabs matches no platform convention
and the spec forbids it.

### D4 — Entry-point migration, no controller rewrites
BlocksScreen/EpisodesScreen/ScenesScreen unchanged internally (they
already receive parent DTOs via constructor) — only the pushing
context moves (Planen tab). CostumesScreen/CharactersScreen keep
controllers/keys; only the constructor call sites move (Kleidung tab
+ season detail). CostumeCategories move to Mehr (+ season detail
later). AI-importAppBar entry moves to Mehr (its own AUTHZ-GATE
comment travels with it — grep-verification still passes).

### D5 — Season context for Kleidung tab
Active season = last-opened season (Riverpod provider persisted via
Drift `seasons_view`-style cache — analogous to an existing
`active-block` store in auth/, reused pattern). With no seasons /
nothing selected: empty state with CTA to the Season tab (spec
scenario). No season-changing token knowledge is assumed in
widgets: the shell controller exposes `activeSeason` as plain data.

### D6 — Test strategy (four tiers, per flutter-test-pyramid)
Unit: shell controller state transitions; keine widget imports.
Widget: per-morphology (compact/medium/expanded — via
`tester.view.physicalSize`); tab preservation; back contract;
label visibility (semantics). Goldens: shell in three morphologies +
dark/light. Integration: tab-switch smoke on device; existing
Gherkin costume-assignment scenario rewired from icon tap to
Kleidung tab path (critical-flow contract stays intact end-to-end).

### D7 — Auth/sign-out mid-session
Inherited behavior: shell listens to `authSessionControllerProvider`
— sign-out/sign-in mid-session pops to gate (existing pattern already
in BlocksScreen etc.); shell root resets tab index on new session.

## Risks / Trade-offs

- [IndexedStack keeps 4 trees alive → memory/CPU cost on low-end
  Android] → measure on device in integration tier; escape hatch
  documented (lazy-stack with keep-alive per tab) if profiling
  demands; not premature now.
- [Nested Navigators complicate route observers/analytics later] →
  accepted; observers per tab are isolated by design; deep-link
  work (future change) would introduce a router package with its
  own OpenSpec change anyway.
- [Golden re-baseline churn across the app (appBars stay, screens
  shrink inside shell)] → goldens re-baselined in this change,
  deliberately (one-time cost, reviewed in the same PR); CI keeps
  failing on any further drift.
- [Widget-test rewrite for icon-key consumers (Gherkin
  `open-costume-assignment-*` steps)] → migrated in-change with
  explicit task; scenario semantics preserved, only the entry action
  changes.

## Migration Plan

1. Add shell (dark-flight behind nothing — single PR sequence
   within the change): shell + 4 tabs wiring existing root screens.
2. Rewire pushing contexts (Planen tab) and entry points
   (Kleidung/Mehr); delete season-row icon buttons.
3. Re-baseline goldens; migrate affected widget/Gherkin tests.
4. Rollback: revert PR series — screens return to direct push
   navigation; no data migrations involved.

## Open Questions

None blocking. (Icon choice for the four tabs from Material Symbols
is implementation detail sourced from the glossary; labels fixed:
"Season", "Planen", "Kleidung", "Mehr".)
