<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: Core Costume Domains

## 0. Blocker tracking (no implementation)
- [ ] 0.1 File/triage the backend issue: scene-shoot + continuity-photo
       + wrap + JSON-report routes are served by the backend router but
       absent from the checked-in `backend/openapi.yaml` (never edit the
       spec from the client change; never retype the DTOs client-side) —
       filed as GitHub issue #333
- [ ] 0.2 Follow-up change slug `flutter-shoot-day-execution` is
       registered in this change's proposal (roadmap traceable); each
       unblock gate task is annotated with its issue number

## 1. Data layer
- [ ] 1.1 Drift migration: `costumes`, `characters`, `shooting_days`
       tables (projection-shaped snapshots; costume rows embed
       `details`/`photos`; migration test)
- [ ] 1.2 Extend `data/costume_repository.dart` — `listBySeason` /
       `get` (cache-backed, snapshot rules), `assign`, `unassign`
       (`VersionRequest` = `version` only, per the corrected schema
       from backend issue #336), `addDetail`,
       `updateNotes`; overlay reducer helpers for the costume row
       including the version-fence clear condition
       (`projection.version >= acknowledgedVersion`)
- [ ] 1.3 Extend `data/character_repository.dart` — `listBySeason`,
       `create`, `updateContact`, `updateMeasurements` (full
       replacements, version echo)
- [ ] 1.4 Extend `data/photo_repository.dart` — raw-bytes `upload`
       (content-type header), `getBytes`, `delete`, and
       `watch(costumeId)` (bounded-backoff costume refetch;
       **terminal condition = every variant of every photo is
       `Ready|Failed`** — not the first terminal variant; **bounded as
       a whole pass** by `PHOTO_WATCH_MAX_ATTEMPTS` refetches or
       `PHOTO_WATCH_MAX_ELAPSED` elapsed, emitting `watch_expired` on
       expiry and stopping; subscriber-count lifecycle)
- [ ] 1.5 Extend `data/shooting_day_repository.dart` — `listByEpisode`,
       `create` (append `order_key`, `Manual`), `update`
       (single-intent reorder/reschedule/rename incl. `date: null`),
       `archive`
- [ ] 1.6 Unit tests: every method Ok AND Err; cache untouched on
       failure; watch state machine with fake scheduler (bounded
       attempts/elapsed, terminal stop incl. the mixed case one
       variant `Ready` + one `Pending`, expiry → `watch_expired` with
       no further calls, unsubscribe stop — no wall-clock);
       assign/unassign overlay unit tests asserting the version fence
       (stale projection retains the overlay)

## 2. AUTHZ-GATE seam
- [ ] 2.1 `lib/auth/membership_gate.dart` — shared capability gate
       mirroring the season-scoped photo policy (annotated
       `// AUTHZ-GATE:`), extensible per gated handler call
- [ ] 2.2 Unit tests: allow/deny per capability set; strict unknown
       capability rejection inherited from the Phase 1 parser; denial
       narrative mapping

## 3. Photos pipeline
- [ ] 3.1 `features/photos/prepare.dart` — pure resize/encode core
       (longest-side cap, content-type mapping) + post-encode size
       measurement with iterative reduction and a local
       `photo_too_large` result when the budget cannot be met (so 413
       stays defensive only) + `compute` isolate wrapper; unit tests
       with tiny fixtures (overflow/format-reject, oversized-after-
       re-encode → `photo_too_large`, reduction loop converges)
- [ ] 3.2 `image_picker` integration — capture intent only at point of
       use; pre-permission rationale dialog (remembered flag);
       denial + revoked + unavailable copy branches
- [ ] 3.3 Gallery widget: `CostumeView.photos` grid (2/3/4 columns by
       token breakpoints), variant status chips, in-memory LRU
       bytes-cache `ImageProvider`
- [ ] 3.4 Widget tests + goldens: variants (Pending spinner / Ready
       thumb / Failed explanation + capture-again), 413/415/403 copy,
       delete confirm flow; camera-permission scenarios (denied,
       revoked-between-sessions, granted) with faked picker

## 4. Costumes feature
- [ ] 4.1 `features/costumes/` — list + create (empty-body contract;
       create sheet chains to first detail), family controller on the
       shared reconciliation
- [ ] 4.2 Costume detail screen — details list (+ add-detail form with
       category picker from the season categories projection), notes
       editor, assign/unassign (character picker, version echo)
- [ ] 4.3 Unit + widget + golden tests: create/assign/unassign/
       addDetail/updateNotes per spec scenarios (conflicts, empty,
       stale, projector-lag exhaustion)

## 5. Characters feature
- [ ] 5.1 `features/characters/` — list (category chip), create,
       detail with contact + measurements editors (prefilled,
       full-replacement PATCH)
- [ ] 5.2 Scene detail additions — assigned characters (read-DTO
       join), assign/unassign with scene version echo
- [ ] 5.3 Unit + widget + golden tests: per spec scenarios (409
       conflict, unknown category strict-reject, optimistic rollback)
- [ ] 5.4 Strict-parse test for unknown `CharacterCategory` variants

## 6. Shooting days feature
- [ ] 6.1 Episode context entry — `features/shooting_days/` list
       (server order), create, single-intent updates (reorder /
       reschedule / unschedule / rename), archive
- [ ] 6.2 Scene detail additions — scheduled days (read-DTO join) +
       schedule/unschedule pickers (day DTO ids, scene version echo)
- [ ] 6.3 Unit + widget + golden tests: order fidelity (no re-sort),
       date null-vs-absent semantics, conflicts, archives

## 7. Gherkin (Tier 3 — designated critical scope)
- [ ] 7.1 `features-spec/costume_assignment.feature` — create → assign
       → optimistic row → projection refresh; role-denial scenario
       with request-counter proof of no network call
- [ ] 7.2 Run via `flutter_gherkin` on device in CI (manifest entry)

## 8. Integration + housekeeping
- [ ] 8.1 Integration smoke (emulator, dev-auth): season → costume
       create + detail → assign → capture (picker faked) → upload →
       thumbnail appears after variant `Ready`
- [ ] 8.2 Both platforms: macOS variants for new screens (focus/hover,
       Escape, column widths); goldens {light,dark}×{android,macos}
- [ ] 8.3 SPDX headers; format/analyze/breakdown_lints clean; coverage
       + coverde gate; gitleaks (no secrets — picks are user-supplied)
- [ ] 8.4 `openspec` coverage audit: every scenario in the four
       spec deltas has a passing test
