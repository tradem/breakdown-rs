<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Tasks: Flutter Decision Model config UI, 5-star review ratings, and low-score preview filter (issue #723)

## 1. Decision Model Configuration & Hand-off Store

- [ ] 1.1 Extend `AiImportHandoffStore` to retain optional decision-scoped `ProviderCredentialReference` entries per provider.
- [ ] 1.2 Extend `AiConfigDraftData`, `AiConfigScreenState`, `AiConfigController`, and `AiConfigScreen` with the optional Decision Model provider/model pickers and the "Use same API key as extraction" toggle.

## 2. 5-Star Rating Widget, Preview/Apply Wiring & Low-Score Filter

- [ ] 2.1 Create `AiScoreStars` (`1..5 ★` from `0.0..=1.0`, empty on `null`) in `lib/design/components/` and register icons/copy keys in `docs/design/glossary.md`.
- [ ] 2.2 Render Scene Score, Synopsis Score, and Shooting Day Score stars in `AiPreviewScreen` (`_PreviewRowCard`) and Shooting Day Group Score stars in `AiApplySection`.
- [ ] 2.3 Add the `All scenes` / `Low score ≤ ★★★` filter chip bar to `AiPreviewScreen` and update EU AI Act banner copy in `lib/l10n/app_{de,en}.arb`.

## 3. Verification

- [ ] 3.1 Unit tests for `AiImportHandoffStore` and `AiConfigController` (same-key vs. separate-key flows).
- [ ] 3.2 Widget + golden tests for `AiScoreStars`, scored vs. unscored preview/apply cards, and low-score filtering.
- [ ] 3.3 `dart format`, `flutter analyze`, `breakdown_lints`, and `check_glossary_catalog.py` green.
