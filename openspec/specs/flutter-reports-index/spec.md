# flutter-reports-index Specification

## Purpose
Defines the episode's report **index** — a pure navigation surface that
lists an episode's projected shooting days (server order) with their own
label, date and per-day finality read directly from `wrapped_at`, and
pushes the existing day-scoped report screen per row. The index renders
no report content of its own, issues no fetch of its own, and reuses the
day-scoped membership gate as a pre-check for the destination screen
(change `reports-season-report-index-571`, the reachability half of
issue #571).

### Requirement: Episode-Scoped Report Index Surface

The client SHALL provide a report index screen scoped to one episode, pushed
from that episode's shooting-days screen via a labelled action
(`reportsIndexOpen`, label `Berichte`). The index SHALL list the episode's
**projected** shooting days in the same server order the shooting-days
list uses (`order_key ASC`, never re-sorted client-side), each row showing
the day's own `label`, its `date` and a per-day finality state, and each row
SHALL be a single tap target that pushes the **existing** day-scoped
`ReportsScreen` for that day with a `ReportDayScope` built from the day's id
and the season id threaded into the navigation context.

The index SHALL render **no report content**: no Soll/Ist rows, no flag
chips, no counts, no PDF cards. The day-scoped report screen remains the
only renderer of report data in the app.

The index SHALL read the episode's day rows from the **existing**
`shootingDaysControllerProvider(episodeId)` state and SHALL issue **no**
report or day-list HTTP request of its own. It SHALL inherit the day list's
projection-lag semantics unchanged: cached rows remain visible and
stale-indicated when a refresh fails, an `AsyncError` renders the error
state keyed on the stable problem `code`, and pull-to-refresh reconciles
through the same controller.

#### Scenario: Opening the index from the shooting-days screen

- **WHEN** the user taps the labelled reports action (`reportsIndexOpen`) on
  the shooting-days screen of an episode that has shooting days
- **THEN** the index screen renders with one row per projected shooting day,
  in the same order the shooting-days list shows, and no network request
  beyond the day list's own fetch has been issued

#### Scenario: A row opens that day's report

- **WHEN** the user taps the index row for shooting day `day-1`
- **THEN** the day-scoped `ReportsScreen` pushes for `day-1` with a
  `ReportDayScope` carrying that day's id and the episode's season id, and
  the index issues no report request of its own before the push

#### Scenario: The index renders no report data

- **WHEN** the index screen is rendered with projected rows present
- **THEN** the screen shows day label, date and per-day finality only — no
  Soll/Ist row, no flag chip, no planned/actual count, no PDF card is
  rendered on the index

### Requirement: Server-Derived Per-Day Finality On The Index

Each index row SHALL render a per-day finality state read **directly** from
that day's own `wrapped_at` field in its `ShootingDayView` DTO —
`abschließend` when `wrapped_at` is present, `offen` otherwise. The client
SHALL NOT recompute, infer, or aggregate finality, and the index SHALL NOT
render any episode-, season- or scene-level finality verdict, any
"x of y days complete" summary, or any other aggregate of the days'
finality. The finality shown on the index and the `final` flag in the
day-scoped report derive from the same `wrapped_at` field and SHALL agree
for a given day.

#### Scenario: A wrapped day is marked final

- **WHEN** the index renders a row whose `ShootingDayView.wrapped_at` is
  present
- **THEN** the row carries the `abschließend` state, and opening that row's
  report shows the same day as final

#### Scenario: An open day is marked open

- **WHEN** the index renders a row whose `ShootingDayView.wrapped_at` is
  `null`
- **THEN** the row carries the `offen` state, and no finality banner is
  implied

#### Scenario: No aggregate verdict is offered

- **WHEN** the index renders a mixture of wrapped and open days
- **THEN** no episode-, season- or scene-level verdict, no aggregate count
  of completed days, and no aggregate progress figure is rendered anywhere
  on the screen

### Requirement: Day-Less And Pending States On The Index

An episode whose shooting-day list is empty and not failing SHALL render a
plain-language empty state (`reportsIndexEmpty`) naming the Soll/Ist report
as what becomes available once a shooting day is planned. The index SHALL
NOT offer a report affordance for a day-less scope, because the report
routes are day-scoped in the contract itself
(`/v1/shooting-days/{id}/report/*` only) — an episode with no day has
nothing to report against. A day that is still an optimistic command
acknowledgement (not yet projected) SHALL NOT be listed on the index; the
screen SHALL show the day list's stale/pending indicator instead, because
an unprojected day carries no server-derived `wrapped_at` to report.

#### Scenario: Episode without shooting days

- **WHEN** the index renders for an episode whose projected day list is
  empty and no fetch is failing
- **THEN** the empty state renders with copy naming the Soll/Ist report as
  what becomes available once a shooting day is planned, and no day row and
  no report link is offered

#### Scenario: A pending day is not listed

- **WHEN** the day list holds a shooting day that is still an optimistic
  overlay and not yet projected
- **THEN** the index does not list a row for it and shows the stale/pending
  indicator instead of a row whose finality is unknown

#### Scenario: Archived days are inherited-excluded

- **WHEN** the index renders for an episode that has archived shooting days
- **THEN** those days are absent from the index, inheriting the
  shooting-days list's server-side exclusion of archived days

### Requirement: Client-Side Authz Pre-Check Before Navigation

The index SHALL evaluate the same client-side membership gate the day-scoped
report screen uses — `currentMembershipProvider(seasonId)` →
`canViewReports` — before the user navigates into a day report, and SHALL
render the localized 403 narrative with **zero** requests issued on denial
(`report.forbidden`; `membership.pending` / `membership.unavailable` while
membership is unresolved). The gate SHALL follow the backend-computed
`has_active_costume_role_in_season` flag only: an unknown capability string
SHALL never enable it. The index SHALL NOT introduce a new authorization
capability, and its gate is a pre-check for the destination screen — the
index itself fetches no protected data.

#### Scenario: Denied membership blocks the index

- **WHEN** the membership read for the season resolves with
  `has_active_costume_role_in_season: false`
- **THEN** the index renders the 403 narrative keyed on `report.forbidden`
  and issues zero requests — neither a day-list refresh nor a report fetch

#### Scenario: Unresolved membership never renders as permitted

- **WHEN** the membership read is still loading or has failed
- **THEN** the index renders the gate state keyed on `membership.pending` /
  `membership.unavailable` and does not treat the scope as permitted

#### Scenario: An unknown capability string never enables the gate

- **WHEN** a future backend returns a capability string the client does not
  know
- **THEN** the gate follows the backend-computed
  `has_active_costume_role_in_season` flag only and never enables itself
  from the unknown string
