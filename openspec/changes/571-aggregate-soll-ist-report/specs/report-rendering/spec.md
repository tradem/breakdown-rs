<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## ADDED Requirements

### Requirement: Aggregated report kinds

`ReportKind` SHALL gain the variants `SeasonSollIst` and `EpisodeSollIst`
(kebab-case wire names `season-soll-ist` / `episode-soll-ist`) for the two
season-/episode-scoped aggregated Soll-Ist render kinds. Each kind SHALL map
to its own embedded Typst template (day-completion summary plus a Drehtag
column over the planned-vs-actual layout). The aggregate kinds SHALL NOT be
part of the archivable kind set; the archival data loader SHALL reject them
explicitly, and no aggregate job kind string SHALL ever be enqueued.

#### Scenario: aggregate kinds render their own templates

- **WHEN** a `ReportRenderRequest` carries `SeasonSollIst` or
  `EpisodeSollIst`
- **THEN** the renderer uses the kind's own embedded template and produces a
  PDF whose layout includes the Drehtag column and the day-completion
  summary

#### Scenario: aggregate kinds are not archivable

- **WHEN** the archival pipeline enumerates kinds to archive or loads data
  for a job kind
- **THEN** only the three day-scoped kinds are relevant; an aggregate kind
  reaching the loader is rejected without enqueueing or rendering
