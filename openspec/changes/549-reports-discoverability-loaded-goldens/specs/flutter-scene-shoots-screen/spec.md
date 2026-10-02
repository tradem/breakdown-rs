<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## ADDED Requirements

### Requirement: Labelled Reports Entry

The day board's reports entry SHALL satisfy the glossary visible-label norm:
it SHALL carry a **visible** label alongside its icon, so the destination is
identifiable without hover or a long-press. The day board is the on-set
surface, so one tap from the board SHALL remain the whole path. When the app
bar is too narrow to carry the label and a readable title together, the entry
SHALL collapse into an overflow-menu item that is **itself labelled** — it
SHALL NOT revert to an icon-only affordance. Design D8 (the report is
strictly day-scoped and stays anchored in the day board) is unchanged by
this requirement: no season- or episode-level report entry is added.

#### Scenario: entry shows a visible label

- **WHEN** the day board renders with room for the label
- **THEN** the reports action is a labelled control — icon plus the visible
  text `sceneShootsReportsLabel` — and a semantic finder on that text
  succeeds (a test that would fail if the label regressed to icon-only)

#### Scenario: narrow app bar keeps a labelled item

- **WHEN** the day board renders narrower than the label breakpoint
- **THEN** the reports action moves into the overflow menu as a labelled item
  (icon plus the same visible text), never as a bare icon button

#### Scenario: entry key is stable across both forms

- **THEN** the tap target carries the Gherkin contract key `reports-open` in
  both forms, so the day-context step `I open the reports for shooting day
  {string}` keeps resolving without a scenario change
