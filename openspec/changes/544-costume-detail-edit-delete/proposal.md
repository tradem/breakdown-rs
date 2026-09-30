<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Proposal: Costume details are editable and deletable (issue #544)

## Problem

A costume detail can be added but never changed or removed — on both sides.

**Backend:** `RemoveDetail` is completely implemented and unreachable
(`crates/core/src/costume/commands.rs:84`, `events.rs:64` `DetailRemoved`,
`aggregate.rs:259`, `ports.rs:46`, `command_adapters.rs:638`, core tests
`tests/costume_aggregate.rs:370`/`:406`). Only the HTTP edge is missing:
`POST /v1/costumes/{id}/details` is the sole detail route. For *changing* a
detail there is no command or event at all.

**Client:** `CostumeRepository` and `CostumesController` know only
`addDetail`; `_DetailsSection` renders a `Card`+`ListTile` per detail with no
action. A typo in the `Betreff` is permanent. (The row actions / inline editor
are issue #545; this change is the data layer it needs.)

## Drift check (2026-09-21, before implementation)

| Issue claim | Reality | Consequence |
|---|---|---|
| `RemoveDetail` implemented, unexposed | confirmed | adapter work only |
| no `DetailUpdated` anywhere | confirmed | new event + command |
| projector upsert handles updates | confirmed (`projectors/costume.rs:207`) | no migration |
| "requires #543 for the wire shape; `categoryId` disappears with #543" | **#543 has partially landed** | `CostumeDetailRequest` (`handlers/mod.rs:224`) is already pure description — `id`/`subject`/`text`, no `category_id`. `UpdateCostumeDetailRequest` is therefore `{detail: {id, subject, text}, version}` with **no** `categoryId`. If #543's remainder lands, it is a field removal, not a break. |
| open | #543 still OPEN | we do not block on it |

## Decisions

1. **Unknown `detail_id` → new `costume-detail.not-found` (404)**, not the
   existing `costume.validation` (422). The issue leaves this open and prefers
   the 404: a client cannot otherwise tell "detail is gone" apart from a real
   validation failure. Implemented as a new `CostumeError::DetailNotFound { id }`
   variant — one variant serves both `RemoveDetail` (today: a `ValidationError`
   string) and the new `UpdateCostumeDetail`, so `DELETE` and `PATCH` answer
   identically. Registry entry in `problem_codes!` (`error_registry.rs`),
   Fluent text in `locales/{de,en}/errors.ftl`, client copy key.
2. **No cross-aggregate invariant is introduced** — the detail is a child of
   the costume's own stream, so per-stream optimistic concurrency is the
   authority. The §1 cross-aggregate doctrine (API-edge 409 pre-check +
   constraint backstop + projector failure spec) does not apply, and the
   projector path is a plain upsert/DELETE that cannot deadlock.

## What Changes

### 1. Core (`crates/core/src/costume/`)
- `events.rs`: `CostumeEvent::DetailUpdated { id, detail, version }` carrying
  the **full** detail, not a patch. A patch-merge leaves field merging to the
  client and turns an empty `subject` into an ambiguity (intent vs. accident).
- `aggregate.rs`: `Apply` arm (`Update` in place, order preserved — the
  `details` vec keeps its position, the aggregate has no ordering key);
  `impl Command<UpdateCostumeDetail>` — version fence, then
  `DetailNotFound { id }` when the `detail_id` is absent, so an unknown detail
  errors **without** an event.
- `commands.rs` + `error.rs`: `UpdateCostumeDetail`, `CommandName`, and the
  `DetailNotFound` variant (`RemoveDetail` switches from the `ValidationError`
  string to it).
- `ports.rs`: `update_detail` on the command port.
- `error.rs` (`core/src/error.rs`): `DetailNotFound` → `DomainError::NotFound`
  with the new code; `error_registry.rs`: the `COSTUME_DETAIL_NOT_FOUND` entry.

### 2. Infra
- `command_adapters.rs`: `update_detail` (same fence/metadata shape as
  `add_detail`).
- `projectors/costume.rs`: a `DetailUpdated` arm onto the **existing** upsert
  plus `touch_parent` — no migration, no new query. `DetailRemoved`'s
  projection DELETE is currently untested; covered now.

### 3. API (`crates/api`)
- `PATCH /v1/costumes/{id}/details/{detail_id}` and
  `DELETE /v1/costumes/{id}/details/{detail_id}` (body `VersionRequest` =
  the costume aggregate's version echo). Both carry an `// AUTHZ-GATE:`
  comment and call `authorize_costume_scoped` **inside** the handler — the
  same seam as `set_costume_category` (#543), since the route hangs off
  `Authenticated`/`BlockMember` and cannot scope season membership.
- `UpdateCostumeDetailRequest { detail: CostumeDetailRequest, version }`.
- `series_id` for the audit trail is resolved at the API edge
  (`series_id_for_costume`) — the CQRS boundary holds; the adapter only
  forwards the field.
- Locales: `problem-costume-detail-not-found` in `de` + `en`.

### 4. Client (`frontend-flutter/`) — data layer only, no UI (#545)
- `CostumeRepository.removeDetail(id, detailId, request)` /
  `.updateDetail(id, detailId, request)`; `Result` returns, no `throw`.
- `CostumesController.removeDetail(...)` / `.updateDetail(...)`:
  `// AUTHZ-GATE:` capability check **before** the network call (403 with a
  localized narrative, nothing sent), version fence
  `_resolveVersion(costume.id, costume.version)`, 2xx ack advances the overlay
  version, bounded-retry reconciliation. `removeDetail` drops the row from the
  overlay immediately; the projection confirms it on refetch. `updateDetail`
  sends a real UUIDv7 — the `'pending'` trap of #472 must not return.
- `costumeCommandErrorCopy` gains the `costume-detail.not-found` key, keyed on
  the stable `code`, never on backend `detail`.

### 5. Contract
- `UPDATE_OPENAPI=1 cargo test -p api --test openapi_drift`
- `bash scripts/regen-client.sh` → committed `vendor/breakdown_api/`
  byte-identical.

## Acceptance criteria
- [ ] `DELETE` + `PATCH` routes with `// AUTHZ-GATE:`, 404/422/409 from the registry, `VersionRequest` echo
- [ ] `UpdateCostumeDetail` emits **one** `DetailUpdated`; unknown `detail_id` → 404 **without** an event
- [ ] `DetailUpdated` projected via the existing upsert, no migration
- [ ] `RemoveDetail` unknown `detail_id` → 404 `costume-detail.not-found` (was 422 string)
- [ ] Client `removeDetail`/`updateDetail` return `Result`; `Err` reaches the banner via `costumeCommandErrorCopy` keyed on `code`
- [ ] Missing `canAssignCostumes` → no network call, localized 403
- [ ] `openapi.yaml` regenerated, `vendor/breakdown_api/` byte-identical

## Relations
- Prerequisite for #545 (detail row actions / inline editor)
- #543 partially landed — see the drift table; the remainder is a field removal
- Closes the editing half of #13 ("Add costume details")
