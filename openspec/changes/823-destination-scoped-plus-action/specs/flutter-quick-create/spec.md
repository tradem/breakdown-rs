<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

## ADDED Requirements

### Requirement: AI-import jobs screen Import action

`AiImportJobsScreen` SHALL render its own plus action (`ai-jobs-plus-fab`) for a
resolved authenticated session, labelled with the entry it opens
(`navAiImport` — „Import") rather than with the shell's generic
`shellPlusFabLabel`. Tapping it SHALL open the shared quick-create sheet with
**exactly one** entry, „Import" (`quick-create-ai-import`), which pops the sheet
and pushes `AiImportSubmitScreen` on the root navigator — the same push
semantics the shell's sheet uses, so the flow covers the shell.

The screen SHALL NOT offer a second path into the same flow: the empty state is
plain narrative (no CTA button), and the FAB stays available in every list
state (empty, loading, data, stale, error). The screen's AUTHZ-GATE comment
SHALL travel with the new affordance; the sheet itself issues no request, and
the pushed submit controller keeps its own gates.

#### Scenario: The Import action is available with every list state
- **WHEN** the jobs screen renders for a resolved session with zero rows, with
  cached/fetched rows, or with a retained-rows error state
- **THEN** the `ai-jobs-plus-fab` affordance is rendered and opens the sheet

#### Scenario: The sheet offers exactly one entry
- **WHEN** the jobs screen's plus action opens the sheet
- **THEN** the sheet contains the single entry „Import" and no other
  quick-create entry

#### Scenario: The entry pushes the import flow on the root navigator
- **WHEN** the user taps the sheet's „Import" entry
- **THEN** the sheet pops and `AiImportSubmitScreen` is pushed on the root
  navigator, covering the shell

#### Scenario: The empty state hosts no second create path
- **WHEN** the jobs list is empty
- **THEN** the empty state renders its honest narrative without a CTA button,
  because the FAB is the screen's single create affordance
