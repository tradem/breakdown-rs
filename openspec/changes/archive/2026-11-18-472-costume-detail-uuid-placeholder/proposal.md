<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Proposal: Costume AddDetail sends a client-side UUIDv7 wire id (issue #472)

## Problem

Creating a costume succeeds (201), but adding a detail always fails with
`422 domain.validation`. `CostumesController.addDetail`
(`lib/features/costumes/costumes_controller.dart`) builds the wire
`AddCostumeDetailRequest` with `..detail.id = 'pending'` — the placeholder
belongs to the client overlay model (`pending-detail-<version>` overlay card
keys), but it is constructed directly into the generated request payload.
The contract types `CostumeDetail.id` as `uuid` (required); serde rejects the
body before the handler runs. User-visible symptom: costume details can never
be added in the app.

## What Changes

- **`lib/core/uuid.dart`** (new): `generateUuidV7()` — the single place the
  third-party `uuid` package is referenced. `Uuid().v7()` produces a
  wire-valid, time-ordered UUIDv7 matching the backend's `uuid`-crate v7 ids.
- **`lib/features/costumes/costumes_controller.dart`** (`addDetail`): the wire
  `detail.id` is now `generateUuidV7()` instead of the literal `'pending'`.
  The optimistic overlay keeps its **own** separate transient placeholder id
  (`pending-detail-<version>`) and is reconciled from the projection response
  — the two ids stay decoupled.
- **`frontend-flutter/pubspec.yaml`**: add `uuid: ^4.6.0` (direct dependency;
  `Uuid().v7()` requires the v7 generator added in uuid 4.4.0).
- **Sibling audit**: the only placeholder-into-wire-payload write in the file
  was `addDetail`; the overlay `pending-detail-<version>` placeholder is used
  solely for `CostumeDetailView` overlay cards, never built into a request.
  No other sibling write was affected.
- **Tests**:
  - `test/unit/uuid_test.dart` (new, Tier 1): `generateUuidV7()` emits 100
    unique RFC-9562 UUIDv7 strings (version nibble 7, variant nibble 8-a-b),
    never the rejected `'pending'` placeholder, and is time-ordered.
  - `test/features/costumes/costumes_screen_test.dart` (Tier 2): the fake
    repository now captures `lastAddDetailRequest`; new regression asserting
    the wire `detail.id` is a parseable UUIDv7 (not `'pending'`) while the
    overlay still rides the separate `pending-detail-2` placeholder; new
    #467-adjacent regression asserting a 422 `domain.validation` surfaces the
    wire `code` via `costumeErrorCopy` (keyed copy, never a generic network
    narrative).

## Non-goals

- No change to the overlay placeholder (`pending-detail-<version>`) or the
  reconciliation flow — the overlay is reconciled from the projection as
  before.
- No backend change; the contract already types `CostumeDetail.id` as
  `uuid` and accepts a valid client-supplied UUID (verified: `detail.id=<UUIDv7>`
  → 200).
- No Gherkin scenario: the requirement calls for "Widget/Gherkin" coverage;
  a Tier-2 widget test asserting the wire payload satisfies this without a
  heavyweight on-device addition (the critical costume flow already has
  on-device Gherkin coverage; this is a wire-level payload regression).
- No change to generated files (`vendor/breakdown_api/`, `*.g.dart`).

## Affected Packages / Artifacts

| Package / Artifact | Action | Reason |
|---|---|---|
| `frontend-flutter` (`pubspec.yaml`) | add `uuid: ^4.6.0`; version `0.3.0-alpha.13+22` → `0.3.0-alpha.14+23` (lockfile updated) | Client-side UUIDv7 for the `uuid`-typed wire id; per-PR version bump convention (ADR-033, see #362) |
| `breakdown_api` (`vendor/breakdown_api/`) | unchanged | no `backend/openapi.yaml` change |
| `*.g.dart` / `*.freezed.dart` | unchanged | no annotation / schema change |
