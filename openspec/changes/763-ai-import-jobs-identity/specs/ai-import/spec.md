<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# ai-import Delta (763-ai-import-jobs-identity)

## ADDED Requirements

### Requirement: Terminal AI-import jobs carry no live progress
An `AiImportJob` in a terminal status (`succeeded`, `dead_letter`,
`payload_unavailable`) SHALL expose `progress = null`. `progress` describes the
live stage of a **running** job, so the queue SHALL clear the column in the same
statement that lands a terminal status (`mark_succeeded`, the dead-lettering
branch of `mark_failed`, and `mark_payload_unavailable`). The retryable `failed`
branch SHALL keep its progress — that job still has a future — and the
claim-time reset SHALL stay, so a re-claimed job never flashes a previous
attempt's stage.

#### Scenario: A completed job drops its stage
- **WHEN** a worker completes a job whose last published frame was
  `stage = storing_preview`
- **THEN** the `succeeded` job carries `progress = null` and no consumer renders
  a stage for it

#### Scenario: A dead-lettered job drops its stage
- **WHEN** `mark_failed` exhausts the retry budget and lands `dead_letter`
- **THEN** `progress` is cleared in the same statement

#### Scenario: A retryable failure keeps its context
- **WHEN** `mark_failed` schedules another attempt (`status = failed`)
- **THEN** `progress` is preserved until the next claim replaces it

### Requirement: An AI-import job carries the uploaded document's file name
An upload SHALL accept an optional percent-encoded UTF-8 `X-Document-Filename`
header naming the uploaded document. The server SHALL decode and sanitize it
(basename only, no path separators or control characters, collapsed whitespace,
bounded length) and persist it as an additive, nullable
`AiImportJob.source_file_name`. A request without the header, and every job
created before the field existed, SHALL expose `null` — an honest absence, never
a fabricated or `source_handle`-derived name. The raw-body upload contract
(content types and their `415` rejections) SHALL be unchanged.

#### Scenario: A named upload is attributable
- **WHEN** a client uploads `Erlösung Skript.pdf` with the percent-encoded name
- **THEN** the resulting job exposes `source_file_name = "Erlösung Skript.pdf"`

#### Scenario: A hostile header is sanitized, never echoed
- **WHEN** a client sends a name containing a path (`../../etc/passwd`), newlines
  or 400 characters
- **THEN** the persisted value is the bounded basename with control characters
  removed — or `null` when nothing printable remains

#### Scenario: An unnamed upload stays honest
- **WHEN** a client uploads without the header
- **THEN** `source_file_name` is `null` and the client renders the kind/date
  title unchanged

### Requirement: A successful script apply records its target episodes
A successful script apply SHALL attempt to persist the resolved target episodes
on the job as an additive `applied_episodes` list, each entry carrying the
episode id, its optional number, its optional name and the number of scene rows
this job applied into it. The list SHALL be derived from the apply path's own
plan and target data (enriched at the API edge, which is the only legitimate
read-model consumer) — never from a second projection lookup inside the write
path. `POST /v1/ai-import/jobs/{id}/apply` SHALL return the same list, whether or
not the column write succeeded. A schedule apply, which has no single target
episode, SHALL record an empty list rather than an invented one.

The persistence is **best-effort by design**: the scene rows are already
committed when it runs, so a failed write SHALL NOT fail the apply. In that case
the job keeps an empty list and every client falls back to its existing
kind/date copy — the same degradation an unnamed job uses. Durable recovery is
out of scope: it would require a persisted source for the summary that survives
the failed write.

A row SHALL only be attributed to an episode when **this** apply dispatched it.
A row whose mapping an earlier attempt already confirmed stays where that
attempt put it, so it SHALL NOT be attributed to the retry's target — neither by
id nor by label — because the retry's target need not be the scene's home. The
persistence SHALL therefore **merge** instead of replace: an entry for a known
episode is restated in place, a new episode is appended, and an empty list is a
no-op. A re-apply of an applied preview contributes nothing and the earlier,
correctly attributed summary survives; a partially applied job adds the episodes
it reached later.

A number/name SHALL only be recorded when it is authoritative for the row's
persisted location. Concretely: the plan's requested `Create` target SHALL label
an entry only when **this** apply created that episode (a reapply keeps the
mapped episode, whose number/title come from the first apply). An episode the API
edge resolved before dispatch labels its entry. Otherwise the entry SHALL keep
its `applied_count` with `number` and `name` unset — a count without a name,
never a name that contradicts the stored episode.

#### Scenario: A single-episode import names its target
- **WHEN** a script apply lands 57 rows in episode 299 "Erlösung"
- **THEN** the job exposes one `applied_episodes` entry (`number = 299`,
  `name = "Erlösung"`, `applied_count = 57`) and the apply response returns it

#### Scenario: A multi-episode import reports every target
- **WHEN** a script apply lands rows in three episodes through episode groups
- **THEN** the job exposes three entries, each with its own `applied_count`

#### Scenario: A schedule apply invents no episode
- **WHEN** a schedule apply merges onto the project's existing scenes and days
- **THEN** `applied_episodes` is empty and the client falls back to its existing
  row copy

#### Scenario: A failed summary write degrades instead of failing the apply
- **WHEN** the scene rows applied successfully but persisting the summary fails
- **THEN** the apply still answers `200` with the summary in its body, the job's
  column stays empty, and the client renders its kind/date copy

#### Scenario: A reapply labels from what is persisted, not from the request
- **WHEN** an episode group already has a mapping and the reapply carries a
  changed `Create` target
- **THEN** the entry keeps its `applied_count` with no number/name, so the summary
  never contradicts the persisted episode

#### Scenario: An already-applied row is never re-attributed
- **WHEN** the first apply lands a scene in episode A and a retry targets
  existing episode B (B resolvable at the API edge)
- **THEN** the retry's response carries no entry for that row, the job keeps A's
  entry, and B is never recorded

#### Scenario: A re-apply cannot erase the summary
- **WHEN** a retry finds every row already applied and therefore reports none
- **THEN** the merge is a no-op and the persisted summary still names the
  original episodes
