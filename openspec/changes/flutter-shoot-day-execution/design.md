<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design: Shoot-Day Execution

## 1. Blocker restated (binding)

The route family is server-implemented and router-mounted
(`backend/crates/api/src/handlers/mod.rs::routes()`:
`/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots` … plus
notes, continuity-photos, and `/shooting-days/{id}/wrap`) but absent
from the checked-in `backend/openapi.yaml`, which the client drift-
checks against. Consequence (unchanged from the Phase 2 finding): the
generated Dart client cannot express these calls, and by the
never-retype rule nothing below may be implemented until the contract
catches up. All tasks in `tasks.md` are gated on Task 0.

## 2. Intended UX (spec'd now, built when unblocked)

### 2.1 Day board (`SceneShootsScreen`, day context from Phase 2)

```
ShootingDay (date, label, order among the episode's days)
├── planned sequence: SceneShoot cards
│     (#scene — is_schedule_set, status, actual position)
├── Ist strip: started/finished/skipped chips, actual order vs planned
├── per-shoot actions: start, finish, skip, replan (version echo)
├── notes: comment list (add/edit/remove) on the shoot card
└── wrap button (guarded; shows finality copy from D3)
```

- All commands post the acted-on read DTO's ids + `version`
  (optimistic-lock echo); optimistic-after-2xx row edits with the
  shared bounded reconciliation, exactly the reference discipline.
- Ist semantics (moved/missing/skipped/reshot, `final` once
  `wrapped_at` is set) render from the projection only (D2).
- Notes are free text with an author line from the read model; edits
  carry the note id + aggregate version.

### 2.2 Continuity capture

Reuses the Phase 2 capture pipeline (point-of-use camera rationale,
isolate prepare, raw-bytes upload) against the continuity route,
binding to the `SceneShoot` (day + scene context) with an optional
costume link picked from the season's costume read DTOs. List renders
the shoot's continuity photos; unlink is confirm-first. AUTHZ-GATE:
the `upload_continuity_photos` capability check (or the season photo
policy mirror) before every upload/unlink call, `// AUTHZ-GATE:`
annotated, 403 narrative pre-network.

### 2.3 Gherkin (designated critical scenarios, on device)

- `features-spec/continuity_photo_capture.feature` — gate → capture →
  upload → variant Ready → thumb appears (projector-lag window
  visible and bounded).
- `features-spec/soll_ist_execution.feature` — plan → start → actual-
  order rearrange → finish → skipped flag; the day becomes final on
  wrap (`wrapped_at`).

Both run via `flutter_gherkin` in CI's on-device tier (deterministic
test API doubles for the camera and clock).

## 3. Test tiers (spec'd now)

- Unit: command-request builders (ids + version echoes), read-model
  → Ist-state renderer (pure, goldens of the state functions),
  reconciliation parity on the day-board rows.
- Widget + golden: the board across {light,dark} × {android,macos};
  per-status cards; wrap confirm; continuity gallery reuse; denial
  narratives; skip/finish optimistic + conflict (409) states.
- Gherkin: the two features above.
- Integration: day-board smoke — plan two shoots, start/finish one,
  skip one, wrap; verify finality (no further mutation actions).
