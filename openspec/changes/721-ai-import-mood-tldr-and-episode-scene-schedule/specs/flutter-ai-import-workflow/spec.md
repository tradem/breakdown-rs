<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## ADDED Requirements

### Requirement: Mood shorthand icon reinforcement
Whenever a scene or preview row renders a non-empty `mood` value (such as `I/T`, `A/N`, `I/D`), the Flutter client SHALL render reinforcing Material icons for the interior/exterior and time-of-day components alongside the visible `mood` text label. Icons SHALL never replace the visible text label.

#### Scenario: I/T mood renders interior and day icons next to I/T text
- **WHEN** a scene or AI preview row with `mood = "I/T"` renders
- **THEN** the interior and day icons render adjacent to the visible `"I/T"` text
