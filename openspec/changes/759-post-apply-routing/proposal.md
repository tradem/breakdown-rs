<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# 759 — Post-apply routing and refresh (Flutter AI import)

## Why

Issue #759 reported the tail of the "299 Erlösung" import test as an
enhancement with a bug component:

1. the apply's only feedback was an 18×18 spinner *inside* the submit button,
2. a successful apply left the user on the review screen, and the only
   affordance led **back to the imports list**,
3. the imported episode and its scenes only appeared after an app restart —
   post-apply cache invalidation covered `episodesListFetch` +
   `blocksListFetch` (the #666 fix) but not the scenes, the season-script
   composition or the shell's scopes.

## Drift check (what was already shipped)

| Point | State at the start of this change | Owner |
|---|---|---|
| 1 — visible apply progress | **Done.** `ApplyProgress` over the dedicated `GET /v1/ai-import/jobs/{id}/apply-events` stream, rendered by the screen-level `AiApplyProgressCard` (indeterminate bar before the first frame, then the determinate row counter, the `applying`/`finalizing` stage line and the coarse ETA), plus the #800 run identity and the re-apply confirmation | #762 (PR #798), #800 (PR #801) |
| 2 — data for the destination | **Done on the wire.** `ApplyAiImportResponse.applied_episodes` and `AiImportJob.applied_episodes` (`id`, `number?`, `name?`, `applied_count`) | #763 (backend) |
| 2 — routing, 3 — refresh | **Open.** Only the hierarchy lists were invalidated; the outcome card's button popped back to the jobs list | — |

The per-row stage labels the issue lists ("Episoden anlegen → Szenen
anlegen → …") do not exist on the wire (the backend's `ApplyStage` is
`applying | finalizing`); the honesty rule of #664 forbids fabricating them,
so the card keeps the stage granularity the server actually publishes.

## What this change does

### Scope of the fix

- **Routing.** On a successful apply the app resolves the target episode from
  the response (`episode_id` of the request first, then the biggest
  contribution, ties in server order; a schedule apply has none), switches the
  sticky episode scope (which cascades the block scope — #765), sets the active
  season when it differs, selects the Script destination and pops the import
  stack. The Script view resets its own nested navigator to its root route, so
  a detail pushed before the apply cannot hide the imported rows.
- **Honest degradation.** A target that cannot be resolved (no applied episode,
  or a season / episode number the read caches do not hold) keeps the review
  screen with the full outcome card and an explicit hint. No invented number,
  no network read on the navigation path, no half-navigation.
- **Report carried over.** `PostImportReport` (keepAlive provider) holds the
  apply's outcome, its skipped day groups, every `unapplied_outfits` row with
  its reason and the OTHER episodes of a multi-episode document with their row
  counts. The Script view renders it as a dismissible card — the episode scope
  hides the other episodes' rows, so naming them is the only thing that keeps
  the user from believing the import stopped where it opened.
- **Refresh (the defect).** The success path invalidates `episodesListFetch` +
  `blocksListFetch` (retained), `scenesListFetch` for every episode the
  response names (the whole family when it names none), their TTL staleness
  memos, and the season-script composition.

## Non-goals

- No backend change: the wire already carries `applied_episodes` (#763).
- No per-row stage labels (not on the wire; #664's honesty rule).
- No offline queueing of the apply.

## Affected artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`lib/features/ai_import/import_jobs/post_import_report.dart`, `…_card.dart`) | new | target choice, resolution, navigation, report provider + banner |
| `lib/features/ai_import/import_jobs/apply_controller.dart` | changed | post-apply invalidation (scenes, staleness memos, season script) |
| `lib/features/ai_import/import_jobs/apply_screen.dart` | changed | submit handler routes on success, unresolved hint, shared outcome copy |
| `lib/features/shell/script_tab_screen.dart` | changed | report card + navigator reset on a report |
| `lib/l10n/app_{de,en}.arb` + generated | new keys | report card + unresolved hint (de template, en catalog) |
| `post_import_report.g.dart` | regenerated | `build_runner` (`@Riverpod`) |
| `vendor/breakdown_api/` | unchanged | `backend/openapi.yaml` untouched |
| `pubspec.yaml` | unchanged | no new dependency |

## Tests

- Tier 1: `pickAppliedTargetEpisode` (reviewer target, biggest contribution,
  server-order ties, schedule apply → none) and the shared outcome copy.
- Tier 2: successful apply leaves the preview, selects Script with the imported
  episode in scope, publishes the report (additional episodes named) and
  re-runs the scene + script seams (counting overrides); a partially applied
  response keeps its unapplied rows reachable and dismissible; a report resets
  the destination's nested navigator; an unresolvable destination keeps the
  review screen with the outcome card, the hint and untouched scopes (decided
  variant: stay, see the implementation notes).
