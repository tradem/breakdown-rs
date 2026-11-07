<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 834 — Scene detail redesign: compact header, divider-free sections, persisted scores, editable fields

## Why

The scene detail screen is the app's most-used detail surface and still wears
the foundation layout: the whole summary sentence as the app-bar title, three
`ExpansionTile`s that draw Material-3 divider lines and all open expanded, no
editable field at all, and the Decision-Model scores exist only in the import
preview. The PO wants a modern Material-3 surface (Spotify as the reference
for *feel*, not chrome), real persisted ratings, and full editability
(PO decisions 1–3 in the issue).

## What changes (two stacked PRs, not five)

| PR | Scope | Base |
|---|---|---|
| 1 `feat(scenes): persist the Decision-Model scene scores` | Backend: scores into `SceneDetails`/`SceneCreated`, projection columns + migration, `SceneView` fields, OpenAPI + Dart client regen, tests | `main` |
| 2 `feat(scenes): redesign the scene detail screen` | Frontend: app-bar `Szene {n}`, header block, `SectionCard` (no dividers, collapsed by default), synopsis section with AI badge + ratings, scene editor sheet (all fields, version echo) | PR 1 |

## Decision 2 — scores (PR 1)

`DraftScene.scene_score` / `synopsis_score` (`f32`, issue #722) ride
`DraftScene::scene_details()` into `SceneDetails` (`serde(default)`, additive
per ADR-021) and the `SceneCreated` event. The projector writes two new
nullable `double precision` columns on create and **preserves** them on
`SceneDetailsUpdated` (a detail edit must not erase the recorded provenance;
re-scoring and user-editable ratings stay out of scope). `SceneView` exposes
`scene_score` / `synopsis_score` (MINOR-additive, wire-fixture allowlist +
OpenAPI + `breakdown_api` 1.3.0 → 1.4.0). Honest absence: `NULL` for manual
scenes and failed scoring passes — the client renders nothing, never
fabricated stars.

## Decisions 1 + 3 (PR 2)

- **Header:** `Szene {n}` in the app bar; the identity block (large numeral,
  location, metadata chips incl. the `AiExtracted` provenance badge from
  `SceneView.source`) as the first content element. No `SliverAppBar` — it
  must not fight #824.
- **Sections:** a reusable `SectionCard` (`lib/design/components/`) replaces
  the `ExpansionTile` chrome: no shape borders (no divider lines), collapsed
  by default, counts stay in the header. Separation via cards + `AppSpacing`,
  no `Divider()` anywhere.
- **Synopsis:** own section with the full `summary`, the AI badge, the ratings
  (`AiScoreStars`, #723) and an honest „Keine Synopsis" empty state.
- **Editing:** one „Szene bearbeiten" sheet for number, location, mood
  (canonical chips + free-text fallback that never destroys an unrecognized
  stored value), script day and summary — dispatched through
  `SceneRepository.updateSceneDetails` with the `version` echoed from the read
  DTO (#473 doctrine), optimistic overlay + bounded refetch, error copy keyed
  on `code` (`scene.*` / `concurrency.version-mismatch`).

## Risks

- The apply `Update` decision re-sends draft details whose scores the
  projector intentionally ignores — documented, not a data risk.
- Scene number editing has no uniqueness backstop; the sheet warns in copy,
  a uniqueness invariant is a separate backend issue (cross-aggregate
  doctrine).
