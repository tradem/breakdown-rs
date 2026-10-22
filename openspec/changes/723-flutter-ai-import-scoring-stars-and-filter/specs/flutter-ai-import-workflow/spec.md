<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## MODIFIED Requirements

### Requirement: Preview AI-extracted banner and calibrated star ratings
The preview screen SHALL render an "AI-extracted content — review carefully" banner above the typed payload body whenever a successfully typed payload renders. When a preview row or shooting-day group carries calibrated Decision Model scores (`scene_score`, `synopsis_score`, `shooting_day_score`), the client SHALL render them as 1–5 star ratings (`AiScoreStars`) alongside their visible labels in `AiPreviewScreen` and `AiApplySection`, and SHALL provide a low-score filter chip (`<= 3★`) above the scene list to focus human review without removing filtered-out rows from the apply payload. When a score field is `null`, the client SHALL NOT render fabricated star ratings for that field.

#### Scenario: Scored preview row renders Scene, Synopsis, and Shooting Day stars
- **WHEN** a `DraftScene` with non-null `sceneScore`, `synopsisScore`, and `shootingDayScore` renders in `AiPreviewScreen`
- **THEN** `_PreviewRowCard` renders the corresponding 1–5 star ratings with their visible labels

#### Scenario: Low-score filter narrows visible cards without altering apply state
- **WHEN** the reviewer activates the `Low score ≤ ★★★` filter chip in `AiPreviewScreen`
- **THEN** only rows with at least one score `<= 3★` render in the list
- **AND** `AiApplyController` retains all seeded rows in the apply request
