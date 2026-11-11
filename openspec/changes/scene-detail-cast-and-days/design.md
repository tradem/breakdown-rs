<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design — scene detail: plan before cast, one cast table, mixed-mood icons

## D1 — Order: days before cast

The body renders `header → synopsis → shooting days → cast`. The reason is not
aesthetic: the day is the dispo's unit and is decided before the wardrobe, and
a reviewer reading top-down should meet the planning question first. The two
sections stay independent `SectionCard`s (collapsed by default, count in the
header) — the merge is about figure+look, not about days.

Consequence handled: the cast card is now BELOW the fold, and the body is a
lazy `ListView`, so it is not in the widget tree until scrolled. Tests reveal it
with a bounded scroll helper (`revealInDetail`), and the golden is rebaselined.

## D2 — Day actions: icons per row, and a move that never leaves the scene empty

Per day row: day board (unchanged), **move to another day** (`swap_horiz`),
unschedule. Below the list the schedule action keeps its label with an icon.

`_realDayCandidates(rows, scene)` is the ONE candidate source — the section's
button, the row's move icon and the header's script-day clip all read it, so no
affordance can offer a day another one filters out (archived, or already on the
scene).

Move semantics (`_pickDayAndSchedule`, optional `replaceDayId`):

1. `scheduleScene(picked)` with the acted-on scene version.
2. On refusal: refresh, surface the code-keyed copy, dispatch NOTHING else. The
   scene keeps the day it had — the failure mode "no day at all" is what the
   naive unschedule-then-schedule would produce.
3. On ack: `unscheduleScene(previous)` with the version the ACK returned (not the
   stale row version — that would 409 on our own write).
4. A refused release leaves the scene on BOTH days: two rows, each removable,
   plus the code-keyed copy. Degraded, visible, and recoverable by hand — never a
   silent drop.

The script-day chip uses the same function WITHOUT `replaceDayId`: binding "Tag 1"
to a real day is a schedule, not a move, so nothing is released. Disabled when
`_realDayCandidates` is empty, which is the honest state (no day to bind).

## D3 — One cast table

`_SceneCastLooksSection` merges the former figures and looks sections.

- Data: `groupSceneBeats(assignedCharacters, outfitBeats)` (unchanged join, no
  client-side aggregation), plus the characters projection for the names.
- Header: `sceneDetailCastTitle(characters, looks)` — both counts, so the
  collapsed card still tells its story.
- Table: a label row (`Figur` / `Look`, `labelSmall`) and one `_CastRow` per
  (figure, look). The look cell keeps the beat identity key
  (`scene-piece-beat-<character>-<order>`), the category icon, the change arrow
  and the wardrobe cue; the figure cell is written on a figure's FIRST row and
  left empty on its change rows (classic table grouping).
- Actions per row: edit (first row only) → `RoleExtractScreen` (the Cast view's
  entry point, which renders the character detail); remove look (every look row);
  remove figure (first row only); add look (last row of a figure, or on the
  placeholder row of a figure without one).
- Placeholder: a figure with no look renders the honest "no look in this scene"
  line with the add-look icon in the look cell (key `scene-piece-empty-<id>`),
  not a separate empty state.
- Bottom action: `Figur und Look zuweisen` (`FilledButton.tonalIcon`), disabled
  when every character is already cast. It assigns (version echo of the acted-on
  `SceneView`) and then opens the look picker. Two commands, aggregate order; a
  cancelled picker keeps the figure cast, and a figure without looks gets the
  "no look yet — create it in the Cast view" hint instead of an empty sheet.

Edit route: the character detail needs a `SeasonView`, and the scene detail is
pushed with a `seasonId` only. `seasonById` (new, `features/seasons`) resolves it
CACHE-FIRST and fetches on a miss through `SeasonRepository` (the single owner of
network + cache writes; CQRS boundary — never a hand-rolled DTO). An unreadable
row disables the edit icon rather than opening a screen it cannot fill.

## D4 — Mixed-mood icons

`forSceneMood` now returns `({List<IconData> locations, IconData time})?`:

- the last component is the time token (`T`, `N`, `D`/`M`, `AB`);
- every preceding component must be `I` or `A`, and contributes one icon
  (`home` / `park`) — except the shorthand that names BOTH distinct locations in
  either order, which collapses to the single `sensor_door` icon (the scene
  crosses the threshold: `INT./EXT.` and the reported `A/I/T` are the same fact);
- repeated locations keep one icon each (`A/A/T` → two park icons);
- anything else (free text, unknown component, more than three locations) yields
  `null` → the label renders as plain text, exactly as before.

`SceneMoodLabel` renders `locations` then `time`, all decorative
(`ExcludeSemantics`), next to the visible label. The editor's canonical chip list
gains the `A/I/*` forms; the parser still only ever produces `I/A/*` (from
`INT./EXT.`), so the extra chips are values a script states verbatim.

## Honest limits

- The section merge is a rendering change: a beat's `note` (wardrobe cue) still
  belongs to the look row, so a figure with three looks has three cues — the
  table does not pretend one cue covers a figure.
- Binding the script day stores no association between the script's wording and
  the chosen day (the domain has none); it schedules the scene on the real day,
  which is the association the dispo and the reports read.
