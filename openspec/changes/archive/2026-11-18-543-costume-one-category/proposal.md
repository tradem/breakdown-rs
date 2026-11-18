<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# 543 — One costume = one category: `category_id` moves from the detail to the costume

## Why

The category lives on the **detail** today, not on the costume — and since #510 the
UI effectively operates on a different model than the backend:

- `CostumeDetailView { id, subject, category_id, category_name, text }` — the
  category sits on the detail.
- `CostumeView` has no category field.
- The Flutter `costumeTileIdentity()` derives the grid tile's category from
  `costume.details.first` — exactly one read site in the whole client.

Result: a costume with three details in three categories shows category 1 and
text 1 in the grid. The category de facto *belongs* to the costume; it is
modelled one level too deep. The default seed categories are garment-level.

## Decision

**A costume belongs to exactly one category (n:1).** The category moves from the
detail to the costume; details keep `subject` + `text` and become pure
description. The costume stays scope-free: `category_id` is a cross-aggregate
reference exactly like `character_id` — no scope column, resolved by join in the
read model (`costume-character-binding` spec: "only character_id" →
"character_id **and** category_id").

## Cross-aggregate invariant (doctrine, AGENTS.md §1)

`category.season_id ∈ (repertoire_seasons(costume) ∪ season(character))`

| Point | Decision |
|---|---|
| Authoritative enforcement | none — not a uniqueness case; the projector resolves `category_name` best-effort (`None` on a miss, audit metadata never blocks) |
| Client-facing 409 | API-edge pre-check in `set_costume_category` **before dispatch**: category exists (404 `costume-category.not-found`), not archived (409 `costume-category.archived`), season in the permitted set (409 **new** `costume-category.season-mismatch`, extension `category_id`) |
| Projector failure behaviour | unchanged — no constraint, no write-failure path; no #37 dead-letter needed |

## Replay trap → derivation in `Apply` + the identical rule in the projector

No SQL backfill: after a replay the aggregate would not have the category while
the projection does → divergence. **Rule (first-wins, deterministic):** while
replaying `CostumeCreated` / `DetailAdded` with `detail.category_id != None` and
a still-empty costume category, the first detail category in event order (within
one event: `detail_id` ASC) is adopted. Executed by both `CostumeAggregate::apply`
and the costume projector; a mandatory parity test pushes a legacy stream
(only `CostumeCreated` with a categorized detail, no `CostumeCategorySet`)
through both and fails on divergence.

## Decisions taken (user-approved in this session)

- **Scope:** backend only in this PR (core/infra/api + migration + specs +
  openapi + vendored client regen). The Flutter tile/picker work follows in a
  separate PR; the wire break is accepted for the window between the PRs.
- **Idempotency:** `SetCostumeCategory` with `cmd.category_id == self.category_id`
  is a **state-based no-op** (`Ok(vec![])`, #515 precedent) — not a version
  conflict, not a validation error.

## Backend changes

**core** (`crates/core/src/costume/`)

- `commands.rs`: `SetCostumeCategory { id, category_id: Option<CostumeCategoryId>, version, series_id }` (`None` clears).
- `events.rs`: `CostumeCategorySet { id, category_id: Option<CostumeCategoryId>, version }`; `CostumeDetail` keeps `category_id` as a `#[serde(default)]` legacy field.
- `aggregate.rs`: `category_id: Option<CostumeCategoryId>` as real state + the replay-derivation rule; `SetCostumeCategory` with version fence and state-based no-op.
- `views.rs`: `CostumeView { + category_id, + category_name }`; `CostumeDetailView { − category_id, − category_name }`.
- `ports.rs`: `CostumeCommands::set_category`.
- `error.rs` (root): new `DomainError::CategorySeasonMismatch { category_id }` (S0) for the 409 extension.

**infra**

- Migration: `projection_costume` gains `category_id UUID NULL`, `category_name TEXT NULL`; `projection_costume_detail.category_id/category_name` stay (legacy replay), cleanup in a later migration.
- `projectors/costume.rs`: `CostumeCategorySet` branch; the derivation rule in `CostumeCreated`/`DetailAdded` (SQL-conditional first-wins).
- `projectors/costume_category.rs`: rename propagation retargets to `projection_costume.category_name`.
- `queries/costume.rs`: `CostumeView.category_id/category_name` from `projection_costume`; details no longer carry the category columns in the view.
- `event_store/command_adapters.rs`: `set_category`.

**api**

- `set_costume_category` route `POST /v1/costumes/{id}/category`, handler-internal `// AUTHZ-GATE:` (costume-role in ANY season scope, reusing the #532 helper), pre-check per invariant.
- `problem_codes!`: new `costume-category.season-mismatch` (409, extension `category_id`), registry count bump, Fluent de/en.
- `AddCostumeDetailRequest` without `categoryId` (new wire struct `CostumeDetailRequest`).

**specs / docs**

- `openspec/specs/costume-category/spec.md`, `openspec/specs/costume-character-binding/spec.md`, `backend/.github/instructions/domain-model.instructions.md`.

## Out of scope (recorded, not ticketed here)

- Flutter client work (separate PR): tile from `costume.categoryName`, category picker with icons, controller setCategory, goldens.
- Follow-up recorded in the issue: `icon_key` on `CostumeCategory` (server-owned icon mapping).
- Follow-up recorded in the issue: lift costume `subject`/`name` onto the aggregate (last `details.first` smell).
- `projection_costume_detail.category_id/category_name` column cleanup: later migration.
- The AI-import apply chain stays deliberately category-less (imported costumes are uncategorised until the picker lands) — recorded in the specs as intended policy.
