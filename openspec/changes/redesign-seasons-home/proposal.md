<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Why

The seasons overview — the app's home surface — renders bare
`ListTile`s ("Season N", subtitle "Number N" with trailing icon
buttons), a text-only empty state, and an icon-only FAB. Per the
UI/UX research report (§4.2) it carries no information density, no
guidance, and the weakest possible primary action affordance. Its
role after `redesign-app-shell-navigation` changes too: it is now the
**Season tab's home content** and the primary jump-off into both
planning and costuming. Team decision 4 allows metrics from the Drift
cache with a stale indicator.

## What Changes

- Season rows become **cards** (`Card` with M3 elevated/outlined
  variants): title (name or fallback "Season N"), status context
  (metadata: block/scene/costume counts), and a single trailing
  chevron affordance; the trailing icon-button cluster is already
  removed by the shell change (dependency).
- Counts sourced from the **Drift read-model cache** (no new API
  routes): blocks per season from the existing hierarchy cache;
  scenes/costumes displayed only where already cached. A subtle
  **stale indicator** (timestamp or icon from the glossary) renders
  when cache data is older than TTL (team decision 4).
- Extended FAB (`FloatingActionButton.extended`) "Season erstellen"
  replaces the icon-only FAB — visible label, AUTHZ-GATE visibility
  logic unchanged (authenticated session).
- Empty state upgraded: headline + explanatory copy + **two CTAs** —
  "Season-Setup starten" (links to the setup wizard change's
  entry route; until that change ships, existing create flow) and
  "KI-Import öffnen" (Mehr tab path) — replacing 'No seasons yet'.
- Optimistic overlays and stale banners keep their existing keys,
  semantics, and reconciliation behavior (renamed presentation only).
- Loading skeleton (shimmer-free, M3-typical) replaces blank first
  load on the tab.

## Capabilities

### New Capabilities
- `flutter-seasons-home`: card-based seasons overview content —
  metadata with stale indication, extended-FAB primary action,
  guided empty state, loading skeleton — as the Season tab content
  inside the shell.

### Modified Capabilities
- `flutter-first-screen`: the SeasonsScreen requirement's
  presentation aspects change (rows → cards, FAB label, empty
  state). Controller contract (`SeasonsController`,
  `SeasonsScreenState`, optimistic/reconciliation semantics) is
  unchanged — the requirement text is modified to describe the new
  presentation while preserving every behavioral scenario.

## Impact

- **Code:** `lib/features/seasons/seasons_screen.dart` +
  `seasons_view_widget.dart` (presentation), `seasons_state.dart`
  (add per-row metrics in the merged view model, sourced from Drift
  hierarchy cache), widgets/ folder; goldens re-baselined.
- **Data:** no API changes; Drift cache DAOs extended (read-only
  aggregation of existing tables — if a projection shape change
  were needed, the migration rule applies; target is: none).
- **Dependencies:** sequenced **after**
  `redesign-app-shell-navigation` (tab context, icon buttons gone)
  and `add-dtcg-design-tokens` (card styling from tokens).
- **Tests:** widget tests for card states (projected/optimistic/
  stale/metrics-present/metrics-absent), golden re-baseline;
  Gherkin costume-assignment scenario unaffected (entry now via
  shell tabs).
