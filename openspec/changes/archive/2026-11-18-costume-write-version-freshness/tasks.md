<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Tasks — Costume write version freshness (issue #473)

## Done

- **`lib/features/costumes/costumes_controller.dart`**:
  - New private `_resolveVersion(costumeId, fallback)` — resolves the freshest
    known aggregate version at command time: held overlay version → reconciled
    projection row (`costumesViewProvider`) → screen-passed fallback (max
    known, since overlays/projections are monotone and the backend guard is
    strict equality).
  - Wired into every write: `updateNotes`, `addDetail`, `assign` (first-
    assignment), `unassign`, and both legs of `_reassign` (the intermediate
    unassigned overlay carries the unassign ack, so the assign leg resolves to
    it — preserving the #454 sequence contract).
  - `costumeErrorCopy`: `concurrency.version-mismatch` (409) and
    `costume.version_conflict` now render "Changed elsewhere — pull to refresh
    and try again." (distinct narrative, req. #3); generic `domain.validation`
    deliberately not blanket-mapped.
- **`frontend-flutter/pubspec.yaml`**: version `0.3.0-alpha.14+23` →
  `0.3.0-alpha.15+24` (ADR-033 per-PR bump, #362).
- **Tier-2 regression tests**:
  - `test/features/costumes/costumes_screen_test.dart`: "stale snapshot echoes
    the freshest known version, not the captured one" — a captured v1 snapshot
    must echo the overlay ack v2 (this test failed pre-fix: echoed 1).
  - `test/features/costumes/costume_detail_screen_test.dart`: "second notes
    save echoes the ack version (no 422 loop)" (req. #2), "add detail after
    save echoes the ack version" (cross-command), "409 version-mismatch
    renders pull-to-refresh copy" (req. #3).
- **OpenSpec change** `costume-write-version-freshness`: proposal, design,
  delta spec (`flutter-costumes-screen`), tasks.

## Verified

- `dart format --set-exit-if-changed`: clean
- `flutter analyze`: clean
- `flutter test`: 993 passed (full suite)
- New regression "stale snapshot echoes the freshest known version": red before
  the fix (echoed 1), green after (echoes 2).
