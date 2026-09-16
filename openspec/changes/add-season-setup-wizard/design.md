<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

## Context

Setup today: `create_season_sheet.dart` (bottom-sheet form, number
+ optional name), then block/episode creation scattered across the
hierarchy screens one row at a time. The research report (§5,
Yazio/Hevy pattern analysis) recommends a linear wizard with
progress, smart defaults, and a value-anchored completion screen.
Team decisions binding here: (3) destructive abort — no draft
persistence, no resume; (6) conditional AI-import CTA gated on
existing AI configuration. Repositories, reconciliation machinery,
and AUTHZ-GATE discipline are already battle-tested in the seasons
reference implementation — this change composes them, it does not
re-implement them.

## Goals / Non-Goals

**Goals:**
- Linear 4-step wizard (Season → Blocks → Review → Completion) with
  per-step validation, smart defaults, progress indicator.
- Block templates as suggestions; repeatable block drafts.
- Sequential dispatch over existing commands with per-command
  optimistic/2xx + bounded-retry reconciliation; partial-failure
  handling with in-session retry.
- Destructive, confirmed abort (decision 3).
- Conditional AI-import CTA (decision 6).
- Gherkin acceptance flow (setup is business-critical).

**Non-Goals:**
- No draft persistence/resume (decision 3).
- No new API routes; no bulk endpoints (episode creation per block
  issues individual commands — backend concurrency is the
  backend's concern).
- No AI import execution inside the wizard (only the link; the
  import flow stays its own screen).
- No replacement of the quick-create sheet (both paths coexist).

## Decisions

### D1 — Wizard state: single freezed model + one controller
`SetupWizardState` (freezed: `step`, `seasonNumber`, `seasonName`,
`blocks: List<BlockDraft>`, `phase: editing|review|dispatching|
completed|partial-failure`, `createdRefs`) owned by an
`@riverpod` `SetupWizardController`. Pure state transitions in the
controller → unit-testable without Flutter imports. Widgets are
presentational only (riverpod-free step widgets in `setup/widgets/`).

*Alternative:* one controller per step with shared store — rejected:
more wiring, no benefit at this size; step-local edit state (text
fields) stays widget-local as in `create_season_sheet.dart`.

### D2 — Dispatch as state machine over existing repositories
Dispatch phase reduces over drafts using the same repositories the
individual screens use (`SeasonRepository.create`,
`BlockRepository.create`, `EpisodeRepository.create`), each already
implementing AUTHZ-GATE + optimistic + bounded-retry. The wizard adds
only sequencing and progress state. Ids flow response → next
command's payload (CQRS boundary). No `Future.wait` fan-out:
sequential dispatch keeps failure semantics simple and matches the
report's per-step progress requirement.

### D3 — Destructive abort with `PopScope` + confirm dialog
Back gesture in editing/review phases triggers the discard
confirmation (dialog copy keyed per glossary). During dispatch,
`PopScope` blocks; system back follows the partial-failure/
completion paths. This honors decision 3 without persisting drafts.

### D4 — AI config check before render of the CTA
The existing ai-config read (`aiConfigController`) decides CTA vs
info card at completion render; no new endpoint, no extra AUTHZ
surface (config read already ships its gate comment — reused
verbatim).

### D5 — Entry: full-screen route in the Season tab's navigator
`Navigator.push` of the wizard page inside the shell's Season tab
stack — same pattern as BlocksScreen pushes; no routing package, no
hero transitions beyond platform defaults.

### D6 — Gherkin flow (critical designation per
flutter-gherkin-hybrid): `setup/season-wizard.feature` covering
happy path, template application, partial failure, abort-discard.
Widget-tier mirrors every scenario minus device specifics; goldens
per step (light/dark).

## Risks / Trade-offs

- [Sequential dispatch duration for large templates (e.g. 4×10
  episodes = 40+ commands)] → progress UI with per-command
  granularity; realistic templates default small; measured on
  device in integration tier; escalation path (backend bulk route)
  is a future backend change if needed.
- [User expects resume because "wizard" implies saving] → the
  discard dialog states explicitly what is lost (decision 3 is a
  product call; revisit via feedback if drop-offs cluster at
  accidental aborts).
- [Partial failure leaves a half-built production] → summary +
  in-session retry keeps recovery cheap; season delete exists as
  the escape hatch; documented honestly in the completion copy.
- [Template list hardcoding vs data-driven] → templates ship as
  consts in the wizard feature (data-driven from backend is
  speculative now; golden-keyed copy via glossary).

## Migration Plan

1. Add wizard state + controller + step widgets (unit tests first).
2. Wire dispatch sequencing + partial-failure surface.
3. Completion screen + conditional CTA (ai-config read).
4. Entry points (empty-state CTA — coordinated with
   redesign-seasons-home task, create-flow menu entry).
5. Gherkin + integration coverage; goldens.
6. Rollback: additive feature removal; empty-state CTA falls back
   to the quick-create sheet link.

## Open Questions

None blocking. (Exact template presets are a copy/detail decision
from the glossary during implementation.)
