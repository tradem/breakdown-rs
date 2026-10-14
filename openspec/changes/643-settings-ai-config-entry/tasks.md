<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (neuralwatt) -->

# Tasks: 643-settings-ai-config-entry

## 1. Design docs (before implementation, AGENTS.md §11)

- [x] 1.1 Update `docs/design/screens/settings.md`: wireframe, component
      table, interactions, states, tests for the AI-configuration entry.
- [x] 1.2 Update `docs/design/glossary.md` with the `settings.aiConfig` /
      `settings.aiConfigSubtitle` rows (icon `psychology_alt_outlined`).
- [x] 1.3 `scripts/check-design-diagrams.sh` compiles clean.

## 2. Implementation

- [x] 2.1 Add `settingsAiConfig` / `settingsAiConfigSubtitle` to the de
      (template) and en ARB catalogs; run `flutter gen-l10n`.
- [x] 2.2 Add the gated `_AiConfigEntryTile` to `SettingsScreen`'s
      general section: `activeBlockProvider` →
      `currentMembershipProvider(seasonId)` → visible iff
      `AsyncData && hasActiveCostumeRoleInSeason`; `// AUTHZ-GATE:`
      comment; push `AiConfigScreen`.

## 3. Tests

- [x] 3.1 Widget: entry hidden (no scope / pending / resolved denial),
      visible on an active costume-dept membership, ≥ 48×48 dp target,
      tap pushes `AiConfigScreen`.
- [x] 3.2 Golden pair for the visible entry (light + dark); existing
      Settings goldens unchanged (harness never sets an active scope).

## 4. Validation

- [x] 4.1 `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test` clean.
