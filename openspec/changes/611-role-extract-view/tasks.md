<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

# Tasks: role-extract view (issue #611)

## 1. Backend cross-link

- [x] 1.1 Open the backend issue for the per-character appearances read
      model (`GET /v1/characters/{id}/appearances` + projection index on
      `(character_id, scene_number)`) — backend issue **#621**, cross-linked.

## 2. Frontend navigation seam (degraded)

- [x] 2.1 `lib/features/characters/role_extract_screen.dart` —
      `RoleExtractScreen` with the documented degraded pass-through
      (character detail as today; TODO(#611) swap point).
- [x] 2.2 `characters_screen.dart` — Cast character row tap pushes
      `RoleExtractScreen` with the stable route key
      `role-extract-<characterId>`.

## 3. Spec & design docs

- [x] 3.1 `docs/design/screens/role-extract.md` — new screen spec (Soll
      Salt layout, degraded state documented).
- [x] 3.2 `docs/design/screens/cast-view.md` — navigation row: character
      tap now opens the role extract.

## 4. Tests

- [x] 4.1 Widget tests: Cast tap pushes the role extract; degraded parity
      (detail content under the extract route) — characters_screen_test.
- [x] 4.2 Gherkin: `features-spec/role_extract.feature` (@pending) +
      `whenOpenRoleExtract` step registered in the runner config.

## 5. Follow-ups (deferred)

- [ ] 5.1 When backend #621 ships: regenerate the Dart client, swap
      `RoleExtractScreen.build` to the generated appearances type (extract
      rows in script order + costume chips, deep links into scene
      detail/costume affordances), bounded-retry reconciliation, l10n
      de/en keys, add the mock-appearances widget tests, promote the
      @pending Gherkin scenario.
