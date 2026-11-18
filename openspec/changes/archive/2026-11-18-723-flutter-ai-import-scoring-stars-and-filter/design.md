<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

# Design — 723 Flutter AI Import: Decision Model Config UI, 5-Star Ratings, and Low-Score Filter

## Decisions

### D1 — Decision Model Picker & Same-Key / Separate-Key Hand-off in `AiConfigScreen`
`AiConfigScreen` adds an optional **Decision / Scoring Model** section:
- Provider dropdown offering `None (Scoring disabled)`, `Neuralwatt`, `EURouter`, and `OpenRouter`.
- Model dropdown populated from the selected provider's curated decision models.
- When `decisionProvider == selectedProviderKey`, a checkbox **"Use same API key as extraction"** defaults to `true` (sending `decisionVaultKeyId = vaultKeyId`). When unchecked, or when `decisionProvider != selectedProviderKey`, `AiImportHandoffStore` retains a separate `decisionCredentials[providerKey]` reference so split-billing keys are remembered across edits without re-entry.

### D2 — 5-Star Rating Component (`AiScoreStars`) in Preview & Apply
`AiScoreStars` maps a normalized `0.0..=1.0` score to `1..5` stars:
- `>= 0.85` -> 5★ (`★★★★★`)
- `0.70 .. < 0.85` -> 4★ (`★★★★☆`)
- `0.50 .. < 0.70` -> 3★ (`★★★☆☆`)
- `0.30 .. < 0.50` -> 2★ (`★★☆☆☆`)
- `< 0.30` -> 1★ (`★☆☆☆☆`)
- `null` -> renders `SizedBox.shrink()` (no fabricated stars).
Rendered with a visible category label and semantic announcement on `_PreviewRowCard` (Scene Score, Synopsis Score, Shooting Day Score) and in `AiApplySection` (Shooting Day Group Score).

### D3 — Low-Score Review Filter in `AiPreviewScreen`
When at least one preview row carries a score, `AiPreviewScreen` renders a `FilterChip` bar (`All scenes (N)` / `Low score ≤ ★★★ (M)`). Selecting the low-score filter narrows the rendered `_PreviewRowCard` list to rows where any present score is `< 0.70` (`<= 3★`), while `AiApplyController` keeps the full row set so filtering the view never omits rows from the apply request.
