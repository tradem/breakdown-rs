<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3-flash (opencode-go) -->

## ADDED Requirements

### Requirement: Point-of-interaction AI disclosure

The AI-import submit screen SHALL render a persistent disclosure card ABOVE
the submit action, visible before any submission, stating that the picked
document is processed by a server-side AI configured by the deployment, that
the results are AI-generated, and that they must be verified in the preview
before apply. The copy SHALL be localized ARB catalog copy keyed by the
glossary; the card SHALL be visibly distinct (icon + icon surface) so the
disclosure is not skippable content.

#### Scenario: Disclosure precedes submit
- **WHEN** the submit screen renders (any kind selection).
- **THEN** the disclosure card renders before the submit button in the
  scroll order and remains persistent while the file picker and kind picker
  render.

#### Scenario: No submission before disclosure
- **WHEN** a test asserts the screen's scroll order.
- **THEN** the disclosure card's scroll offset precedes the submit button's
  (the card is never moved below the fold as an afterthought).

### Requirement: Preview AI-extracted banner

The preview screen SHALL render an "AI-extracted content — review carefully"
banner above the typed payload body whenever a successfully typed payload
renders. The banner copy SHALL state that the rows are machine-extracted
drafts and that the payload carries no machine-verified confidence values
(the wire preview has none; `confidence` exists only on the recorded
provenance after apply). The client SHALL NOT render fabricated per-row
confidence chips.

#### Scenario: Typed payload shows the banner
- **WHEN** a script / schedule / merged payload renders.
- **THEN** the banner renders above the payload header.

#### Scenario: No fabricated confidence chips
- **WHEN** the payload renders.
- **THEN** no per-row chip asserts a confidence value; the honest review
  note is the banner's only safety framing (the wire carries none).

### Requirement: Apply review acknowledgement

The apply section SHALL gate the apply dispatch behind an explicit review
checkbox ("I have reviewed the AI-extracted content"). The submit button
SHALL stay disabled until the checkbox is checked (together with the
existing context gate); the selection summary
(create/update/skip counts + edit distance) SHALL render adjacent to the
acknowledgement.

#### Scenario: Unchecked apply is disabled
- **WHEN** the apply section renders with a valid context and the checkbox
  is unchecked.
- **THEN** the submit button is disabled.

#### Scenario: Acknowledged apply dispatches once
- **WHEN** the user checks the acknowledgement and taps submit.
- **THEN** the existing single apply dispatch runs unchanged (context,
  rows, decisions, versions) — the acknowledgement adds no second dispatch.

### Requirement: Provenance badge on AI-derived read rows

Every read surface that renders AI-derived rows SHALL render a persistent
provenance badge whenever the row's `source` is `Some(AiExtracted)`:
the shooting-days day list, the scene-detail shooting-days section and its
schedule picker, and the Soll/Ist day surface. Rows with `Manual` or `null`
source SHALL NOT carry the badge (legacy-proof). The badge copy SHALL be
localized and the badge SHALL be a semantic visible element (test key per
row id), not an arrow decoration.

#### Scenario: AI-derived day row is recognizable
- **WHEN** a `ShootingDayView` with `source = Some(AiExtracted)` renders.
- **THEN** the row carries one visible badge keyed
  `shooting-day-ai-badge-<id>`.

#### Scenario: Manual row carries no badge
- **WHEN** a row's `source` is `Manual` or `null`.
- **THEN** no badge renders for that row (no false attribution in either
  direction).
