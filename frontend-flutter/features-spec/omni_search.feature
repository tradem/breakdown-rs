# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3-flash (opencode-go)
# Co-authored-by: glm-5.3-flash (neuralwatt)

# Feature: OmniSearch — search across the active season from the top bar
# (issue #616, OpenSpec change `add-omni-search`).
#
# OmniSearch is NOT one of the designated critical acceptance scopes
# (AGENTS.md §6: Soll/Ist report, continuity photo, costume assignment);
# the surface is covered exhaustively by widget tests
# (omni_search_screen_test.dart) and by the data-layer DAO tests. This file
# exists because the task checklist (task 7.3) explicitly asks for the
# device-level happy path: the top-bar slot (#613) is shell chrome (the
# context bar lives OUTSIDE the surface's own widget tree), so only a
# device run asserts the affordance → surface → result flow end-to-end.
#
# @pending until the AppWorld seeding fixtures understand the fake OmniSearch
# universe (the widget tests drive the surface with a fake DAO holder; the
# device fixture needs one real backend season with the exact rows the
# steps quote — the same seeding shape the costume-assignment flow uses).

@pending
Scenario: Search across the season from the top bar
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  And the season "SF-1" is active with scene "Wohnung Zoe", character
    "Zoe Zimmermann", costume "Marineblau Wolle" and shooting day
    "Wonnemonat"
  When I tap "shell-search-action" in the top bar
  Then I expect the widget "omni-search-field" to be focused within 30 seconds
  When I type "wohnung"
  Then I expect the widget "omni-search-group-scene" to be present
  And I expect the widget "omni-search-hit-scene-s1" to be present

@pending
Scenario: Restricting the search to the costume facet
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  And the season "SF-1" is active with scene "Wohnung Zoe" and costume
    "Marineblau Wolle"
  When I tap "shell-search-action" in the top bar
  And I type "wo"
  And I toggle the facets "omni-search-chip-scene",
    "omni-search-chip-character" and "omni-search-chip-shooting-day" off
  Then I expect the widget "omni-search-group-costume" to be present
  And I do NOT expect the widget "omni-search-group-scene" to be present
