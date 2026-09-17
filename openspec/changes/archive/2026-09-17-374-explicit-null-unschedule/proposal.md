<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# Proposal: emit explicit null for shooting-day unschedule / rename-to-null (issue #374)

## Why

Backend #372 (PR #373) made `PATCH /v1/shooting-days/{id}` presence-tracked:
an absent `date`/`label` field means "no update"; an explicit JSON `null`
means unschedule / rename-to-null. The regenerated
`vendor/breakdown_api` model is nullable-optional, but its built_value
serializer omits null fields — built_value has no present-but-null
representation. So the shipped client still cannot *send* the explicit
`null`: `buildUnscheduleRequest` serialized `date` as absent and the
backend (correctly) rejected the command with 422, leaving the unschedule
affordance shipped by PR #371 unwired.

## What Changes

- `ShootingDayRepository` gains raw-Dio single-intent methods
  (Option A, user-approved): `unschedule(id, version:)` sends
  `{"version": N, "date": null}` and `renameToNull(id, version:)` sends
  `{"version": N, "label": null}`, sharing one private `_patchExplicitNull`
  helper that PATCHes `/v1/shooting-days/{id}` bypassing the typed request
  serializer (precedent: `PhotoRepository.upload`) and never throws
  (RFC 9457 `ProblemError` mapping, `shooting_day.dto_invalid` for a
  missing/non-int body).
- `ShootingDaysController._singleIntent` is generalized to a closure-based
  `_intent(day, send)` so every day mutation shares the AUTHZ-GATE session
  resolution, error routing, and bounded-retry reconciliation; `unschedule`
  and `rename(label: null)` route to the new repository methods.
- `buildUnscheduleRequest` is deleted (it can never emit the required wire
  body); `buildRenameRequest` now requires a non-null `label` — the null
  case is the repository's explicit path.
- `vendor/breakdown_api/` is NOT touched (rebuild-only; no hand edits; the
  limitation is built_value's, not the generated model's defect).

## Impact

- **Code:** `lib/data/shooting_day_repository.dart`,
  `lib/features/shooting_days/shooting_days_controller.dart`.
- **Tests:** new tier-1 `test/unit/shooting_day_explicit_null_test.dart`
  (wire-format + Ok/Err branches); tier-2 flows-test fake extended with
  unschedule / rename-to-null routing coverage.
- **Specs:** no delta — the shooting-days screen spec (PR #371) already
  prescribed the affordance; this change wires the transport it assumed.
