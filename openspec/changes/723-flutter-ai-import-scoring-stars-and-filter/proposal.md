<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## Why

Issue #723 (depends on #721 and #722): Once the backend supports dedicated Decision Model configuration and emits calibrated `scene_score`, `synopsis_score`, and `shooting_day_score` values on preview payloads (#722), the Flutter client needs:
1. A configuration UI in `AiConfigScreen` to pick a Decision Model provider/model and choose between reusing the extraction API key or binding a separate API key for split billing.
2. Intuitive **1–5 Star ratings (★☆☆☆☆ to ★★★★★)** in `AiPreviewScreen` and `AiApplySection` so reviewers can immediately gauge the quality of extracted scenes, TL;DR synopses, and shooting days.
3. A **low-score filter chip** in `AiPreviewScreen` to focus human attention on low-rated rows first during large screenplay imports.

## What Changes

- `lib/features/ai_import/ai_config/` & `lib/data/ai_import_handoff_store.dart`:
  - Add the optional **Decision / Scoring Model** configuration section in `AiConfigScreen` (provider selector for `neuralwatt`, `eurouter`, `openrouter`, or disabled; curated decision model selector).
  - Add the **"Use same API key as extraction"** toggle when `decisionProvider == extractionProvider` (default ON); when unchecked or when providers differ, support entering/retaining a separate decision credential reference in `AiImportHandoffStore`.
- `lib/design/` & `docs/design/glossary.md`:
  - Add a reusable Material 3 5-star rating widget (`AiScoreStars`) mapping `0.0..=1.0` to 1–5 stars (`< 0.30` -> 1★, `0.30..0.50` -> 2★, `0.50..0.70` -> 3★, `0.70..0.85` -> 4★, `>= 0.85` -> 5★) with visible label + accessibility semantics, rendering nothing when `null`.
- `lib/features/ai_import/import_jobs/preview_screen.dart` & `apply_screen.dart`:
  - Render **Scene Score**, **Synopsis (TL;DR) Score**, and per-row **Shooting Day Score** star ratings on `_PreviewRowCard`.
  - Render aggregated **Shooting Day Group Score** star ratings on each day-group decision row in `AiApplySection`.
  - Add a filter chip bar (`All scenes` vs. `Low score ≤ ★★★`) above the preview rows when scores are present, filtering only the visible list without removing rows from `AiApplyController`'s apply decisions.
  - Update the EU AI Act Art. 50 preview banner copy to explain machine-evaluated star ratings when scores are present while preserving the honest "no confidence values" note when scores are absent.

## Impact

- **EU AI Act Art. 50 transparency:** Star ratings are explicitly framed as machine-evaluated review aids that do not replace the mandatory human review acknowledgement checkbox.
- **Offline / Hand-off:** Separate decision credentials use the same opaque `ProviderCredentialReference` pattern in `AiImportHandoffStore` (no secrets stored locally).
- **Affected specs:** `specs/flutter-ai-config/spec.md`, `specs/flutter-ai-import-workflow/spec.md`, `docs/design/glossary.md`.
