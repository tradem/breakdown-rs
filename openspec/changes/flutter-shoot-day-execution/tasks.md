<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Shoot-Day Execution (Soll/Ist + Continuity) — BLOCKED

## 0. Unblock gate (blocking everything below)
- [ ] 0.1 Backend re-export lands the scene-shoot / continuity-photo /
       wrap routes in `backend/openapi.yaml` (tracked backend issue,
       Phase 2 change task 0.1)
- [ ] 0.2 `bash scripts/regen-client.sh`; commit the regenerated
       `vendor/breakdown_api/` tree; confirm the new DTOs
- [ ] 0.3 Verify the intended routes in the generated client match
       the router-served family from design.md D1 (no improvisation)

## 1. Data layer
- [ ] 1.1 Extend `data/scene_shoot_repository.dart` with the
       generated execution calls (plan/replan/get, start,
       actual-order, finish, skip, notes add/update/remove,
       continuity upload/list/unlink, wrap) — Result-typed, version
       echoes, `// AUTHZ-GATE:` on continuity calls
- [ ] 1.2 Drift table(s) for the day-board projection + migration
- [ ] 1.3 Unit tests: every command Ok/Err; optimistic-edit
       reducers; Ist-state renderer purity (flags/finality from read
       model only)

## 2. Day board
- [ ] 2.1 `features/scene_shoots/scene_shoots_screen.dart` — day
       board (planned sequence, Ist strip, per-shoot actions, wrap),
       controllers on the shared reconciliation module
- [ ] 2.2 Notes widget on the shoot cards; wrap confirm dialog with
       finality copy
- [ ] 2.3 Continuity strip reusing the Phase 2 capture pipeline
       (scene-shoot context, optional costume link)
- [ ] 2.4 Widget tests + goldens ({light,dark} × {android,macos});
       statuses, wrapped-day read-only state, 409 conflicts, denial
       narratives

## 3. Gherkin (designated critical scenarios)
- [ ] 3.1 `features-spec/continuity_photo_capture.feature` — gate →
       capture → upload → variant Ready → thumb appears
- [ ] 3.2 `features-spec/soll_ist_execution.feature` — plan → start
       → actual-order → finish; skip; wrap finality
- [ ] 3.3 Wire into the flutter_gherkin CI manifest

## 4. Integration + housekeeping
- [ ] 4.1 On-emulator smoke: plan two shoots → start/finish/skip →
       wrap → assert read-only finality
- [ ] 4.2 SPDX headers; lint/coverage/gitleaks gates clean
- [ ] 4.3 `openspec` coverage audit for
       `flutter-scene-shoots-screen`
