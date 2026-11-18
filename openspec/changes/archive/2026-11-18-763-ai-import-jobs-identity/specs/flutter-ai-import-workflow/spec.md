<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# flutter-ai-import-workflow Delta (763-ai-import-jobs-identity)

## ADDED Requirements

### Requirement: The jobs list renders no stage for a terminal job
The AI-import jobs list SHALL render its stage/episode block only while the row
is in progress (`pending`/`running`), independent of whether the fetched row
still carries progress. A terminal row SHALL show status, identity, target and
cost — never a stage line — so no stale "Vorschau wird gespeichert …" can appear
for a finished job, including from a cached-first paint after an app restart.
An in-progress row SHALL show the stage and its discovered episode labels **with
their values**; a label without values SHALL NOT render.

#### Scenario: A succeeded row has no stage line
- **WHEN** the list renders a `succeeded` row whose DTO still carries
  `progress.stage = storing_preview`
- **THEN** no stage text renders and the localized
  `aiJobStageStoringPreview` copy is absent from the subtree

#### Scenario: A running row shows real episode values
- **WHEN** a running row's progress carries `episodes_seen = ["Ep. 299", "Ep. 300"]`
- **THEN** the row renders the stage line and both episode labels with their
  values

### Requirement: The row identifies the document and the imported episode
The jobs list SHALL title each row with the uploaded document's file name when
the job carries one (at most two lines, ellipsized) and keep `kind · date` as
secondary text. A job without a name SHALL keep today's `kind · date` title
unchanged, with no invented placeholder. The subtitle SHALL name the imported
episode(s) when the server reports them — `{kind} · {number} {name}`, and
`{number} {name} (+n)` when several episodes were targeted — degrading to the
kind alone when unknown. The Drift cache SHALL persist both fields with an
additive migration, and a cached-first paint SHALL NOT fabricate a name the
authoritative read has not yet supplied.

#### Scenario: A named, applied row
- **WHEN** a job carries `source_file_name = "Erlösung Skript.pdf"` and one
  applied episode (299, "Erlösung")
- **THEN** the title is the file name, the secondary line is `Skript · <date>`,
  and the subtitle names episode 299 Erlösung

#### Scenario: A multi-episode row
- **WHEN** the job's `applied_episodes` lists three episodes
- **THEN** the subtitle renders the first episode plus `(+2)`

#### Scenario: An unnamed, unapplied row degrades honestly
- **WHEN** a cached row has no name and no applied episodes
- **THEN** the title stays `kind · date` and the subtitle keeps the plain status
  copy — nothing is fabricated

### Requirement: The upload carries the picked document's name
The submit flow SHALL send the picked document's own file name with the upload
as a percent-encoded UTF-8 `X-Document-Filename` header, leaving the raw-body
`Content-Type` contract untouched (the documented `Options.contentType`
pitfall). A pasted/text-only document without a picked name SHALL send no
header rather than an invented one.

#### Scenario: A picked PDF sends its name
- **WHEN** the user picks `Erlösung Skript.pdf` and submits
- **THEN** the upload carries `X-Document-Filename` with the percent-encoded
  UTF-8 name and the unchanged `application/pdf` content type

#### Scenario: A pasted schedule sends no name
- **WHEN** the body is pasted text rather than a picked file
- **THEN** no `X-Document-Filename` header is sent and the job keeps a `null`
  name
