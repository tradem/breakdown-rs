<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# flutter-ai-import-workflow Specification

## Purpose
Defines the AI document import workflow of the Flutter client: the
user-facing pipeline that submits raw schedule/script documents (paste,
CSV, PDF) to the backend import routes, observes job processing through
a bounded watch state machine (pending/running → succeeded/failed/
dead_letter/payload_unavailable, no cancel affordance — the backend
owns cancellation), renders typed previews with strict rejection of
unknown future payload kinds, and applies mapping decisions into an
episode (verbatim draft_refs, edit_distance from real selections,
missing-context picker requirement). Every dispatch is AUTHZ-gated
client-side — a denial issues zero network requests — and duplicate
uploads are surfaced honestly, never as a fresh import.
## Requirements
### Requirement: Raw-Document Job Submission
The workflow SHALL submit schedules (CSV file, PDF file, or pasted
plain text) and scripts (PDF) as RAW-body uploads with the matching
declared `Content-Type` (never multipart), after the season
membership AUTHZ-GATE (capability check before the network call,
`// AUTHZ-GATE:` annotated). A 202 SHALL navigate to the job status
screen; a 200 duplicate SHALL navigate with an explicit "already
imported (duplicate)" callout; 413/415/404 SHALL render copy keyed on
the problem `code`.

#### Scenario: Schedule upload accepted
- **WHEN** the user submits a CSV and the backend returns 202 with a
  job id.
- **THEN** the job status screen pushes with the returned id; the
  submission screen surfaces in-flight progress and never blocks the
  frame on the upload.

#### Scenario: Duplicate document
- **WHEN** the upload returns 200 (digest-duplicate).
- **THEN** the UI navigates to the existing job with the duplicate
  callout; nothing implies a second import was created.

#### Scenario: Membership denial short-circuits
- **WHEN** a user without the costume-dept capability submits.
- **THEN** the client denies before the network call with the 403
  narrative (fake-repository call count of zero in tests).

### Requirement: Job Status With Terminal Error States
The job status screen SHALL watch the job while foregrounded via the
push-based Server-Sent Events stream (`GET /v1/ai-import/jobs/{id}/events`)
with a single snapshot `GET /v1/ai-import/jobs/{id}` on app resume (no
periodic polling, no background wake-ups) and render every status honestly:
`pending`/`running` with localized extraction stage (`stage`), chunk counter
(`chunk / chunks_total` with determinate progress indicator only when
`chunks_total` is present and positive, otherwise indeterminate progress —
never fabricated percentages), and discovered episode badges/chips
(`episodes_seen`, e.g. `Ep. 3`, `Ep. 4`) when `progress` is present;
retryable `failed` with `retries/max_retries`, a live localized time until
the next planned attempt derived from `next_attempt_at`, and the reason the
prior attempt(s) failed keyed on the attempt's stable problem `code`; and
terminal `dead_letter`/`payload_unavailable` as error cards whose primary
copy is keyed on the status with the attempt's code-keyed reason and
`last_error` as secondary text only. A "cancel" affordance SHALL NOT exist
(no server route); the user may only close/leave, and the copy SHALL say
so. When `next_attempt_at` is absent the screen SHALL say a retry is
scheduled without inventing a time; copy SHALL NEVER be interpolated from
the backend `detail`/`error_summary`.

#### Scenario: Live stage, chunk, and episode visibility during processing
- **WHEN** the SSE stream delivers a `running` job carrying
  `progress = { stage: "extracting", chunk: 4, chunks_total: 12, episodes_seen: ["Ep. 3", "Ep. 4"] }`.
- **THEN** the job status screen renders the localized stage copy, the `4 / 12`
  chunk progress, and the discovered episode labels `Ep. 3` and `Ep. 4`
  without blocking the UI thread.

#### Scenario: Running job without chunk counts shows indeterminate progress
- **WHEN** a job is `pending` or `running` with `progress == null` or
  `chunks_total == null`.
- **THEN** the screen shows the indeterminate progress affordance (never a
  fabricated percentage); leaving the screen closes the SSE subscription and
  returning re-arms it.

#### Scenario: Retryable failure shows a live ETA
- **WHEN** a retryable `failed` job carries `next_attempt_at` in the
  future.
- **THEN** the retryable card renders a localized "next retry in …"
  that updates as time passes, alongside the retry budget.

#### Scenario: Retryable failure without an ETA degrades honestly
- **WHEN** a retryable `failed` job has no `next_attempt_at`.
- **THEN** the card says a retry is scheduled and shows no countdown —
  no fabricated time.

#### Scenario: Retryable failure explains the prior attempt
- **WHEN** a retryable `failed` job carries attempt history.
- **THEN** the reason of the newest attempt is rendered on the retryable
  card, localized from the ARB catalog keyed on the attempt's problem
  `code`; an absent or unrecognized `code` renders the generic localized
  reason, never the raw backend summary as identity.

#### Scenario: Terminal processing error
- **WHEN** the job reaches `dead_letter` or `payload_unavailable`.
- **THEN** the terminal error card renders with status-keyed primary
  copy and the `last_error` string as secondary detail; the SSE watch ends.

