<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Tasks: 538-ai-transparency-frontend

## 1. Foundations

- [ ] 1.1 Scene cache column `SceneCacheRows.sourceJson` (nullable text, wire
      JSON verbatim) in `lib/data/cache/hierarchy_cache.dart`; v8 → v9
      `from < 9` migration branch (`m.addColumn` for the nullable column);
      `hierarchy_cache_dao.dart` `_companion`/`_toSceneView` serialize /
      deserialize through `SceneSource.serializer`.
- [ ] 1.2 Pure provenance helpers (unit-testable, no Flutter): parse
      `SceneSource?` / `ShootingDaySource` into `AiProvenanceVariant`
      (`manual` / `aiExtracted` / `absent`) via the oneOf variant value.

## 2. Point-of-interaction disclosure

- [ ] 2.1 Import submit screen: persistent disclosure card above the submit
      button (key `ai-import-disclosure`), de/en ARB keys.
- [ ] 2.2 Widget test: card visible before submit; submit flow unchanged.

## 3. Preview + apply acknowledgment

- [ ] 3.1 Preview screen: "AI-extracted content — review carefully" banner
      (key `ai-preview-ai-banner`) above the typed payload body; honest note
      that the payload carries no machine-verified confidence values.
- [ ] 3.2 Apply card: review checkbox (key `ai-apply-review-checkbox`)
      gating the submit button; unchecked = disabled; selection summary
      adjacent.
- [ ] 3.3 Widget tests: banner present; checkbox gates dispatch.

## 4. Provenance badges

- [ ] 4.1 Shooting-days tile: `some(AiExtracted)` → badge chip next to the
      label (key `shooting-day-ai-badge-<id>`).
- [ ] 4.2 Scene tiles + scene detail: scene `source_` badge
      (key `scene-ai-badge-<id>`); scene-detail shooting-days section and
      schedule picker rows day badge.
- [ ] 4.3 Soll/Ist board: day `source` badge in the day title row.
- [ ] 4.4 Widget tests for each surface (badge present / absent on Manual /
      absent on `null` legacy rows).

## 5. About AI screen + About dialog doorway

- [ ] 5.1 `AiDisclosureScreen` with six content blocks; reads provider/
      model naming from the configured `AiConfigView` (honest degradation
      when none configured); screen spec + Salt wireframe in
      `docs/design/screens/about-ai.md`; glossary rows.
- [ ] 5.2 About dialog AI ListTile → push doorway.
- [ ] 5.3 Widget tests + goldens: screen blocks, doorway push, degraded
      naming state.

## 6. AI-config literacy helper

- [ ] 6.1 Admin-facing AI-literacy helper card above the forms
      (key `ai-config-literacy`).
- [ ] 6.2 Widget test + golden refresh for the config screen.

## 7. Spec deltas + gates

- [ ] 7.1 Delta specs `flutter-ai-import-workflow`, `flutter-app-dialogs`,
      `flutter-ai-config` under this change.
- [ ] 7.2 `dart format` / `flutter analyze` / `breakdown_lints` runner /
      `flutter test --coverage` gates; ARB key parity; gitleaks.
