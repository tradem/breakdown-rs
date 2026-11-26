<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — issue #969

## 1. Schedule preview — the `ROLLEN` legend

- [x] 1.1 `_CastLegendSection` in
      `lib/features/ai_import/import_jobs/preview_screen.dart`: `Card` +
      `ExpansionTile`, `initiallyExpanded: false`, ICU-plural title, hint
      subtitle; rendered under the payload header for the schedule variant only.
- [x] 1.2 `_CastLegendEntryRow`: tabular-figure code, character name, modifier
      badge; entries ordered numerically (`_sortedLegendEntries`).
- [x] 1.3 Absent/empty legend renders `SizedBox.shrink` — no placeholder card.

## 2. Rows — cast pills, modifier badges, shot-suffix chip

- [x] 2.1 `_RoleModifierBadge`: one pill per modifier from M3 container roles
      (`secondaryContainer` / `tertiaryContainer` / `primaryContainer`), a
      `Semantics` label carrying modifier + meaning, `none`/absent/unknown render
      nothing.
- [x] 2.2 `_CastPill` + `_scheduleRowChips`: one pill per resolved cast member,
      outlined `_ShotSuffixChip` for a verbatim `shotSuffix`; blank values are
      absence, never an empty chip.
- [x] 2.3 Pre-merge schedule rows (`_InfoRowCard`) render the chips under the
      label; merged rows (`_PreviewRowCard` → `_MergedScheduleRows`) render one
      `Wrap` line per schedule row (verbatim `rowRef` + suffix chip + cast pills).

## 3. AI config — the #968 EU vision providers

- [x] 3.1 Verified: picker, reachability probe, provider health and credentials
      are catalog/wire-key driven → `scaleway`/`ovhcloud`/`nebius` need no screen
      change (test: `ai_config_screen_test.dart`, one wire-key health probe per
      provider; picker lists all three from the catalogue).
- [x] 3.2 No curated-model VISION signal exists on the wire (`ModelInfo` carries
      no such field) → model dropdown untouched; gap recorded on #968.

## 4. l10n

- [x] 4.1 Seven keys in `app_de.arb` + `app_en.arb`
      (`aiPreviewCastLegendTitle` [ICU plural], `aiPreviewCastLegendHint`,
      `aiPreviewRoleModifierDummy|VoiceOnly|ExtraOt`,
      `aiPreviewRoleModifierSemantics`, `aiPreviewShotSuffixSemantics`);
      `flutter gen-l10n` output committed; de/en parity clean.

## 5. Tests & goldens

- [x] 5.1 `test/features/ai_import/preview_apply_test.dart`: five widget tests
      (absent legend, collapsed + numeric order + vocabulary, empty legend,
      pre-merge chips, merged Scene-37 double row incl. accessible names).
- [x] 5.2 Four goldens: `ai_preview_cast_legend_{light,dark}_android.png`,
      `ai_preview_merged_cast_{light,dark}_android.png`.
- [x] 5.3 `test/features/ai_import/ai_config_screen_test.dart`: four widget tests
      for the #968 providers.

## 6. Documentation

- [x] 6.1 `docs/design/screens/ai-import-jobs.md`: new section
      "Preview & Apply — the `ROLLEN` legend, cast chips and shot suffixes".
- [x] 6.2 This OpenSpec change (proposal + delta spec + tasks).
- [x] 6.3 Version bump `0.5.0-alpha.1+156 → 0.5.0-alpha.2+157` in
      `frontend-flutter/pubspec.yaml` + the matching `## [Unreleased]` entry in
      `frontend-flutter/CHANGELOG.md` (ADR-033: `pubspec.yaml` is the single
      version source, `+N` strictly monotonic).