### Requirement: Tolerant Preview Rendering and Explicit Apply
The preview screen SHALL render the typed `AiImportPreviewResponse` / `AiPreviewPayload` (`kind`/`data`: `script` → `ScriptContext`, `schedule` → `ShootingSchedule`, `merged` → `MergedPreview`; backend issue #337, PR #357) from the generated client: recognized payloads as cards, an unknown future `kind` as an explicit degraded card with a stable code — never silently coerced data, never retyped DTOs. The apply action SHALL submit `ApplyAiImportRequest`
with `draft_ref`s taken verbatim from the preview rows the user acted
on, per-row decisions (Create / Update with the picked aggregate id +
version from the read DTO / skip), the job's PERSISTED episode context
(`episode_id` + `series_id`, stamped onto the cached job row at submit
time — never read from the navigation stack; a missing context requires
the explicit episode picker before the apply dispatch), and the
`accept_as_is` + `edit_distance` values from the actual selection state. The 200 response SHALL render the outcome
summary (`applied_count`, `created_days`, `planned_scene_shoots`).

#### Scenario: Partial preview results
- **WHEN** the preview contains a mix of recognized rows and an
  unknown future `kind`.
- **THEN** recognized rows are actionable; the unknown payload renders as
  a degraded card excluded from one-tap accept-all; apply proceeds only
  with explicit user decisions.

#### Scenario: Unknown preview kind strict-rejects
- **WHEN** the preview carries a `kind` string the client does not know.
- **THEN** the screen renders the standard error state keyed on the
  stable code instead of guessing a meaning (no guessed rendering).

#### Scenario: Apply with mixed decisions
- **WHEN** the user marks one row Create, one Update (existing
  aggregate picked), and skips the rest.
- **THEN** the request carries exactly those mappings; the summary
  card reflects the server's outcome counts; deep navigation to the
  affected episode is offered.

#### Scenario: Apply reconciles after an ambiguous timeout
- **WHEN** an apply dispatch times out with an unknown outcome.
- **THEN** the controller re-reads the job/outcome first and reconciles
  (bounded retry, server-side idempotency per backend issue #338) —
  never blind re-dispatch, never a duplicate import implied.

#### Scenario: Empty preview
- **WHEN** a succeeded job's preview returns 404.
- **THEN** an explicit "no preview available" state renders with the
  option to view the job's terminal status; no fabricated rows.

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

### Requirement: Foreground-Only SSE Subscription and Battery Contract
The Flutter client SHALL consume `GET /v1/ai-import/jobs/{id}/events`
exclusively over the existing ADR-024 / ADR-032 pinned-CA `Dio` transport
(`SecurityContext(withTrustedRoots: false)` with `ResponseType.stream`),
never via an unpinned `HttpClient`. Only `AiJobStatusScreen` SHALL open an
SSE subscription, and only while the screen is mounted and the application
is foregrounded.

When `AiJobStatusScreen` is disposed or the application transitions to the
background (`paused` / `hidden` / `detached`), the client SHALL cancel the
SSE stream immediately so zero background network wake-ups occur. When the
application resumes to the foreground while `AiJobStatusScreen` is mounted,
the controller SHALL perform ONE snapshot read (`GET /v1/ai-import/jobs/{id}`)
and re-subscribe to the SSE stream only if the job status is non-terminal.
On a transient stream disconnect or a read-idle watchdog timeout (`receiveTimeout`
exceeding 2× the server's 30 s `: keep-alive` interval, detecting silent
middlebox/NAT drops) while foregrounded, the client SHALL
reconnect with bounded backoff passing the last received SSE `id` in the
`Last-Event-ID` header. The jobs overview list (`AiImportJobsScreen`) SHALL
NOT open SSE streams (zero watches); it SHALL render each row's `progress`
summary (stage and `episodes_seen`) from its one-shot `GET /v1/ai-import/jobs`
fetch and manual pull-to-refresh.

#### Scenario: Stream closes on background and refreshes once on resume
- **WHEN** `AiJobStatusScreen` is watching a running job and the app is
  backgrounded.
- **THEN** the active SSE stream subscription is cancelled immediately.
- **WHEN** the app returns to the foreground (`resumed`).
- **THEN** the controller performs one `GET /v1/ai-import/jobs/{id}` snapshot
  read and re-opens the SSE stream only if the job is still non-terminal.

#### Scenario: Transient disconnect reconnects with Last-Event-ID over pinned TLS
- **WHEN** an active SSE stream on `AiJobStatusScreen` drops transiently after
  receiving event `id: 42`.
- **THEN** the repository reconnects via the pinned-CA `Dio` client with header
  `Last-Event-ID: 42` and updates the UI from the server's initial snapshot
  event.

#### Scenario: Jobs overview list renders progress without opening SSE streams
- **WHEN** `AiImportJobsScreen` renders a list of jobs fetched from
  `GET /v1/ai-import/jobs` containing a running job with `progress`.
- **THEN** the row displays the localized stage/episode progress summary
- **AND** the repository `watch` call count from `AiImportJobsScreen` remains
  zero.

### Requirement: Per-Import Cost Display in Jobs List and Job Detail
The Flutter AI import jobs list and job status/detail screens SHALL display
per-import cost information from `AiImportJob.cost`, `AiImportJob.telemetry` and
`AiImportJob.decision_telemetry` (including updates arriving via the terminal
`succeeded` SSE frame on `GET /v1/ai-import/jobs/{id}/events`), using the
integer nano-currency formatting of `cost_format.dart` only (no floating-point
math, and a non-zero amount SHALL NEVER render as `0`):

- **Detailed view (job status / detail screen)** SHALL render a card with a
  visible hierarchy rather than a flat list:
  - a **hero figure**, rendered large and with an ALWAYS-VISIBLE label that
    names what the figure is. The figure SHALL be the money the user pays:
    `cost.total.total_nano` when `cost.total.status == "known"`, otherwise
    `cost.token_cost.total_nano`. When the user's
    `AiConfig.cost_display_preference` is `"energy"` and `cost.energy_cost` is
    present, the hero SHALL instead show
    `cost.energy_cost.effective_capped_nano` (the capped value, never the raw
    one) under an energy label. The label SHALL change with the figure, so a
    component is never presented as the total.
  - the **effective model** (`telemetry.model`) and the **provider**
    (`telemetry.provider`) as two prominent, individually LABELLED elements that
    wrap in narrow layouts, ellipsize past two lines and expose the full value
    in a tooltip.
  - the remaining figures as icon-prefixed, visually subordinate detail rows:
    `tokens_in` / `tokens_out` (and `cached_tokens_in` when non-zero), the
    snapshot rates and `price_as_of` timestamp, the token cost, and — when
    `cost.energy_cost` is present — the energy consumption
    (`energy_millijoules` / Wh) and the energy cost, with the user's preferred
    component emphasised. No figure the detailed view rendered before MAY be
    dropped.
  - when `cost.decision` is present, that component's OWN `provider` / `model`,
    its own usage counts and its own priced figures (`token_cost_nano`,
    `energy_cost_nano` in the component's own `currency`), visually grouped
    apart from the extraction component; when it is present but not `"known"`,
    its usage counts SHALL still render and its price SHALL be stated as not
    priced — the extraction rate SHALL NEVER be substituted. When
    `cost.image_cost` is present, its total SHALL render, so a displayed total
    stays explainable by the rows around it.
- **A refused total** SHALL be rendered honestly: `cost.total.status`
  `"incomplete"` or `"mixed_currency"` SHALL render the priced component plus a
  localized note stating why no sum is shown (no rate substitution, and no
  currency conversion — design D2). The note SHALL be rendered under EVERY
  display preference, including `"energy"`: the refusal is a property of the
  snapshot, not of the figure the user chose to see first. `"unknown"`, or a
  snapshot that carries no total at all (every pre-#768 row), SHALL claim no
  total and SHALL render no note.
- **Compact view (jobs list):** SHALL render the SAME primary figure as the
  detailed hero, resolved by ONE shared rule: `cost.total.total_nano` when the
  wire publishes a `"known"` total, `cost.energy_cost.effective_capped_nano`
  under the `"energy"` preference when a component exists, and the extraction
  `token_cost.total_nano` otherwise — so the two surfaces can never claim
  different primary amounts. The line SHALL carry a metric icon that mirrors
  the same choice. The icon is reinforcement only: the visible `"Kosten: …"`
  text SHALL always be present, and the line SHALL NOT trigger any additional
  request (a cached row carries no cost and renders no line).
- When `cost.status == "unknown"`: both views SHALL render localized
  `"Unbekannt"` / `"Unknown"` copy (the detailed view as the hero VALUE, while
  still displaying the recorded token counts) and SHALL NEVER display `0` or
  `$0.00`.
- When `cost.status == "not_applicable"` (e.g. native CSV schedule import):
  the UI SHALL indicate that no AI model was billed (or omit the LLM cost badge)
  rather than displaying an unknown or zero LLM price.

#### Scenario: Jobs list and detail switch primary cost according to user preference
- **WHEN** a completed Neuralwatt job carries both `token_cost` (`$0.0235`) and `energy_cost` (`$0.00005`) and the user's `AiConfig.cost_display_preference` is `"energy"`
- **THEN** the jobs list compact line displays the energy cost as the primary figure and carries the energy metric icon
- **AND** the job detail card displays the energy figure as its labelled hero
- **AND** the job detail card displays both the energy breakdown and the token breakdown below it

#### Scenario: The list line and the detail hero show one primary figure
- **WHEN** a completed job carries a `"known"` `cost.total` of `$0.023755` whose components include a Decision-Model share
- **THEN** the jobs list compact line and the detail hero both render `$0.023755`
- **AND** a job without a total renders the extraction token cost in both places

#### Scenario: The detail card names the model and the provider
- **WHEN** a completed job carries `telemetry.model = "gpt-5.6-luna"` and `telemetry.provider = "neuralwatt"`
- **THEN** the detail card renders both as labelled identity elements next to the hero figure

#### Scenario: A published total is the hero figure
- **WHEN** a #768 job carries `cost.total.status = "known"` with `total_nano` and the preference is `"token"`
- **THEN** the hero figure is the formatted total, under a total label
- **AND** the token and energy component rows still render below it

#### Scenario: A total the server refuses is not invented client-side
- **WHEN** a job carries `cost.total.status = "incomplete"` (a recorded component is unpriced) or `"mixed_currency"`
- **THEN** the hero figure is the priced component under a component label
- **AND** a localized note states why no total is shown
- **AND** no rate is substituted and no currency is converted

#### Scenario: The refusal note survives the energy preference
- **WHEN** the preference is `"energy"` and `cost.total.status` is `"incomplete"` or `"mixed_currency"`
- **THEN** the hero shows the energy figure under its energy label
- **AND** the localized refusal note still renders below it

#### Scenario: A pre-#768 snapshot claims no total
- **WHEN** a job's cost snapshot carries no `total` at all
- **THEN** the hero figure is the token component under a component label
- **AND** no "total unavailable" note is rendered (an absence is not an error)

#### Scenario: The Decision Model's own component is shown separately
- **WHEN** a job's `cost.decision` carries a different `provider` / `model` than the extraction telemetry
- **THEN** the card renders that pair with its own usage counts and its own priced figures in its own currency
- **AND** the extraction component's figures are unchanged

#### Scenario: An unpriced Decision component is never priced with the extraction rate
- **WHEN** `cost.decision.status` is `"unknown"` (no pricing row for that model)
- **THEN** its usage counts still render
- **AND** its price line states that the component is not priced
- **AND** neither `0` nor the extraction rate is rendered for it

#### Scenario: Unknown model price displays Unknown and never zero
- **WHEN** a completed job carries `cost.status == "unknown"` (e.g. an Ollama import)
- **THEN** both the jobs list and the job detail screen display localized `"Unbekannt"` / `"Unknown"` for the cost and never `0` or `$0.00`
- **AND** the detail card still renders the recorded token counts

#### Scenario: Nothing was billed
- **WHEN** a completed job carries `cost.status == "not_applicable"` (native CSV import)
- **THEN** the detail card states that no AI model was billed
- **AND** the jobs list renders no cost line

#### Scenario: A long model id holds in the compact layout
- **WHEN** the detail card renders a model id that does not fit the available width
- **THEN** its identity element wraps to at most two lines and ellipsizes, with the full value available in a tooltip
- **AND** the card does not overflow horizontally at the compact window width

#### Scenario: Final SSE frame populates cost breakdown on job completion
- **WHEN** the job status screen is watching a running job over SSE and receives the terminal `succeeded` frame containing `job.cost`
- **THEN** the screen immediately renders the completed job's cost breakdown without requiring an extra manual refresh

### Requirement: Mood shorthand icon reinforcement
Whenever a scene or preview row renders a non-empty `mood` value (such as `I/T`, `A/N`, `I/D`, `I/A/T`), the Flutter client SHALL render reinforcing Material icons for the interior/exterior and time-of-day components alongside the visible `mood` text label. A combined `I/A/T` mood SHALL resolve the interior/exterior icon from its combined `I/A` component and the time-of-day icon from its `T` component. Icons SHALL never replace the visible text label.

#### Scenario: I/T mood renders interior and day icons next to I/T text
- **WHEN** a scene or AI preview row with `mood = "I/T"` renders
- **THEN** the interior and day icons render adjacent to the visible `"I/T"` text

#### Scenario: I/A/T mood renders the combined and day icons next to I/A/T text
- **WHEN** a scene or AI preview row with `mood = "I/A/T"` renders
- **THEN** the combined interior/exterior icon renders adjacent to the visible `"I/A/T"` text together with the day icon

### Requirement: Calibrated preview ratings and low-score filtering
When a preview row or shooting-day group carries calibrated Decision Model scores (`scene_score`, `synopsis_score`, `shooting_day_score`), the client SHALL render them as 1–5 star ratings (`AiScoreStars`) alongside their visible labels in `AiPreviewScreen` and `AiApplySection`, and SHALL provide a low-score filter chip (`<= 3★`) above the scene list to focus human review without removing filtered-out rows from the apply payload. When a score field is `null`, the client SHALL NOT render fabricated star ratings for that field.

#### Scenario: Scored preview row renders Scene, Synopsis, and Shooting Day stars
- **WHEN** a `DraftScene` with non-null `sceneScore`, `synopsisScore`, and `shootingDayScore` renders in `AiPreviewScreen`
- **THEN** `_PreviewRowCard` renders the corresponding 1–5 star ratings with their visible labels

#### Scenario: Low-score filter narrows visible cards without altering apply state
- **WHEN** the reviewer activates the `Low score ≤ ★★★` filter chip in `AiPreviewScreen`
- **THEN** only rows with at least one score `<= 3★` render in the list
- **AND** `AiApplyController` retains all seeded rows in the apply request

### Requirement: The preview states where each look came from
The preview SHALL render exactly ONE provenance badge per outfit row, keyed on
the row's `DraftOutfit.origin`: `explicit_quote` (quoted from the script),
`derived` (derived from the script), `continued_from_scene` (continued from the
source scene named by `DraftOutfit.provenance.source_scene_number`, degrading to
"an earlier scene" when the wire carries no number) and
`inferred_from_context` (inferred from the scene context). The badge SHALL be a
visible, localized element with a per-row test key — never the raw wire slug.

An outfit row whose origin is absent (a preview stored before the field existed)
or unrecognized SHALL render NO badge: provenance is never inferred from the
presence of a quote, a scene number or a confidence value.

#### Scenario: A continued look names its source scene
- **WHEN** an outfit row carries `origin = continued_from_scene` with
  `provenance.source_scene_number = 4`
- **THEN** the row renders the badge "continued from scene 4"
- **AND** the badge is keyed for that row and ordinal

#### Scenario: An origin-less row carries no badge
- **WHEN** an outfit row carries no origin (a preview stored before the field)
- **THEN** the row renders no provenance badge and no attribution is invented

### Requirement: A Pass-2 look renders no source quote
The source-quote line SHALL render only for an outfit row whose origin carries
its own grounding evidence (`explicit_quote`, `derived`, or an absent origin on
a pre-change preview). A `continued_from_scene` or `inferred_from_context` row
SHALL NOT render the quote line, because the server leaves `source_quote` empty
for those rows and an empty evidence line would read as if the script had stated
the look.

#### Scenario: An inferred look shows no evidence line
- **WHEN** an outfit row carries `origin = inferred_from_context` and an empty
  `source_quote`
- **THEN** the row renders its provenance badge and no "Source:" line
- **AND** a quoted row of the same preview still renders its evidence

### Requirement: The reviewer resolves a wardrobe gap with one tap
For a `dropped_row` uncertainty on the `outfits` field whose `candidates` list
is non-empty, the preview SHALL render a gap card with the server's note
verbatim, ONE selectable option per candidate (the candidate's look name plus
the server's confidence) and an explicit option that leaves the scene without a
look. The default SHALL be "leave without a look". A gap whose candidate list is
empty SHALL keep the existing plain uncertainty notice, and no option beyond the
server's list SHALL ever be offered.

#### Scenario: Both script-derivable candidates are offered
- **WHEN** a scene carries a gap uncertainty with a continuation candidate and
  a context candidate
- **THEN** the gap card offers both, each rendering its own look name
- **AND** the third option leaves the scene without a look, selected by default

#### Scenario: A gap without candidates offers nothing
- **WHEN** a gap uncertainty carries an empty candidate list
- **THEN** the plain uncertainty notice renders and no gap card, chip or
  selectable option appears for it

### Requirement: A pick travels as a continuity selection
The apply request SHALL carry one `continuity_selections` entry per resolved
gap, addressed by the gap's `scene_index` and the figure's preview-wide
`character_identity` (case-folded, whitespace-collapsed character name derived
from the gap's own scene — the identity the server validates against, never a
re-normalization of the server's note prose). The field SHALL be absent when no
gap was resolved. A resolved pick SHALL count as a review edit, so
`accept_as_is` / `edit_distance` stay truthful about the review.

#### Scenario: Picking the continuation sends the selection
- **WHEN** the reviewer picks the continuation candidate for the gap of figure
  "BEN" in the preview's scene index 1
- **THEN** the apply request carries one selection with `scene_index = 1`,
  `character_identity = "ben"` and `candidate = continued`
- **AND** the request reports `accept_as_is = false`

#### Scenario: An unresolved gap applies unchanged
- **WHEN** the reviewer leaves every gap without a look
- **THEN** the apply request carries no `continuity_selections` at all
- **AND** the apply is dispatched and reported like a pre-change client's

### Requirement: The dispatch states each gap's resolution
The apply card SHALL render one summary line per preview gap, naming the scene,
the figure and the look the pick applies — or that the scene deliberately stays
without one. A `409 ai-import.apply-unknown-continuity-candidate` SHALL surface
as the localized "refresh the preview and re-apply" narrative, keyed on the
stable `code` (never the server `detail`).

#### Scenario: Refreshed preview refuses a stale pick
- **WHEN** the apply is answered with `409
  ai-import.apply-unknown-continuity-candidate`
- **THEN** the apply card renders the refresh-and-re-apply copy
- **AND** the client does not re-derive or silently drop the pick

### Requirement: The preview header names the provider and model prominently
The preview screen SHALL render the configured extraction naming as a header
card above the typed payload — the model as the primary line, the provider as a
secondary line — instead of a quiet `bodySmall` footnote. A long model id SHALL
stay on one line and ellipsize rather than wrap. The EU AI Act Art. 50
transparency wording SHALL remain present as the card's caption, resolved by the
SAME shared sentence the submit disclosure and the apply section render, so the
promotion never weakens or forks the disclosure.

#### Scenario: A configured import preview
- **WHEN** the caller has a resolved AI configuration
- **THEN** the preview shows a header card with the model as the primary line,
  the provider as the secondary line, and the Art. 50 sentence as the caption

#### Scenario: A long model id
- **WHEN** the configured assistant model id does not fit the card width
- **THEN** the model line stays on one line, ellipsizes, and no layout overflow
  is reported

#### Scenario: Nothing configured, or the discovery failed
- **WHEN** the caller has no configuration or the configuration discovery fails
- **THEN** the header renders the existing "no AI configuration" copy as a
  single line, without a model or provider line, and never an invented name

### Requirement: A missing Decision Model is disclosed, non-blocking
When a resolved configuration carries no Decision Model (`decisionProvider` and
`decisionModel` both unset), the preview SHALL render a non-blocking warning
card that names exactly the two consequences — Pass-2 wardrobe continuity
suggestions and the scene/synopsis ratings are skipped — and states that the
import still runs. The card SHALL offer an affordance into the AI configuration
screen and SHALL NOT gate, disable, or delay the apply. When a Decision Model is
configured, nothing extra SHALL render.

#### Scenario: No Decision Model configured
- **WHEN** the resolved configuration has no `decisionProvider`/`decisionModel`
- **THEN** the preview shows the warning card with both consequences, the
  "runs anyway" statement and the link to the AI configuration

#### Scenario: A Decision Model is configured
- **WHEN** the resolved configuration carries both Decision Model fields
- **THEN** no warning card renders anywhere on the preview

#### Scenario: The warning does not block the dispatch
- **WHEN** the warning card is visible and the reviewer acknowledges the review
- **THEN** the apply action is enabled and dispatches as usual

### Requirement: An unread configuration is never reported as an unset Decision Model
The Decision Model warning SHALL render only from a resolved, non-failed
configuration read. A pending discovery, an unconfigured account, and a failed
discovery SHALL render no warning: a failed read is a different fact from "no
Decision Model is set", and the header degrades to the existing
"unconfigured" disclosure copy instead.

#### Scenario: The configuration discovery failed
- **WHEN** the configuration read fails
- **THEN** the header shows the "no AI configuration" copy and no Decision
  Model warning is rendered

#### Scenario: The discovery is still pending
- **WHEN** the configuration read has not resolved yet
- **THEN** no Decision Model warning is rendered

#### Scenario: No configuration exists at all
- **WHEN** the discovery resolved to "no configuration"
- **THEN** no Decision Model warning is rendered (the naming card already
  states the missing configuration)

### Requirement: The disclosure reads one cached discovery
The header card and the Decision Model warning SHALL resolve the caller's
newest non-revoked configuration through the existing cached discovery provider
— the same configuration the import handler resolves — issuing no additional
network call.

#### Scenario: Both surfaces on one screen
- **WHEN** the preview renders the header card and the warning
- **THEN** exactly one configuration discovery is performed per container

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

### Requirement: A row whose scoring failed states it
A preview row whose own scoring request failed (`DecisionRubric.scoringFailed`
is `true`) SHALL render an explicit, localized, non-blocking failure state
("Bewertung fehlgeschlagen – keine Sternchen" / "Scoring failed — no stars.")
in the same visual language as the other degradation surfaces. The row SHALL
NOT render a rating for it, and a row without any rubric — where the pass
genuinely never ran — SHALL render nothing extra: the failure state names a
failure, not an absence.

#### Scenario: The scoring request for a row failed
- **WHEN** a script preview row carries a rubric with `scoringFailed: true` and no score
- **THEN** the row renders the localized failure line and no star rating

#### Scenario: The pass never ran for a row
- **WHEN** a preview row carries no rubric at all
- **THEN** the row renders neither the failure line nor a rating

#### Scenario: A scored row is unaffected
- **WHEN** a preview row carries a score and a rubric with `scoringFailed: false`
- **THEN** the row renders its stars and no failure line

### Requirement: The preview and job view name the effective Decision Model
The preview header and the job cost card SHALL state the **effective Decision
Model** of the import from the job's recorded `decision_telemetry`: the
resolved `provider / model` when the pass ran, and otherwise the reason class —
distinguishing "no model configured" (`skipped_no_config`), "model unavailable"
(`client_unavailable`) and "scoring failed" (`scoring_failed`, with the affected
row count). The copy SHALL be keyed on the stable outcome class only, never on
backend prose, and SHALL be localized in German and English. A job that
recorded no outcome (a pre-#767 row, or a failed read) SHALL render no line at
all — never a guessed class.

#### Scenario: The pass ran with a configured model
- **WHEN** the job's `decision_telemetry.outcome` is `ran`
- **THEN** the preview header states the resolved `provider / model`

#### Scenario: The import ran without a Decision Model
- **WHEN** the job's outcome is `skipped_no_config`
- **THEN** the header states that no model was configured — distinguishable from the `client_unavailable` copy, which names the configured pair

#### Scenario: The scoring pass failed
- **WHEN** the job's outcome is `scoring_failed` with `failed_rows = N`
- **THEN** the header names the failure and the number of affected rows, in both locales (correct singular/plural)

#### Scenario: The job recorded no outcome
- **WHEN** the job carries `decision_telemetry: null`
- **THEN** neither the preview header nor the job cost card renders an outcome line

### Requirement: The Decision Model outcome is read without a second stream
The client SHALL read the job-level outcome through ONE snapshot read of
`GET /v1/ai-import/jobs/{id}` (or the job the screen already holds) and SHALL
NOT add a second SSE consumer: the job-status controller stays the app's only
event-stream subscriber (battery contract D5).

#### Scenario: The preview screen states the outcome
- **WHEN** the preview screen renders for a job with a recorded outcome
- **THEN** the outcome line appears without opening an event stream

#### Scenario: The cost card states the outcome
- **WHEN** the job status screen already holds the job
- **THEN** the cost card renders the outcome line from that job without an additional read

### Requirement: A blocked apply is a decision, not an error

When the apply dispatch is refused with `409 ai-import.apply-in-flight`, the
client SHALL classify the refusal from the server's own S1 extensions
(`apply_run_age_seconds`, `stale_after_seconds`) and SHALL render a decision
card inside the apply section, never the generic apply-error narrative:

- While `age <= stale_after`, the card SHALL state that an apply is running, name
  the owning run's last publication as a localized relative age, and show the
  whole minutes remaining until a takeover becomes possible (rounded up, never
  zero). The submit button SHALL be disabled in that state — a second dispatch
  could only be refused again — and NO takeover affordance SHALL be offered.
  The boundary is STRICT, mirroring the claim's own predicate: at exactly the
  window the server still refuses, so the run is still live.
- Once `age > stale_after` (including while the card stays open, derived from
  the server-measured age plus local elapsed time; no polling request), the card
  SHALL state that the run counts as abandoned and SHALL offer one explicit
  takeover action, which re-dispatches the same idempotent apply without a
  second confirmation dialog.
- When the refusal carries NO `apply_run_age_seconds` (an owner that published
  nothing), the card SHALL claim neither liveness nor abandonment: it SHALL say
  that no progress was reported, SHALL NOT fabricate an age or a countdown, and
  SHALL keep the apply action available while offering the same explicit action
  — the server's claim stays authoritative either way.

The classification SHALL NOT be mirrored client-side: a refusal that carries no
`stale_after_seconds` (a server predating the extensions) keeps the previous
bounded-wait behaviour and renders no takeover.

While a notice is stored, the client SHALL follow the apply-run stream: a
**progress** frame SHALL re-anchor the notice's local silence to that frame's
arrival (so a run that keeps publishing is never labelled abandoned by a
countdown started earlier, and no client/server timestamp comparison is made),
and the run's **end** frame SHALL clear the notice so the apply action is
released. An empty snapshot SHALL NOT clear it: `apply_progress: None` means "no
progress published", never "idle".

The reconciliation loop SHALL NOT steal an abandoned claim on its own: a refusal
older than the window SHALL end the loop after that single dispatch. A refusal
for a live run MAY consume the bounded attempt budget (the client's own earlier
POST may still be running), but the loop SHALL re-check the locally aged refusal
after each backoff and BEFORE the next dispatch: once the wait would carry the
age past the window, the loop SHALL stop and report the blocked run instead of
dispatching into a claim the server would hand over. If the budget ends on a
live refusal the outcome SHALL be reported as a blocked live run, never as an
unknown outcome; if it ends on an ambiguous timeout the earlier refusal SHALL be
discarded, so the outcome is reported as unknown.

#### Scenario: An abandoned run offers the takeover

- **WHEN** the refusal reports `apply_run_age_seconds = 700` and
  `stale_after_seconds = 600`
- **THEN** the apply card states that the run has stopped reporting progress and
  counts as abandoned, and names the 11-minute silence
- **AND** it offers the takeover action, and no apply-error line is rendered
- **AND** exactly one dispatch was made before the user's tap

#### Scenario: A live run still blocks

- **WHEN** the refusal reports an age inside the server's window
- **THEN** the card names the run and the remaining minutes until a takeover is
  possible
- **AND** the submit button is disabled and no takeover action is rendered
- **AND** an exhausted attempt budget leaves the card in that live state rather
  than reporting an unknown outcome

#### Scenario: The takeover re-runs the idempotent apply

- **WHEN** the user taps the takeover action
- **THEN** the client dispatches the same apply request again, with no second
  confirmation dialog
- **AND** a success clears the blocked-run card and follows the post-apply
  routing, because already-applied rows are skipped server-side

#### Scenario: A server without the extensions keeps the previous behaviour

- **WHEN** the refusal carries no `stale_after_seconds`
- **THEN** the client keeps its bounded wait and renders no takeover, because it
  never guesses a window the server did not state

### Requirement: One acknowledgement row per blocking decision

The apply card SHALL render exactly ONE acknowledge row per
`(scene_index, field)` pair, never one per preview entry. A preview may report
several blocking `field_ambiguity` entries for the same pair; they are one
question with several notes, so the client SHALL collapse them into one
decision (the first entry supplies the row's note, and the preview screen keeps
listing every entry with its own note).

The apply request SHALL carry exactly one `uncertainty_acknowledgement` per
acknowledged pair, and SHALL never carry the same pair twice. Apply SHALL stay
disabled until every pair is acknowledged. Acknowledging one pair resolves all
of its entries. Once every pair is acknowledged, this requirement no longer
blocks apply; the other apply gates (context, resolved group targets, and the
review checkbox) still apply.

#### Scenario: Duplicate blockers render one row

- **WHEN** the preview carries three blocking `field_ambiguity` entries for
  `(0, category)` and one for `(1, episode)`
- **THEN** the apply card renders two acknowledge rows
- **AND** toggling the first row acknowledges all three entries of `(0, category)`

#### Scenario: The wire list carries no duplicate pair

- **WHEN** the reviewer acknowledges every row and dispatches the apply
- **THEN** `uncertainty_acknowledgements` carries one entry per pair (two
  entries for the preview above), never a repeat
- **AND** the apply reaches the worker instead of failing at the API edge

#### Scenario: A single-entry preview is unchanged

- **WHEN** the preview carries exactly one blocking entry per pair
- **THEN** the panel renders one row per entry and the request stays
  byte-identical to the pre-#821 client

### Requirement: Aggregated provider-degraded state

The client SHALL derive one degraded-provider state from a job's own attempt
history and render it as a first-class state, instead of leaving the reviewer to
count identical per-attempt rows. The derivation SHALL:

- count the **consecutive newest** attempts whose stable `code` is the
  provider-attributed code (`ai-import.llm-provider-unavailable`) and stop at the
  first attempt with any other code, so an intervening non-provider failure ends
  the window rather than being absorbed into it;
- fire only at **two or more** such consecutive attempts — a single provider
  failure is a transient blip and keeps the per-attempt narrative alone;
- yield the attempt count, the failure window (oldest → newest of that run), the
  job's `next_attempt_at`, and whether the retry budget is spent;
- be keyed on the stable code ONLY. `last_error`/`error_summary` SHALL never
  participate in the derivation, and the legacy generic
  `domain.service-unavailable` SHALL NOT be folded in — it covers the mapping DB,
  the pricing read model and storage, so treating it as provider-attributed would
  name the wrong dependency.

The state SHALL name the dependency (the AI provider), never "a service", and
SHALL render:

- on the job-status screen as a banner carrying the attempt count, the window and
  the next attempt time (the existing live "next retry in …" affordance, never a
  second countdown), and
- on the jobs list row as a compact line derived by the SAME function, so the two
  surfaces cannot disagree about whether the provider is degraded.

A job whose attempts carry no code, an unknown code, or a single provider failure
SHALL render exactly as before.

#### Scenario: Repeated provider failures become one degraded state

- **WHEN** a `failed` job carries three consecutive newest attempts with
  `code = ai-import.llm-provider-unavailable`, ~17 minutes apart, with
  `next_attempt_at` set
- **THEN** the job-status screen renders a "AI provider degraded" banner naming
  the provider, the three attempts, their window and the next attempt time
- **AND** the jobs list row for the same job renders the compact form of the same
  state

#### Scenario: A single provider failure stays a transient per-attempt reason

- **WHEN** a job carries exactly one attempt with the provider code
- **THEN** no degraded banner renders; the retryable card shows the localized
  transient provider narrative for that attempt

#### Scenario: A non-provider failure in between ends the window

- **WHEN** the two newest attempts are a provider failure followed by a
  `domain.service-unavailable` attempt (a storage/database failure)
- **THEN** the degraded state does not render, because the consecutive
  provider-attributed run is shorter than two

### Requirement: Terminal copy after provider failures never promises a retry

A job in a terminal failure state (`dead_letter`, `payload_unavailable`) whose
history is provider-attributed SHALL render terminal copy that

- states that the retry budget is spent, **only where that is derivable** — a
  `dead_letter` whose newest attempt carries the retryable provider code — and
- names what the user can do: delete the failed job from the list (uploading the
  same bytes deduplicates onto it) and start again once the provider answers.

It SHALL NOT render "the next attempt may succeed" (or any other promise the
state cannot keep) on a terminal card, and the per-attempt terminal reasons SHALL
make no **exhaustion** claim: `dead_letter` also happens on a non-retryable
failure and `payload_unavailable` is terminal for a different reason. A
`dependency.auth-failed` history likewise SHALL NOT describe retries that cannot
happen (that failure is permanent).

#### Scenario: Dead-lettered provider outage reads as spent, not retryable

- **WHEN** a job reaches `dead_letter` after provider-attributed attempts
- **THEN** its terminal card names the provider, says the retry budget is spent,
  and offers the recovery narrative instead of the transient retry promise

### Requirement: The preview header names the provider/model the job USED

The preview's naming card SHALL name the provider/model pair the import job
actually ran with, sourced from the job's content-free telemetry
(`AiImportJob.telemetry`), as its primary line. The card SHALL NOT render the
currently configured pair as its primary line, and SHALL NOT repeat the same
pair in a second line or caption.

The configured pair SHALL render as a second, subordinate line ONLY when it
differs from the used pair by provider or by model; when the two agree the card
renders no second line. The comparison SHALL be field-wise over the KNOWN
telemetry halves: a missing or blank model/provider is unknown, so a snapshot
carrying only one half never produces a difference claim about the other, and
every known half is compared with its configured counterpart.

Both header lines SHALL be bounded to one row and ellipsized, so a long curated
model id can neither wrap the header nor push the review rows off screen.

The telemetry snapshot SHALL be read through the job snapshot route
(`getJobAndCache`), never through the SSE watch and never through a second
projection lookup, and the app's single SSE consumer SHALL remain the job-status
controller.

#### Scenario: The configured model differs from the used one

- **WHEN** the job's telemetry records `mistral-large-3` at `eurouter` and the
  caller's configuration names `assistant-model-1` at `openai`
- **THEN** the card's primary line names `mistral-large-3 (eurouter)` as the
  model used
- **AND** a second line names `assistant-model-1 (openai)` as the currently
  configured, differing model
- **AND** no third line repeats the configured pair

#### Scenario: The configured model equals the used one

- **WHEN** the job's telemetry and the caller's configuration name the same
  provider and model
- **THEN** the card renders exactly one line — the used pair
- **AND** no "differs" line and no configured caption render

#### Scenario: A job without telemetry claims no comparison

- **WHEN** the job recorded no telemetry (a pre-#609 row) or the snapshot cannot
  be read
- **THEN** the card names no used model
- **AND** it names the configured pair once, in wording that states the pair is
  currently configured rather than used
- **AND** it renders no "differs" line

#### Scenario: A used pair survives an unconfigured account

- **WHEN** the job's telemetry records a pair but the account has no
  configuration (deleted after the import, or the discovery failed)
- **THEN** the card still names the used pair
- **AND** it claims no comparison

#### Scenario: No invented names

- **WHEN** the account is unconfigured AND the job recorded no telemetry
- **THEN** the card renders the existing "no AI configuration" copy
- **AND** no provider or model name is rendered at all

### Requirement: The episode picker renders only while the apply context is missing

The apply card SHALL render the episode-picker affordance
(`ai-apply-pick-episode`) ONLY while the apply context is unresolved, together
with the missing-context notice that explains it. With a resolved context the
card SHALL render nothing under the submit button, and the
`state.context == null` recovery SHALL stay reachable.

#### Scenario: A resolved context shows no stray picker

- **WHEN** the preview opens with a persisted apply context
- **THEN** the apply card renders no `ai-apply-pick-episode` affordance
- **AND** nothing else is rendered between the submit button and the card's end

#### Scenario: A missing context still offers the picker

- **WHEN** the job carries no apply context
- **THEN** the apply card renders the missing-context notice AND the picker
  affordance beside it
- **AND** the submit button stays disabled until an episode is picked

### Requirement: The import submit action requires a picked document

The submit affordance SHALL stay disabled (`onPressed: null`) until a document
is picked, for both the script and the schedule flow, and SHALL disable again
once a successful submit clears the pending document. The in-dispatch
missing-document guard SHALL remain as a backstop that is not reachable from the
UI. The file row's "no file picked" line SHALL provide the visible explanation
of the disabled state, and the row SHALL derive its displayed filename from the
pending document, so clearing the document (a kind switch, or a successful
submit) returns the row to that line instead of naming a file the dispatch no
longer carries.

#### Scenario: No file picked

- **WHEN** the screen opens (no document in the pending-document state) with a
  resolved target
- **THEN** the submit affordance is disabled
- **AND** the file row states that no file is picked
- **AND** zero uploads are dispatched in either kind

#### Scenario: A file is picked, then cleared

- **WHEN** a document is picked
- **THEN** the submit affordance becomes enabled (given a resolved target)
- **AND** it disables again when the pending document is cleared (a kind switch,
  or a completed submit)

### Requirement: The post-apply hop resolves its target from the persisted summary

The post-apply navigation hop SHALL resolve its target episode from the apply
response when that response names applied episodes, and otherwise from the job's
**persisted** applied-episode summary, read from the local cache. It SHALL NOT
drop straight to the request's episode while a durable answer exists.

The fallback is load-bearing and not cosmetic: a re-apply of an already-applied
preview dispatches nothing (every row is settled by its confirmed mapping), so
its response carries an empty list while the job still says where the rows are.

Because a persisted summary describes **earlier** applies, it SHALL only answer
WHERE to go: the report published at the destination SHALL list as "also
applied" only the episodes **this** request dispatched (the response's own
list), never the historical summary's remaining entries, so no earlier row count
is attributed to the request the user just confirmed.

The fallback SHALL remain a cache read: the navigation path SHALL NOT wait for,
or depend on, the network. An absent, offline or undecodable cached summary SHALL
degrade to the existing honest behaviour — navigation is skipped and the outcome
card stays in place. No id or number SHALL ever be invented.

The resolution SHALL tell the caller whether the server knows a target episode at
all, so the "the imported episode could not be opened" hint is shown exactly when
a target exists but does not resolve from the read caches. A job with no target
episode whatsoever — a schedule merge, or nothing ever applied — SHALL keep the
outcome card **without** that hint.

A successful apply SHALL reconcile the job projection (re-run the jobs list and
drop the job-scoped summary read) so the server-derived summary reaches the cache
for a later hop, without the hop itself awaiting it.

#### Scenario: A re-apply with an empty response still lands on the imported episode

- **WHEN** an apply answers an empty applied-episode list but the cached job row
  carries a persisted summary naming episode 299 "Erlösung"
- **THEN** the app leaves the review screen for the Script destination with that
  episode in scope

#### Scenario: A persisted target never donates its historical counts

- **WHEN** the persisted summary names two episodes with 57 and 4 rows
- **THEN** the destination report lists no "also applied" episode for this
  request, because it dispatched none

#### Scenario: A known target that cannot be resolved still says so

- **WHEN** the persisted summary names an episode whose season the read caches do
  not hold
- **THEN** the review screen stays with the outcome card AND the explicit hint

#### Scenario: An offline or unknown job degrades honestly

- **WHEN** the response names no episode and the cached job row is unknown or its
  summary undecodable
- **THEN** navigation is skipped, the outcome card stays, and nothing is invented

### Requirement: The target card offers "Block extrahieren" as a per-dispatch choice
The import target card SHALL offer a third action, **"Block extrahieren"**, next
to *Block wechseln* and *Block anlegen*, whenever the target season is known and
the season is not in the "no block at all" arm. In that arm the block-less
dispatch is already the only target that exists and applies without a tap, so no
duplicate choice SHALL be offered there.

Choosing the action SHALL mark **this dispatch** as block-less: the upload SHALL
carry `X-Declared-Season` and SHALL omit `X-Active-Block`. The choice SHALL NOT
clear or overwrite the ambient block scope (`activeBlockProvider`), because that
scope is the shell's block pill and the target of other screens.

The choice SHALL be per dispatch and SHALL be cleared by a kind switch and by a
successful dispatch, so a stale choice can never turn a later upload block-less
without the user asking for it.

#### Scenario: A season with a block offers the third action
- **WHEN** the target season resolves to an existing block and the target card renders
- **THEN** the card shows "Block wechseln", "Block anlegen" **and** "Block extrahieren"
- **AND** no block is dropped from the dispatch unless the user chooses the third action

#### Scenario: Choosing "Block extrahieren" dispatches block-less
- **WHEN** the user selects "Block extrahieren" and submits a picked document
- **THEN** the upload carries the declared season and no `X-Active-Block`
- **AND** the ambient block scope is still the block it was before

#### Scenario: The choice does not outlive its dispatch
- **WHEN** a dispatch with the choice has succeeded, or the user switches the document kind
- **THEN** the choice is cleared and the next dispatch carries the resolved block again

#### Scenario: A resolved block still wins by default
- **WHEN** a block is resolved and the user never selects "Block extrahieren"
- **THEN** the dispatch carries that block in `X-Active-Block`

### Requirement: The card states the deferred target while "Block extrahieren" is active
While the choice is active the target line SHALL render the season with the
block stated as unknown (`aiImportTargetUnknownBlock`) together with the
existing block-less hint, and the action SHALL become an **undo** that restores
the resolved line. The card SHALL NOT keep showing the previously resolved block
while the dispatch carries none — the visible target and the dispatched headers
SHALL remain one value.

The undo SHALL restore the resolved line without mutating the ambient scope, so
no restore logic is needed.

#### Scenario: Deferred target is stated, not the previous block
- **WHEN** the user selects "Block extrahieren" on a card that showed `Block 1`
- **THEN** the line reads the season with `Block unbekannt` and the block-less hint
- **AND** the submit affordance stays enabled (the season is the authorization scope)

#### Scenario: Undo restores the resolved line
- **WHEN** the user activates the undo of the "Block extrahieren" action
- **THEN** the line shows the previously resolved block again
- **AND** the ambient block scope is unchanged by the toggle and its undo

### Requirement: After extraction the script's block becomes the target
For a dispatch that chose "Block extrahieren" the client SHALL let the block the
script states become the job's target through the established adoption path: the
block carrying that number SHALL be attached when the target season has it, and
a block with that number SHALL be created and then attached when the season does
not. No second adoption implementation SHALL be introduced for this entry point.

When the script states no block, no number SHALL be invented: the preview SHALL
keep its manual affordances (pick an existing block, or create one by hand).

#### Scenario: The script's block already exists
- **WHEN** the extracted script states `Block 98` and the target season already has a block with number 98
- **THEN** the job's target is attached to that block without a further decision by the user

#### Scenario: The script's block does not exist yet
- **WHEN** the extracted script states `Block 98` and the target season has no block with number 98
- **THEN** a block with number 98 is created in that season and attached as the job's target
- **AND** the created block carries no shooting dates (the script states none)

#### Scenario: A script without a block statement stays undecided
- **WHEN** the extracted document states no block number
- **THEN** no block number is derived from the ambient scope or invented
- **AND** the preview keeps the manual pick/create affordances, and an apply without an attached target is refused with the existing `409 ai-import.target-missing`

