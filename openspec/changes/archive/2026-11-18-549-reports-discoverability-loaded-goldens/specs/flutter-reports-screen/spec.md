<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

## ADDED Requirements

### Requirement: Report-Provenance Empty State

A scene scheduled on **no** shooting day SHALL render a plain-language empty
state in its shooting-days section that names the Soll/Ist report as what
becomes available once the scene is scheduled on a day. The empty state
SHALL invent no report and SHALL NOT offer a season- or scene-scoped report
entry: the report routes are day-scoped in the contract itself
(`/v1/shooting-days/{id}/report/*` only), so a scene with no day genuinely
has nothing to report against. The hint is copy, not an affordance.

This is the discoverability half of the entry chain: no day → no day board →
no reports entry, so without the hint the report surface is invisible to a
user who has just created a scene and has no reason to expect one later.

#### Scenario: scene with no shooting day names the report

- **WHEN** the scene detail screen renders a scene whose scheduled day list
  is empty (key `scene-shooting-days-empty`)
- **THEN** the empty state carries the report-provenance copy
  (`sceneDetailNoShootingDaysReportHint`) naming the Soll/Ist report as what
  becomes available once the scene is scheduled on a shooting day

#### Scenario: hint is absent once a day exists

- **WHEN** the same scene detail screen renders a scene with at least one
  scheduled day
- **THEN** the report-provenance copy is absent — the hint never appears on a
  scheduled scene, and no season-level report entry is offered
