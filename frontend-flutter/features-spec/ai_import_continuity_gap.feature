# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.4 (opencode-go)

# Feature: Wardrobe-gap resolution on the AI-import preview (issue #745).
#
# OpenSpec change `ai-import-decision-outfit-continuity`: after Pass 2 the
# preview shows WHERE each look came from, and a scene whose figure the script
# left undressed offers ONLY the looks the script supports (a continuation of
# the figure's most recent earlier look, and/or a look derived from the scene's
# own location). The reviewer resolves the gap in ONE tap and the apply request
# carries the pick as `continuity_selections`.
#
# This is NOT one of the designated critical acceptance scopes (AGENTS.md §6),
# but the issue asks for an end-to-end Gherkin covering the flow.
#
# @pending until the on-device seeding can hand the runner a Pass-2 preview:
#   1. the harness must be able to seed a job whose stored preview carries a
#      `dropped_row` gap uncertainty with candidates (`AppWorld.seedIds` today
#      seeds ids only, and the preview is produced by the AI worker, not by a
#      seeding call), and
#   2. the gap steps below need their `integration_test/gherkin/steps/`
#      definitions.
# Until promoted, the flow is covered by widget + unit tests
# (test/features/ai_import/preview_continuity_test.dart,
# test/unit/continuity_gap_test.dart, plus the committed goldens).

Feature: Wardrobe-gap resolution and look provenance on the AI-import preview

@pending
Scenario: A Pass-2 preview shows the look's provenance and resolves a gap in one tap
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  And an AI-import preview for job "job-1" carries a continuation look for "BEN" in scene 4
  And the same preview carries a wardrobe gap for "BEN" in scene 5 with candidates
  When I open the preview for job "job-1"
  Then I expect the widget "ai-preview-outfit-origin-row-4-0" to be present within 10 seconds
  And I expect the widget "ai-preview-gap-1-ben" to be present within 10 seconds
  When I pick the continuation candidate for the gap "1-ben"
  Then I expect the widget "ai-apply-continuity-gap-1-ben" to show the look "Zivil-Look"

@pending
Scenario: A gap without script-derivable candidates offers no choice
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  And an AI-import preview for job "job-2" carries a wardrobe gap for "CARLA" without candidates
  When I open the preview for job "job-2"
  Then I expect no widget "ai-preview-gap-3-carla" to be present within 10 seconds
  And I expect the uncertainty notice for the gap to be present within 10 seconds
