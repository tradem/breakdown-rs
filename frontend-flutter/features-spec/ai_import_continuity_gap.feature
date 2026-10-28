# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: glm-5.4 (opencode-go)
# Co-authored-by: deepseek-v4.1-flash (opencode-go)

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
# but the issue asks for an end-to-end Gherkin covering the flow. It is fully
# promoted (issue #748): no `@pending` left, so both scenarios run in the
# default on-device pass.
#
# How the runner reaches a Pass-2 preview: a preview is produced by the AI
# worker, not by a seeding call, so the harness seeds one through the
# `test-support`-only fixture route `POST /v1/__fixtures/ai-import-preview`
# (issue #748, absent from release builds and from backend/openapi.yaml). The
# arrange steps then READ the stored preview back over the real
# `GET /v1/ai-import/jobs/{id}/preview` before the device ever opens the
# screen, so a misconfigured fixture backend fails the Given, not the Then.
# The dev backend therefore needs:
#   cargo run --bin api --features api/test-support   (fixture route)
#   AI_IMPORT_ENABLED=1 + the AI payload storage env   (the job status screen
#   renders from the SSE stream, which only exists for an enabled import)
# `bash tool/run_gherkin.sh` documents the full boot recipe.

Feature: Wardrobe-gap resolution and look provenance on the AI-import preview

Scenario: A Pass-2 preview shows the look's provenance and resolves a gap in one tap
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  And an AI-import preview for job "job-1" carries a continuation look for "BEN" in scene 4
  And the same preview carries a wardrobe gap for "BEN" in scene 5 with candidates
  When I open the preview for job "job-1"
  Then I scroll the preview to the widget "ai-preview-outfit-origin-row-4-0"
  And I expect the widget "ai-preview-outfit-origin-row-4-0" to be present within 10 seconds
  Then I scroll the preview to the widget "ai-preview-gap-2-ben"
  And I expect the widget "ai-preview-gap-2-ben" to be present within 10 seconds
  When I pick the continuation candidate for the gap "2-ben"
  Then I scroll the preview to the widget "ai-apply-continuity-gap-2-ben"
  Then I expect the widget "ai-apply-continuity-gap-2-ben" to contain the text "Zivil-Look"

Scenario: A gap without script-derivable candidates offers no choice
  Given the app is launched in dev-auth mode
  And I am authenticated as a "costume_dept" user
  And an AI-import preview for job "job-2" carries a wardrobe gap for "CARLA" in scene 5 without candidates
  When I open the preview for job "job-2"
  Then I scroll the preview to the widget "ai-preview-notice-0"
  Then I expect the uncertainty notice at index 0 to be present within 10 seconds
  And I expect no widget "ai-preview-gap-3-carla" to be present within 10 seconds
