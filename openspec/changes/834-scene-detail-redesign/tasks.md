<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks — 834

## 1. Backend — scores (PR 1)

- [x] 1.1 `SceneDetails.scene_score` / `synopsis_score` (`Option<f32>`,
      `#[serde(default)]`) — additive on the event/command wire (ADR-021).
- [x] 1.2 `DraftScene::scene_details()` carries the draft's scores into the
      apply payload.
- [x] 1.3 Migration `20261107000001_projection_scene_scores`: two nullable
      `double precision` columns on `projection_scene` (+ down).
- [x] 1.4 Scene projector: write the scores on `SceneCreated`; the
      `SceneDetailsUpdated` statement does NOT touch them (provenance is
      preserved).
- [x] 1.5 Read adapters (`queries/scene.rs`, `queries/shooting_day.rs`):
      select + map the columns; `SceneView.scene_score` /
      `SceneView.synopsis_score` on the wire.
- [x] 1.6 Tests: core serde round trip (pre-#834 payload replays unscored;
      scored payload round-trips; `scene_details()` carries scores),
      projector persistence test, wire-fixture additive allowlist, Tier-4
      apply round trip (`ai_script_apply_scene_scores.rs`).
- [x] 1.7 `UPDATE_OPENAPI=1` regen of `backend/openapi.yaml` (committed diff),
      Dart client regen via `scripts/regen-client.sh`
      (`breakdown_api` 1.3.0 → 1.4.0), crate version lockstep
      (`core` 0.64.0, `infra` 0.74.0, `api` 0.62.0), CHANGELOG.

## 2. Frontend — visual shell (PR 2)

- [ ] 2.1 ARB keys: `sceneDetailTitle` („Szene {number}“), header/synopsis/
      editor copy; de + en.
- [ ] 2.2 `SectionCard` in `lib/design/components/` — no shape borders, token
      spacing/radius; the three detail sections use it, `initiallyExpanded`
      false, counts in the header.
- [ ] 2.3 App bar `Szene {n}`; content header block: numeral + location +
      metadata chip row (mood #721, script day, geplant/ungeplant, AI badge
      from `SceneView.source`).
- [ ] 2.4 Synopsis section: full summary, AI badge, honest empty state.
- [ ] 2.5 Goldens re-baselined; no `Divider` in any state (widget test).

## 3. Frontend — ratings + editor (PR 2)

- [ ] 3.1 Ratings in the synopsis section via `AiScoreStars`
      (`sceneScore`/`synopsisScore`; `null` renders nothing).
- [ ] 3.2 `ScenesController.updateDetails` (AUTHZ-GATE + version echo +
      optimistic overlay + bounded refetch) over
      `SceneRepository.updateSceneDetails`.
- [ ] 3.3 Scene editor sheet: number, location, mood (canonical chips +
      free-text fallback, unrecognized stored value stays selectable), script
      day, summary; `concurrency.version-mismatch` localized retry narrative.
- [ ] 3.4 Widget tests: editor fields, version echo, mood preservation.

## 4. Docs (PR 2)

- [ ] 4.1 `docs/design/screens/scenes.md` — detail-screen rewrite + Salt
      wireframe; `docs/design/glossary.md` entries; `README.md` SectionCard
      note.
