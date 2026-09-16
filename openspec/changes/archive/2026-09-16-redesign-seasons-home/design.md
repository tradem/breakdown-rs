<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

Seasons overview today (`lib/features/seasons/`): bare ListTiles with
trailing icon buttons, icon-only FAB, text-only empty state, no
loading skeleton. After the navigation-shell change this screen
becomes the Season tab's home content. Team decision 4: metrics from
Drift cache with a stale indicator. Research report §4.2 defined the
target (cards, extended FAB, guided empty state). Dependencies:
`redesign-app-shell-navigation` (removes icon buttons, provides tab
context), `add-dtcg-design-tokens` (card styling via tokens).

## Goals / Non-Goals

**Goals:**
- Card-based season rows with cached metadata + stale indicator.
- Extended FAB with visible label, gate semantics unchanged.
- Guided empty state (setup + import CTAs).
- Loading skeleton for cold start.
- Zero controller-semantic changes (optimistic/reconciliation/keys
  preserved); presentation-layer change only.

**Non-Goals:**
- No new API routes or DTOs (metadata from existing Drift cache).
- No card content redesign beyond metadata (no cover imagery,
  no season editing).
- No setup wizard (separate change `add-season-setup-wizard`; the
  empty-state CTA links to what exists at merge time).
- No visual redesign of other screens.

## Decisions

### D1 — Metrics via existing Drift hierarchy cache
`lib/data/cache/hierarchy_cache.dart` (blocks/episodes/scenes) and
season cache already hold what the cards need; a small read-only
DAO query counts rows per season id. `SeasonsScreenState` gains a
per-row `SeasonMetrics` (nullable counts + `cachedAt` timestamp).
No projection DTO reshaping; no new fetch calls on card render.

*Alternative:* backend aggregation route — rejected (API change,
cross-PR coupling, projector-lag responsibility shifts server-side).

### D2 — Stale indicator: per-card timestamp, not banner
The existing `isStale` banner covers the season list itself; card
metadata staleness is distinct (hierarchy rows can be older). Cards
show a small icon + relative time ("vor 2 h") computed from
`cachedAt` vs. cache TTL. Deterministic in tests via injected clock
(`data/cache/clock.dart` exists for exactly this).

### D3 — Card variant: M3 `Card.outlined` on light surfaces,
`Card.filled` in dark (token-driven) — single variant per theme,
chosen via token config, not per-widget branching. Touch target:
whole card; chevron is affordance, not separate button.

### D4 — Empty/state CTAs route through shell tabs
Setup CTA triggers the (future) wizard route or — until it ships —
the existing create bottom-sheet; Import-CTA switches to the Mehr
tab (AI import entry), keeping AUTHZ-GATE client check before any
network call. Copy keys live in the glossary; no hardcoded strings.

### D5 — Skeleton: simple M3 placeholder, no shimmer animation
package; `AnimatedOpacity`-fade acceptable (deterministic in goldens
via disabled animation flag). Avoid adding dependency for shimmer.

## Risks / Trade-offs

- [Metadata query cost on large caches] → counts are indexed
  SQLite lookups; measured in integration tier; caching the count
  per season id in state when cache generation stamps are equal.
- [Stale indicator wording in i18n (relative times)] → reuse
  existing localization patterns; relative-time helper unit-tested
  (deterministic via fake clock).
- [Goldens re-baseline again (after shell change)] → one-time,
  in-PR, expected; the two re-baselines happen in separate PRs so
  reviews stay reviewable.
- [Empty-state CTA to wizard when wizard change not merged yet] →
  CTA target resolved at implementation time (guarded routing
  decision in tasks); no speculative wizard code ships here.

## Migration Plan

1. Add metrics to view model (behind the same controller).
2. Swap tile→card widget, FAB, empty state, skeleton in one PR
   series; re-baseline goldens.
3. Rollback: revert — controller untouched, presentation reverts
   cleanly.

## Open Questions

None blocking. (Whether scene/costume counts render in V1 or only
block counts is decided by what the existing cache comfortably
yields — spec permits omission when absent.)
