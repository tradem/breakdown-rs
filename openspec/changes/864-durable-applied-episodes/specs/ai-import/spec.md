<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# ai-import

## ADDED Requirements

### Requirement: The applied-episode summary is derived from the durable apply mappings

`AiImportJob.applied_episodes` SHALL be derived at the **read edge** from the
durable apply mappings, and SHALL NOT be written by the apply path. This
supersedes the persistence clause of the #763 requirement "A successful script
apply records its target episodes": the wire field, its meaning and its
consumers stay, the best-effort write behind it does not.

Derivation SHALL be: every `projection_ai_import_mapping` row of the job whose
`aggregate_kind` is `scene`, joined to the scene it names and to that scene's
episode, counted per episode. Each entry SHALL carry the episode id, the
persisted episode's own `number`/`name` (honest absence when the projection does
not know the episode), and the number of the job's rows mapped into it. Entries
SHALL be ordered by episode number, with the episode id as the tiebreak, so two
reads of an unchanged job agree.

The derivation SHALL be performed where the read model is legitimately read —
the job read (`GET /v1/ai-import/jobs/{id}`, its event stream) and the jobs list,
the latter in ONE query per page, never one per job. The write path SHALL NOT
consult a projection to produce it (CQRS boundary, `AGENTS.md` §1).

Consequences the derivation SHALL guarantee:

- an apply that committed rows leaves its summary resolvable **even when the
  client disconnected before the response**, because no write has to survive the
  cancelled handler future;
- a mapping that is still **reserved** (an id claimed, no command appended) SHALL
  NOT count — it is not applied work;
- a **schedule** apply, which writes only `scene_shoot`/`shooting_day` mappings,
  SHALL derive an empty list rather than an invented target;
- a row reconciled onto an **existing** scene SHALL be attributed to that scene's
  episode;
- a failure to derive SHALL be display-metadata loss only: an empty list and a
  logged warning, never a failed job read and never an unreachable job.

The `POST /v1/ai-import/jobs/{id}/apply` response SHALL keep reporting what that
request dispatched, from the apply's own plan — it answers "what did this request
do", not "where are this job's rows", and SHALL NOT wait for projector catch-up.

#### Scenario: A committed apply is readable after the client disconnected

- **WHEN** an apply commits scene rows and the client drops the request before
  the response, so no post-apply write runs
- **THEN** `GET /v1/ai-import/jobs/{id}` still lists the episodes those rows
  landed in, with their row counts

#### Scenario: A re-apply of an applied preview keeps the summary

- **WHEN** an apply re-runs a preview whose rows are all settled by confirmed
  mappings and therefore dispatches nothing
- **THEN** the job's summary still names where the earlier run put the rows, and
  the response's empty list does not erase it

#### Scenario: A schedule apply names no episode

- **WHEN** a schedule apply merges onto the project's existing scenes and days
- **THEN** the derived summary is empty and the client falls back to its existing
  row copy

#### Scenario: A job that was never applied stays distinguishable

- **WHEN** no row of the job is mapped to a projected scene
- **THEN** the summary is empty — the same answer as a job whose apply was
  cancelled before its first commit, and never a fabricated entry

#### Scenario: A row reconciled onto an existing scene is attributed to its home

- **WHEN** an apply updates an existing scene that lives in a different episode
  than the one the request named
- **THEN** the entry carries that scene's episode, not the request's target

#### Scenario: The list and the single read agree

- **WHEN** the jobs list and `GET /v1/ai-import/jobs/{id}` are read for the same
  job
- **THEN** both return the same summary, and the list pays one derivation query
  for the whole page
