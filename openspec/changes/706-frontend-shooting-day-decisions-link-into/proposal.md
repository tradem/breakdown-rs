<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash-flex (neuralwatt) -->

## Why

Issue #706 continuation: the backend half (extraction, preview metadata,
apply with day groups, the `link-into` endpoint) merged in PR #714 and the
regenerated `breakdown_api` client already ships every needed type
(`DraftShootingDay`, `ApplyShootingDayRequest`, `ApplyAiImportRequest.shootingDays`,
`ApplyAiImportResponse.skippedDayGroups`, `linkShootingDayInto`,
`ShootingDayView.source_/archived`). The frontend surfaces that machinery is
missing: script previews do not show the extracted shooting days, the apply
screen sends no `shooting_days` decisions (a script preview carrying day
groups is currently UNAPPLIABLE from the app — the backend answers
`409 ai-import.apply-missing-shooting-day-group`), the outcome card hides
`skipped_day_groups`, and the shooting-days screen offers no planned→actual
assignment. The day tiles already carry the AI provenance badge (issue #538).

**Settled decisions (user, this branch):**

1. **Scope:** frontend continuation only — backend untouched,
   `backend/openapi.yaml` unchanged (client regen not needed).
2. **Day-decision default:** accept-all pre-checked (mirrors rows defaulting
   to Create and costumes defaulting to accepted). The reviewer unchecks a
   day to leave its scenes unscheduled; the client always sends one decision
   per day group, so the backend's missing-decision gate never trips.
3. **Link-into target eligibility:** any same-episode day that is not the
   source itself, not archived, and not wrapped (backend rules plus archive
   exclusion) — merging two AI days stays possible, as the backend permits.

## What Changes

- `lib/features/ai_import/import_jobs/apply_controller.dart`:
  `draftShootingDayGroupRef` (byte-for-byte mirror of
  `DraftShootingDay::group_key`: `day:<n>` / `day-l:<label>`),
  `PreviewRow.shootingDay`, per-group day decisions (default accepted,
  explicit picks only in the map), `_dayEdits` counted into `editDistance`
  (a toggled day breaks `accept_as_is`, honestly), `buildShootingDays()`,
  the `shooting_days` request field (absent when the preview carries no day
  metadata), and error copy for
  `ai-import.apply-missing-shooting-day-group`.
- `apply_screen.dart`: per-day decision rows in the apply card (where the
  episode-group targets live, per the 2026-10-19 UX decision), a dispatch-
  point day summary line (EU AI Act gate), `skipped_day_groups` on the
  outcome card.
- `preview_screen.dart`: each script scene row renders its extracted day
  label; actionable rows thread `DraftShootingDay` into the apply state.
- `shooting_day_repository.dart`: `linkInto(id, targetId)` over
  `POST /v1/shooting-days/{id}/link-into/{target_id}`.
- `shooting_days_controller.dart`: `linkInto` command (AUTHZ-GATE, error
  routing, bounded refetch); `shootingDayErrorCopy` gains
  `shooting-day.target-wrapped` / `shooting-day.episode-mismatch`.
- `shooting_days_screen.dart` + widgets: "In echten Drehtag überführen"
  overflow action on AI-extracted, non-archived days; target-picker sheet
  over the episode's eligible days; success feedback with the response's
  `linked_scenes`.
- l10n: new de template + en catalog keys; `pubspec.yaml` version bump;
  CHANGELOG entry.

## Impact

- **CQRS boundary:** the day decisions ride the existing apply request
  (command payload, not projection lookups); the link-into picker reads the
  day list the screen already holds (the acted-on episode's projection).
- **Wrap finality:** the picker excludes wrapped targets; the backend's
  `409 shooting-day.target-wrapped` stays the authoritative refusal and is
  surfaced with its own copy.
- **Wire compatibility:** previews stored before #706 carry no day metadata
  → `shootingDays` stays absent → the request stays byte-identical to the
  pre-#706 client.
- **Affected specs:** `specs/flutter-ai-import-workflow` (day decisions in
  the review/apply flow), `specs/flutter-shooting-days-screen` (link-into
  action).

## Version Bumps

| Package | Previous | New | Reason |
|---|---|---|---|
| `frontend-flutter` | 0.4.0-beta.5+97 | 0.4.0-beta.6+98 | New feature: day decisions + link-into flow |
