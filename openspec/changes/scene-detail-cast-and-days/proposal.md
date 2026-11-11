<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Scene detail — plan before cast, one cast table, mixed-mood icons

## Why

Three PO findings on the scene detail screen (`834-scene-detail-redesign`
landed the shell: compact header, divider-free sections, persisted scores):

1. **The order is backwards.** „Figuren", „Looks" and „Drehtage" stood in that
   order, so the newest operational fact (where the scene is planned) sat at the
   bottom. A scene is planned before it is cast, and the dispo is built from the
   days, not from the looks. The day actions were text buttons and a picker
   round-trip: „Auf Drehtag planen", then unschedule + reschedule by hand to move
   a scene to another day — which leaves the scene with no day in between.
   The day the SCRIPT states („Tag 1", `SceneView.scriptDay`) had no affordance
   at all: the reviewer had to read the text and guess which real day it meant.
2. **Separate „Figuren" and „Looks" lists do not carry the information.** The
   reader joins them by hand, and a figure without a look is a dead end one
   section away from the affordance that fixes it. The PO wants ONE expandable
   area („Figuren (n) und Looks (m)"), one table row per figure with its look,
   removable/editable targets, and a single bottom action
   „Figur und Look zuweisen".
3. **Mixed moods render no icons.** `forSceneMood` accepted one location
   component plus the canonical `I/A` pair, so the very common „outside at the
   street, then inside the clinic / day" shorthand (`A/I/T`) degraded to plain
   text — while the import preview showed icons for the simple shorthands. The
   icons must be the same set everywhere.

## What changes (frontend only)

**Order + day affordances.** The shooting-days section moves directly below the
synopsis. Every action in it becomes an icon: per day row the day board, „move to
another day" and unschedule; at the bottom „Auf Drehtag planen" keeps its label
with an icon. „Move" schedules the newly picked day FIRST and releases the
current one only after that ack (chained on the ACK version), so a refused
schedule leaves the scene where it was and a refused release leaves it on both
days — visible and removable — never on none. The script-day chip in the header
gains the icon that binds the script's day to a real shooting day of the episode;
it is disabled exactly when no candidate day exists.

**One cast table.** „Figuren" and „Looks" merge into one `SectionCard`
(„Figuren (n) · Looks (m)"). Every row shows the figure cell and its look cell
(category icon, change arrow for further looks, wardrobe cue), with column
labels. Per row: edit (opens the Cast screen, i.e. the character detail with its
looks), remove look, remove figure, add look. The bottom `FilledButton.tonalIcon`
is „Figur und Look zuweisen": pick an unassigned figure, then pick its look —
two commands in the aggregate's own order (a beat needs an assigned character),
and a cancelled look picker leaves the figure cast, which is a real production
state and not an error.

**Mixed-mood icons.** `BreakdownMaterialIcons.forSceneMood` returns the location
icons (one per named component, in the shorthand's order) plus the time icon.
A shorthand that names exactly the two distinct locations `I` and `A` — in either
order — resolves to the single threshold icon (the scene crosses the door); every
other combination renders one icon per component (`A/A/T` → two park icons). The
editor's canonical chip set additionally offers the `A/I/*` forms, which the
deterministic `parse_mood_from_heading` scan never produces but a script states
verbatim.

## Non-goals

- No wire change, no backend change, no new route: every affordance uses the
  existing scene/shooting-day commands and the existing read DTOs.
- The synopsis/scores sections, the edit sheet and the freeze rules of #829 stay
  exactly as they are.
- No client-side aggregation: the cast table joins `SceneView.assignedCharacters`
  + `SceneView.outfitBeats` + the characters projection, as before.

## Affected specs

- `flutter-scene-detail` — MODIFIED: the section order, the day affordances and
  the merged cast table.
- `flutter-design-tokens` — MODIFIED: the mood icon resolver's component rule.

## Risks

- The cast section now sits below the days, so it is outside the initial
  viewport: a lazy `ListView` does not build it. Tests must scroll (they do) and
  the golden is rebaselined once.
- „Move to another day" chains two commands; the ordering rule (never release
  before the new day is acknowledged) is the whole point and is pinned by a test.
