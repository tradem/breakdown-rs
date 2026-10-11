# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.3-flash (opencode-go)

# Feature: Role extract from the Cast view (issue #611).
#
# The role extract ("Ring binder per role") is NOT one of the designated
# critical acceptance scopes (AGENTS.md §6: Soll/Ist report, continuity
# photo, costume assignment) — this file exists because the issue checklist
# explicitly asks for a Gherkin step covering the Cast → role-extract
# navigation, and because the navigation is the entry point for the
# costume-assignment critical flow's costume stream.
#
# @pending until both halves land:
#   1. the backend read model (backend issue #621,
#      `GET /v1/characters/{id}/appearances`) ships and
#      `role_extract_screen.dart` renders the extract rows instead of the
#      degraded character-detail pass-through; and
#   2. the seeding Given step establishes the character symbolic id
#      ("ch-1") the way the other critical flows seed their ids
#      (AppWorld.seedIds). Until promoted, the degraded route is covered by
#      widget tests (characters_screen_test.dart, RoleExtractScreen group).

@pending
Scenario: Role extract opens from the Cast view's roster
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  When I open the role extract for character "ch-1" in season "1"
  Then I expect the widget "role-extract-ch-1" to be present within 30 seconds
