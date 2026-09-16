<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## 1. Screen Spec & Glossary

- [ ] 1.1 Create the screen spec `docs/design/screens/seasons-home.md`
      from the template (nine sections; Salt wireframe of the Season
      tab cards; stale indicator and empty-state CTAs in the
      Interactions section)
- [ ] 1.2 Glossary: add the stale-indicator icon + copy keys for
      metadata ("{n} Blöcke"), empty-state headline/guidance, and
      the FAB label "Season erstellen"

## 2. View Model & Cache (Unit Tier)

- [ ] 2.1 Add `SeasonMetrics` (nullable counts + `cachedAt`) to
      `seasons_state.dart`; merge logic (projected rows + metrics)
      as a pure function with unit tests (Ok/Err branches of the
      DAO source)
- [ ] 2.2 DAO extension (read-only): count blocks/scenes/costumes
      per season from the existing hierarchy cache tables; unit
      tests with in-memory Drift including the empty-season case
- [ ] 2.3 Relative-time helper ("vor 2 h") with an injected clock
      (`data/cache/clock.dart`) — deterministic unit tests

## 3. Presentation (Widget Tier)

- [ ] 3.1 Season card widget (`widgets/season_card.dart`, pure
      presentation, no Riverpod): title, metadata line with stale
      indicator, chevron; card variant token-driven (light:
      outlined, dark: filled) — no hardcoded colors
- [ ] 3.2 `seasons_view_widget.dart`/`seasons_screen.dart`: tiles →
      cards (projection/overlay row keys stay: `season-<id>`,
      `overlay-<id>`, `overlay-spinner`, `overlay-warning`)
- [ ] 3.3 Replace the FAB: `FloatingActionButton.extended` with the
      label "Season erstellen" (key `season-add-fab` stays); session
      visibility logic + AUTHZ-GATE comment unchanged
- [ ] 3.4 Empty-state widget: headline + guidance + setup CTA +
      import CTA (wired to the existing create-sheet route and the
      Mehr tab switch respectively); keep the session gate for the
      setup CTA
- [ ] 3.5 Loading skeleton (M3 placeholder, no shimmer dependency;
      animation disabled in golden tests)

## 4. Tests (Tier 2)

- [ ] 4.1 Widget tests: card states (projected with/without
      metadata, optimistic as a card, stale-indicator rendering) —
      semantic finders + key pairings
- [ ] 4.2 Widget tests: extended FAB (label visible, hidden when
      signed out), empty-state CTAs including the AUTHZ denial
      narrative on import without membership
- [ ] 4.3 Skeleton test: cold start shows the skeleton, no
      empty-state flash (loading→data transition)
- [ ] 4.4 Goldens: Season tab (light/dark × cards empty/full/
      optimistic + empty state + skeleton) re-baselined

## 5. Verification & Wrap-up

- [ ] 5.1 `flutter analyze` + `breakdown_lints`, `dart format
      --set-exit-if-changed` green; coverage of changed code above
      the coverde threshold
- [ ] 5.2 Existing Gherkin/integration scenarios pass green (no
      entry change: costume assignment runs over tabs)
- [ ] 5.3 `openspec validate redesign-seasons-home` — change valid;
      update the screen spec if the implementation deviates
