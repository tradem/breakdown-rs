<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# ADR-035: Production-Kind-Flexible Hierarchy — `Project` as the Container Target

**Status**: Accepted
**Date**: 2026-10-05
**Author**: Tobias Rademacher (@tradem)
**Related**: ADR-001 (Hexagonal Architecture), ADR-002 (Event Sourcing & CQRS),
ADR-019 (Costume Photo Storage), ADR-031 (HTTP Error Surface)
**Source change**: GitHub issue #531 — strategic parent of the 0.4.x series
(#532, #533, #534, #535)

## Context

The domain is hard-wired to the TV-series production shape. The container
chain is:

```
Series (opaque UUIDv7, not an aggregate) → Season → Block → Episode → Scene
```

`Season` is the smallest container that today carries costume roles, blocks,
episodes and shooting days. For **film** and **theatre** productions that
concept does not exist — there are no seasons there, but there are other
brackets: production unit, run time, premiere period, shooting block.

Two distinct defects are visible in the current code, and it matters that they
are not the same one:

1. **The security layer is typed by a production form.** Costume-photo
   authorization runs through a *season-typed* predicate:

   ```rust
   // crates/core/src/membership/ports.rs:99
   async fn has_active_costume_role_in_season(
       &self, season_id: SeasonId, user_id: UserId,
   ) -> Result<bool, DomainError>;
   ```

   `SeasonId` is therefore burned into the security layer. For a film or a
   theatre production, `SeasonId` is no longer a sensible container — and
   authorization is exactly the layer that must *not* know which production
   form it is guarding.

2. **The name of the top container is itself TV-shaped.** The position of
   `Series` is already right: it is the transcendent bracket, the tenancy
   seam (`docs/security/security-architecture.md` §1), and the audit-journal
   scope (`has_active_membership_in_series`, `ports.rs:88`). But the *word*
   "Series" names one specific production form. A container named after the
   TV form cannot honestly be the tenant boundary of a film production.

The first defect is being fixed in the 0.4.x series (chiefly #535). It is
fixed *blindly* unless the rationale is recorded — without a boundary rule, the
next feature re-bakes a production-form-specific id into a new authorization
predicate or a new uniqueness key, and the 0.4.x issues look like four
unrelated refactors.

Cracks already visible in the model, all pointing the same way:

- **#453** — the costume repertoire (`projection_costume_season`) makes a
  costume span *several* seasons. The costume is no longer bound to exactly one
  season, so a season-typed predicate cannot even name its full scope.
- **#513** — the photo gate had to *derive* a season through
  `costume.character_id` purely to satisfy a season-typed predicate; the real
  scope (the repertoire) was present in the projection and never read.
- **#534** — makes the repertoire real aggregate state; the binding is
  cross-season by construction.
- **#586** — cross-aggregate uniqueness keys are spelled
  `(series_id, number)` for season, block and episode numbering. A
  production-form-specific term sits in the storage key of an invariant that
  applies to any container.

Constraints this decision must respect:

- **Event-sourced data already exists** (ADR-002). Nothing in this decision
  may require a data migration; the wire contract (`backend/openapi.yaml`)
  and the projection column names stay untouched.
- **No DI frameworks, no framework-coupled domain** (ADR-001). The
  authorization predicate lives in a `core` port; the resolution of "which
  container does this entity belong to" is an infra concern.
- **The client mirrors the hierarchy.** `frontend-flutter/AGENTS.md` §2
  describes the chain as a navigation tree; it must be made consistent with
  this ADR.
- **Single-tenant v1.** The tenancy seam *is* the `SeriesId`; renaming the
  term must not change the tenant boundary.

## Decision

### D1 — The container target is `Project`, not `Series`

`Project` is the production-neutral name for the container that is today
called `Series`. It is a **1:1 rename of the term, not a new level**:

| | |
|---|---|
| Today | `Series` (opaque `SeriesId`) → `Season` → `Block` → `Episode` → `Scene` |
| Decided | `Project` (opaque `ProjectId`) → *configurable containers* → `Scene` |

`Project` replaces `Series` at the same position with the same UUIDv7 values
and the same tenant boundary. The `Series` term is dissolved together with the
`Season` term — there is no `Project → Series → Season` chain, because nothing
in the product requires a level above the production itself.

The reasoning for 1:1 rather than "add a level above": the defect is the
*word*, not the *position*. `SeriesId` is already the tenancy seam, already the
audit scope, already the uniqueness-key prefix. Adding a `Project` level above
it would move the tenancy seam, invent a level no user ever names, and make
every existing projection column and event payload wrong — to fix a naming
problem.

`Project` is the level **below which containers become configurable**. It is
fixed; what sits under it is not (see D4).

### D2 — Why not generalize `Season` into a generic "scope"

Weighed and rejected. `Season` today carries:

- `number` uniqueness scoped to `(series_id, number)`;
- `Episode` and `Block` children;
- the costume repertoire (`projection_costume_season`);
- the costume-category vocabulary (a projector-driven seeding saga, issue #543);
- `Character` scope (`Character.season_id`).

Generalizing it into a generic scope/container aggregate is conceivable, but
the name and the invariants are TV-specific:

1. A generic container would need a **union of children** — episodes and
   blocks for TV, units for film, runs for theatre. Every production form
   would then model the children it does not have, or the aggregate would carry
   an open variant that projectors must branch on forever.
2. The **numbering invariant is not universal**. "Episode 3 of season 2" is a
   TV concept; "unit 2 of a shoot period" is not the same invariant. A
   generalized container would carry a numbering invariant that is meaningless
   for some forms and load-bearing for others.
3. It would put a **TV-shaped aggregate at the top of the hierarchy**, exactly
   where the tenancy boundary needs a production-neutral concept.

`Season` is therefore a *configurable child container of `Project`* — dissolved
only when a second production form actually has to land, and dissolved as a
child-container concept, not by generalizing the current aggregate in place.

### D3 — Domain configuration points (**non-normative**)

This section records **what must become configurable, not the concrete
solution**. No container model, schema or trait is prescribed here; a
concrete model is a future ADR with its own migration plan.

| Production form | Container chain (illustrative) |
|---|---|
| TV series | `Project` → `Season` → `Block` → `Episode` → `Scene` |
| Film | `Project` → `Unit` → `Scene` |
| Theatre | `Project` → `Run` → `Performance` → `Scene` |

What is common to all three chains, and therefore what a future container model
must keep expressible:

- `Scene` is the atomic shootable unit in every form.
- A *scheduleable day* exists in every form (today `ShootingDay`, an
  Episode-scoped `Drehtag` aggregate).
- `Character` and `Costume` live under **the smallest container that carries
  the costume repertoire** — that container is form-dependent and must not be
  assumed to be a season.
- A costume may belong to **more than one container over its life** (build in
  one, carried over into another) — the repertoire is m:n by construction
  (#453, #534), not a `season_id` column.
- A *block* of consecutive work is what scheduling, numbering and authorization
  scopes hang off; only its name and parent are form-dependent.

### D4 — Boundary: what stays fixed to `Project` (**normative**)

Fixed to `Project` — these are rules, and a change that violates one needs its
own ADR:

- **B1 — Tenancy boundary.** `ProjectId` is the tenancy seam
  (`docs/security/security-architecture.md` §1). It renames `SeriesId` and
  does not move: same UUIDv7 values, same tenant boundary, no multi-tenancy
  change.
- **B2 — Authorization level.** Authorization predicates are typed by the
  **authorization level**, never by a production-form-specific container. A
  new predicate takes a `ProjectId`; no new `*_in_season` predicate may be
  added. The existing `has_active_report_archive_role_in_season` is
  grandfathered and must not be joined by siblings.
- **B3 — Audit-journal scope.** The membership audit journal stays
  project-scoped (`AuditRepository::list_by_series` → `list_by_project`,
  `crates/core/src/audit/ports.rs:59`).
- **B4 — Uniqueness keys.** Cross-aggregate uniqueness constraints and
  reservation-stream keys are prefixed with the `ProjectId`, not a
  form-specific id: today's `(series_id, number)` for season / block / episode
  numbering becomes `(project_id, number)` (see the open ES-native reservation
  stream work in #586).
- **B5 — No schema churn in this ADR.** Projection columns and OpenAPI field
  names keep the spelling `series_id` until a dedicated migration ADR renames
  them. The rename is deliberately *not* bundled here: the event store already
  holds events that must replay unchanged.

  **B5 outcome after issue #591 (2026-10-07): still in force, deliberately.**
  #591 covered layers 1 and 2 and left every persisted and published spelling
  on `series_id`:
  - **projection columns** `series_id` (`projection_season/_block/_episode`,
    `projection_audit`) — untouched, no migration;
  - **OpenAPI fields** `series_id`, including the `?series_id=` query
    parameters — untouched; the only OpenAPI delta is the *schema name*
    `SeriesId` → `ProjectId`, which is wire-neutral (both render as
    `type: string, format: uuid`) and leaves the generated Dart client's
    `seriesId` accessor unchanged;
  - **event payload fields and `EventMetadata`** — untouched via
    `#[serde(rename = "series_id")]`, for the `event_key` reason above.

  Renaming the projection columns and the 32 OpenAPI fields therefore remains
  **open work**, and it is a *breaking* change: per ADR-021 D2/D3 it needs a
  `/v2` path version, an 8-week concurrent `/v1`+`/v2` deprecation window
  (D4), a column/index migration, and a `regen-client.sh` diff. That is a
  second subsystem (wire + storage) and a second contract change — the size
  gate, which is why it was not folded into #591. It should be its own change
  with its own ADR; until it lands, **B5 is unchanged and new code must keep
  the `series_id` spelling on those surfaces.**

Configurable **below** `Project`:

- **C1** which containers exist (season/block/episode vs unit vs run);
- **C2** which invariant binds at which container (numbering);
- **C3** which container carries the costume repertoire and the `Character`
  scope.

### D5 — Prescriptive seam sketch

The seams the 0.4.x issues must converge on. These are prescribed; the
container model behind them is not.

- **S1 `ProjectId` in `core::shared`.** Replaces `SeriesId`
  (`crates/core/src/shared.rs:109`). The rename change is **deferred past 0.4.x** —
  the 0.4.x issues cite this ADR and add no new `SeriesId`-typed surface —
  and lands as its own change. Tracked in issue #591.

  **Not a mechanical rename.** The identifier lives on three layers with
  three different rules, and conflating them is the main risk:

  1. *Rust type name* (`SeriesId` → `ProjectId`) is wire-neutral — the type is
     `#[serde(transparent)]` over `Uuid`, so the JSON value is unchanged. Watch the
     `utoipa` schema names, which are derived from the Rust type.
  2. *Command/event field names* (`series_id` → `project_id`) are **forbidden for
     events**: the event store already holds serialized events and ADR-002
     forbids rewriting history. A blind rename surfaces as a projector dying
     on deserialization (SQLSTATE 22, dead-letter via the #37 path), not as a
     compile error. Commands are not persisted and may be renamed freely;
     events need `#[serde(rename = "project_id", alias = "series_id")]` or an unchanged
     wire field. The choice must be recorded, not improvised.
  3. *Projection column + OpenAPI field names* are a **breaking change**
     (ADR-021, 32 fields in `openapi.yaml`) and need their own
     migration plus a deprecation window.

  Whether #591 covers layer 3 or stops after layers 1 — 2 is a decision for that
  issue; the outcome updates **B5** below. What is normative here: the
  rename must never be a single undifferentiated sweep across the three.

  **RESOLVED by issue #591 (2026-10-07).** #591 shipped layers **1 and 2**
  only and did **not** touch layer 3 — see the **B5 outcome** below. Two
  consequences that were *not* visible when this ADR was written:
  1. **Layer 1 needs no compatibility alias.** `core` is an internal
     workspace crate with no out-of-tree consumers, so `SeriesId` was removed
     outright rather than kept as a `pub type` alias; a new ast-grep rule
     (`backend/rules/no-stale-series-id.yml`) now fails CI on any stale
     reference.
  2. **Layer 2 must pin the wire key, not alias it.** The obvious-looking
     `#[serde(rename = "project_id", alias = "series_id")]` is **unsafe
     here**, and the reason is specific to this codebase:
     `projection_audit.event_key` is derived from the **re-serialized** event
     (`write_audit_row`: `format!("{entity_type}:{entity_id}:{event_type}:{payload}")`),
     and `ON CONFLICT (event_key) DO NOTHING` is what makes projector
     redelivery idempotent. An alias reads old events correctly — so it looks
     right — but re-serializes them under a different key, which silently
     **duplicates every pre-rename audit row** on replay. No compile error,
     no dead-letter, no failing test. The shipped shape is therefore
     `#[serde(rename = "series_id")]` on a field named `project_id`: byte-
     identical re-serialization, stable `event_key`. Pinned by
     `crates/integration-tests/tests/project_id_rename_replay.rs`.
  A second, smaller trap in the same layer: `utoipa` derives schema property
  names from the **Rust field name**, so a renamed field silently renames the
  OpenAPI field — i.e. layer 3 leaking into a layer-1/2 PR. Every wire-visible
  struct therefore carries an explicit `#[schema(rename = "series_id")]` (or
  `#[param(rename = "series_id")]` for query params) alongside the serde pin.
- **S2 — Authorization seam.** `has_active_costume_role_in_project(
  project_id, user_id)` is the shape (the 0.4.x #535 work). Same role set as
  today's season-typed predicate (`costume_designer`, `wardrobe_supervisor`,
  `costume_assistant`), one level up, typed by B2.

  **How the costume-photo boundary is enforced under S2** — this is a
  deliberate *widening*, not a mechanical re-bending, so it is spelled out
  rather than left to the implementing PR (#535 flags it as "deliberate scope
  widening (review required)"):

  - *Today* the gate is `authorize_costume_scoped`
    (`crates/api/src/handlers/mod.rs:757`): it computes the costume's **season
    scope** — its character's season ∪ its repertoire seasons
    (`costume_season_scopes`, `:681`) — and calls the season-typed predicate
    for **each** scope, passing on any `true`.
  - *Under S2* the gate resolves **which project owns the costume**
    (S3; `series_id_for_costume`, `:616`, already carries the repertoire
    fallback) and calls the **project-typed** predicate **once**. Photo
    access is therefore **project-wide**: holding a costume-department role in
    any active block of the owning project is sufficient, and the season union
    is **not** an authorization input.
  - The repertoire remains the costume's **domain** scope — it decides which
    seasons list the costume, which project the costume resolves to, and what
    the season-scoped reports are about. Only the *authorization* level moves
    up. B2 is not violated: it forbids **adding** season-typed predicates, and
    S2 **removes** the existing season-typed call from the photo path.
  - The client mirrors the rule (`frontend-flutter/AGENTS.md` §5): a client
    that still denies on the season union will block flows the server permits
    and silently drift, which is the #513 mirror lesson.
- **S3 — Container-resolution seam.** The ad-hoc handler helpers
  `series_id_for_costume` and `series_id_for_costume_category`
  (`crates/api/src/handlers/mod.rs:616` / `:539`) are replaced by one
  `ContainerResolver` port in `core`, answering
  `project_of(entity) -> Option<ProjectId>`, implemented in `infra`. Two rules
  carry over from `AGENTS.md` §1: the API edge is the only legitimate
  read-model consumer, and the resolution is **best-effort** — a projection
  miss yields `None`/default and never blocks command processing.
  This is the seam that makes a second production form cheap: a new form needs
  one resolver row, not one authorization predicate per form.
- **S4 — Uniqueness naming.** Reservation-stream keys (see #586) are keyed by
  `ProjectId`, so the naming follows B4 from the start.

## Consequences

### Positive

- The 0.4.x issues (#532–#535) get a documented rationale and stop looking
  like isolated refactors; each of them can cite B2/S2/S3 instead of
  re-deciding the boundary.
- Authorization becomes production-form-agnostic: a film or theatre production
  inherits the existing role model without a new predicate per form (B2, S3).
- The top container's name stops lying about the product's scope, which is the
  cheapest possible fix for the naming defect (D1) — no migration, no new
  level, no change to the tenant boundary (B1, B5).
- The costume repertoire's m:n nature (D3, #453/#534) stops being a TV-shaped
  exception and becomes the general rule, which is what the wardrobe lifecycle
  actually needs across seasons *and* across forms.

### Negative

- Two terms now coexist in prose and code: `SeriesId` (persisted, on the
  wire, in the projections) and `ProjectId` (the decided term). Every doc that
  names the chain must say which one it means. The rename is deferred, so this
  is a real, bounded cost.
- B2 constrains future feature work: a genuinely season-scoped permission
  (something only a season lead may do) can no longer be expressed as a new
  season-typed predicate. It has to be expressed at the project level or
  deferred to the container model — this ADR accepts that restriction
  deliberately, because the alternative is one predicate per production form.
- D3 is non-normative on purpose, so the concrete container model — the actual
  hard part — remains undecided. That work is **not** scheduled by this ADR and
  must not be smuggled into a 0.4.x PR.
- The prescriptive seams (D5) constrain the shape of #535 and its follow-ups;
  a solution that does not fit them needs an explicit deviation, not a silent
  divergence.

### What to watch

- Any new `*_in_<container>` authorization predicate → violates B2.
- Any new uniqueness key or constraint spelled `series_…` at the tenant level
  → violates B4.
- Any *write-side* code resolving a container through a projection → violates
  the CQRS boundary in `AGENTS.md` §1, independently of this ADR (S3 is an
  API-edge/infra seam by design).

## Alternatives Considered

1. **Generalize `Season` into a generic container/scope aggregate.** Rejected
   in D2: union children, a numbering invariant that is not universal, and a
   TV-shaped aggregate at the tenancy boundary.
2. **Keep `Season` and add a parallel Film/Theatre branch** (poly-morphic
   hierarchy, one set of aggregates per production form). Rejected: N
   authorization predicates, N projection families, and no single tenant story —
   it multiplies the very defect this ADR removes.
3. **Put `Project` above `Series` as a new level** (`Project → Series →
   Season → …`). Rejected in D1: moves the tenancy seam, invents a level no
   user names, and makes every projection column and event payload wrong to fix
   a naming problem.
4. **Pure rename ADR — fix the word, decide the boundary later.** Rejected: the
   rename alone leaves `has_active_costume_role_in_season` untouched, so 0.4.x
   would keep re-baking `SeasonId` into the security layer and the ADR would
   have prevented nothing.
5. **Defer entirely until a second production form is on the roadmap.**
   Partly true — which is why D3 is non-normative and D5's rename (S1) is
   deferred. Rejected as the ADR's *content*, because the erosion is happening
   now: the 0.4.x issues are actively adding season-typed authorization
   (#535) and season-scoped lifecycle state (#533). The rationale has to be on
   the record before those land.

## Notes

- **Strategic parent of 0.4.x.** #532 (photo upload for repertoire-bound
  costumes), #533 (season lifecycle — `ArchiveSeason`), #534 (repertoire as
  real aggregate state) and #535 (series-level costume-photo authorization)
  link back here. None of them is blocked by this ADR: it constrains their
  *shape* (B2, S2, S3), it does not add work.
- **Doc drift corrected alongside this ADR.** The claim "`Costume` … is
  scope-free (bound only to a `Character`)" in
  `.github/instructions/domain-model.instructions.md` has been false since
  #453/#543 introduced the season repertoire; the same file and
  `frontend-flutter/AGENTS.md` §2 now carry a pointer to this ADR. The
  `docs/architecture/adrs/README.md` table also gained the missing ADR-033 row.
- **Not touched, deliberately.** `docs/security/security-architecture.md` §1
  ("the tenancy seam is the opaque `SeriesId`") is *accurate for today's
  code* and is corrected by S1's rename change, not by this ADR (B5).
  **Corrected by issue #591** — §1 now names `ProjectId` as the tenancy seam
  (same boundary, same values; ADR-035 B1).
- **No code.** This ADR is rationale + boundary + seams. The first code change
  it prescribes is #535's `has_active_costume_role_in_project`; the rename
  (S1) is a separate, later change (issue #591).