<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-argon (google) -->

## ADDED Requirements

### Requirement: Mood shorthand icon reinforcement
Whenever a scene or preview row renders a non-empty `mood` value (such as `I/T`, `A/N`, `I/D`, `I/A/T`), the Flutter client SHALL render reinforcing Material icons for the interior/exterior and time-of-day components alongside the visible `mood` text label. A combined `I/A/T` mood SHALL resolve the interior/exterior icon from its combined `I/A` component and the time-of-day icon from its `T` component. Icons SHALL never replace the visible text label.

#### Scenario: I/T mood renders interior and day icons next to I/T text
- **WHEN** a scene or AI preview row with `mood = "I/T"` renders
- **THEN** the interior and day icons render adjacent to the visible `"I/T"` text

#### Scenario: I/A/T mood renders the combined and day icons next to I/A/T text
- **WHEN** a scene or AI preview row with `mood = "I/A/T"` renders
- **THEN** the combined interior/exterior icon renders adjacent to the visible `"I/A/T"` text together with the day icon
