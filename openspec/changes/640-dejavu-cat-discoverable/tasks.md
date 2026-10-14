<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Tasks: 640-dejavu-cat-discoverable

## 1. Design (first, per PO sequencing decision)

- [x] 1.1 Record the PO decision (Option 4 — splash + empty-surface
      visitor + Settings gallery) in `proposal.md`
- [x] 1.2 Update `docs/design/glossary.md` (déjà-vu cat copy keys +
      `settings.easterEggsPreview*`)
- [x] 1.3 Update `docs/design/screens/settings.md` (gallery section,
      wireframe, semantics, states, interactions, tests)
- [x] 1.4 Update `docs/design/screens/seasons-home.md` (cat visitor on
      the empty state)
- [x] 1.5 `scripts/check-design-diagrams.sh`: all PlantUML blocks compile

## 2. Implementation

- [x] 2.1 Wrap the seasons home empty state in `DejaVuCatOverlay`
- [x] 2.2 Add the Easter-eggs gallery (per-egg preview cards) to
      `SettingsScreen`; previews bypass only the October gate, honor the
      per-egg switch + "remove animations"
- [x] 2.3 ARB catalogs (de/en): `settingsEasterEggsPreview`,
      `settingsEasterEggsPreviewSubtitle`, updated déjà-vu cat subtitle;
      `flutter gen-l10n`

## 3. Tests

- [x] 3.1 Settings: gallery visibility (month-independent), per-egg
      switch gate, remove-animations static pose
- [x] 3.2 Seasons: October visibility, dormancy outside October,
      egg-switch gate, CTA hittability, remove-animations static pose,
      October golden; suite pinned to a non-October cat clock
      (month-independence)
- [x] 3.3 Re-baseline settings goldens (gallery rows added)

## 4. Validation

- [x] 4.1 `dart format --set-exit-if-changed .`: clean
- [x] 4.2 `flutter analyze`: clean
- [x] 4.3 `flutter test`: 1579 passed
- [x] 4.4 `breakdown_lints` custom runner: no violations
- [x] 4.5 `tool/check_glossary_catalog.py`: catalogs in parity
- [x] 4.6 OpenAPI drift: `backend/openapi.yaml` untouched — no client
      regen required
