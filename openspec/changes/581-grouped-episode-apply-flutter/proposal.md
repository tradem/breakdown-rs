<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# 581 (follow-up) — Flutter grouped episode apply screen

## Why

The backend portion of #581 (PR #584) extracts `Ep.: <n> (<Titel>)` markers
into `DraftScene.episode` preview metadata and accepts per-group
`episode_groups` targets on the apply request — but the Flutter app still
renders a flat row list and dispatches every scene into the one picked
episode. This change lands the frontend: the apply screen groups rows by
draft episode and lets the reviewer map each group to an existing or a
to-be-created episode. The single-episode flow stays intact for schedule
imports, flat scripts, and rows without episode metadata.

## Decisions (user-confirmed)

1. **Default per-group target: create-new, pre-filled from the heading.**
   The backend requires a target for every group the preview carries
   (`MissingEpisodeGroup`), so every group is pre-mapped to
   `create { number, name }` from the marker — matching the device-testing
   expectation that episodes named in the screenplay are created/assigned
   automatically. The reviewer can switch any group to an existing episode.
2. **Group ref derivation mirrors the backend `group_key()` exactly:**
   `ep:<n>` when the marker carried a number, else `ep-t:<trimmed title>`
   — byte-identical refs, or the apply 422s. A title-only group (no
   number) still needs a number for the wire (`EpisodeTargetOneOf1.number`
   is required): the group's create target stays incomplete and the submit
   button stays disabled until the reviewer enters one.
3. **Group-target edits count into `edit_distance`.** A group whose target
   deviates from its seeded create-default (switched to existing, or
   number/name changed) is an edit — `accept_as_is` must stay a truthful
   statement about the review.
4. **Merged previews are ungrouped.** `MergedScene` rows act on existing
   `SceneView`s and carry no draft episode metadata — they keep the
   single-episode flow.

## Scope (frontend-only)

- `apply_controller.dart`: `PreviewRow.episode`; `EpisodeGroupTarget`
  (existing/create); seeded default targets per group ref;
  `setGroupTarget`; `episodeGroups` on the built request; `canApply` also
  requires every create target to carry a number and forbids two groups
  creating the same number (client-side mirror of the 422, before the wire).
- `preview_screen.dart`: script rows render under per-group headers with a
  target selector (existing via `showEpisodePicker`, create via an inline
  number/name editor); unmarked rows under the picked-target header.
- `apply_screen.dart`: the apply card summarizes each group's target (EU AI
  Act gate — the reviewer sees which episode each group lands in at the
  dispatch point); `episode.number-already-exists` gets its own copy branch.
- l10n: de (template) + en keys for group headings, target labels, the
  create editor, and the number validation copy.
- Tests: unit (group-ref derivation, target defaulting, request building,
  edit-distance), widget (grouped headers, selector flows, submit gating,
  number-required gate, single-episode fallback), golden drift check.

## Out of scope

- No backend change; `backend/openapi.yaml` does not move.
- No auto-apply: the explicit review acknowledgement stays the gate.
