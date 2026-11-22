<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: gemini-4-carbon (google) -->

# Delta: ai-import-outfit-continuity-pass — neighbor-scene transition context brackets

## MODIFIED Requirements

### Requirement: Continuity is one calibrated choice question per gap
For each eligible gap the worker SHALL build a deterministic state payload
containing the current scene (number, location, mood, shooting/script day,
summary), compact transition context from the immediately adjacent `ScriptBody`
scenes (`previous_scene` and `next_scene`: scene number, location, mood,
script day, and whether `script_day` is continuous with the current scene),
and the character's most recent prior appearance carrying an outfit
(scene number, location, mood, day, outfit name, its pieces) and SHALL evaluate
exactly one `DecisionQuestion::Choice` with the options
`continue_previous`, `infer_new_outfit` and `report_conflict_or_gap`. The
winning option SHALL be the highest-probability option of the answer, and the
winning probability SHALL be recorded on the produced row. `continue_previous`
SHALL be treated as unavailable when the character has no prior outfit in the
preview, and an answer naming an unavailable option SHALL fall back to the next
highest available option.

#### Scenario: Model answers continuation
- **WHEN** the choice answer gives `continue_previous` the highest probability and the figure wore an outfit in an earlier scene
- **THEN** the gap SHALL resolve to Option A
- **AND** the produced outfit SHALL carry the winning probability as its confidence

#### Scenario: Continuation without a prior outfit
- **WHEN** the choice answer names `continue_previous` for a figure's first appearance
- **THEN** Option A SHALL be treated as unavailable
- **AND** the gap SHALL resolve to the next highest available option instead

#### Scenario: Adjacent scene bracket supplies same-day transition context
- **WHEN** Scene 12 (`"I/T - FOYER KLINIK"`, `"Tag 2"`) immediately follows Scene 11 (`"A/T - VOR KLINIK"`, `"Tag 2"`) in `ScriptBody`
- **THEN** the Pass 2 state payload for Scene 12 includes `previous_scene` (`scene_number: 11`, `location: "VOR KLINIK"`, `mood: "A/T"`, `script_day: "Tag 2"`, `same_script_day: true`)
