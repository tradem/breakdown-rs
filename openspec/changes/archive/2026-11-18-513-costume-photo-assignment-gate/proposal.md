<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# 513 — Costume photo commands: client-side assignment gate + honest error copy

## Why

`POST /v1/costumes/{id}/photos` (and the photo `delete`/bytes handlers)
resolve the photo season for the AUTHZ-GATE through
`costume.character_id → character.season_id`
(`crates/api/src/handlers/mod.rs`). A costume without a character binding
(`character_id: null`) 422s `domain.validation` — "costume has no assigned
character — cannot determine season". The Flutter app surfaced that failure
through the generic `costumeErrorCopy` fallback:
**"The costume could not be saved (domain.validation)"** — misleading for a
photo operation, and it masked the real cause (issue #513).

The remaining backend causes behind the same message (#514 read-back race,
#515 saga version conflict) have already been fixed backend-side (#522, #523);
the character-derived season seam is still intentional, so the fix is the
client-side dimension.

## Decision (b) — keep the backend requirement, make the client enforce/explain

The backend seam question offers (a) derive the season from the costume itself
(needs the costume-projector to expose `season_id`) or (b) keep the
requirement and have the client enforce/explain it. **Decision: (b).**
Option (a) is a backend change (projection + handler + OpenAPI contract) and
is out of scope for this Flutter change; the generated `CostumeView` does not
carry `season_id`, so (a) would require regenerating the Dart client. It
remains a candidate backend change.

Client behaviour (AUTHZ-GATE mirror, Decision D6 / `frontend-flutter/AGENTS.md`
§5):

1. **Assignment gate before any network call.** `uploadPhoto` and
   `deletePhoto` refuse with a client-side denial
   (`code: photo.requires_character`, 403) when the costume's **confirmed**
   binding is unassigned (fence-held overlay first, then the reconciled
   projection). Zero requests leave the device (provable by a fake
   repository call count). The check runs **before** the season-membership
   fetch (pure local state — no unnecessary membership request). A binding
   that is *unknown* locally (e.g. a costume assigned by another client
   before this one cached it) is **not** pre-denied — the authoritative
   server decides.
2. **Gated affordances.** On the costume detail screen, photo capture,
   capture-again, and delete affordances are hidden when the costume is
   unassigned; the section explains the precondition instead of offering a
   doomed action.
3. **Honest error copy by command origin.** The command-error provider now
   carries the originating surface (`CostumeCommandSurface.costume |
   .photo`) alongside the `ProblemError`. A shared `costumeCommandErrorCopy`
   (used by both the list and detail screens) routes **photo-command**
   failures through `photoErrorCopy`, outfit commands through
   `costumeErrorCopy`. Routing is by origin, never by the `photo.*`
   prefix: a photo command that fails with the generic `domain.validation`
   (a concurrent unassign racing the local gate) still renders the photo
   copy, not the "costume could not be saved" fallback.

## Changes

- **`lib/features/costumes/costumes_controller.dart`**
  - `_resolveCharacterBinding` returns a tri-state
    (`CostumeBinding.assigned | unassigned | unknown`);
    `_denyUnassignedPhotoCommand` only pre-denies a **confirmed**
    unassigned binding and runs before the membership fetch. Gate
    `uploadPhoto` and `deletePhoto` on assignment before the network call.
  - `CostumesCommandError` carries `CostumeCommandFailure(surface, error)`;
    `costumeCommandErrorCopy` routes by command **origin** (photo vs.
    costume write), never by the `photo.*` code prefix.
- **`lib/features/photos/widgets/photo_gallery.dart`** — `photoErrorCopy`
  branch for `photo.requires_character` ("Assign the costume to a character
  before managing photos.").
- **`lib/features/costumes/costume_detail_screen.dart`** — `_PhotosSection`
  gating (narrative `photo-assignment-gate-narrative`, affordances hidden on
  an unassigned costume); inline error rendered via `costumeCommandErrorCopy`.
- **`lib/features/costumes/costumes_screen.dart`** — banner rendered via
  `costumeCommandErrorCopy`.
- **Tests** (`test/features/costumes/costume_detail_screen_test.dart`)
  - New: err-branch assertion for the rejected upload (direct `uploadPhoto`
    on an unassigned costume → `Left(photo.requires_character)`, zero network
    calls, actionable narrative rendered — scoped to the `costume-detail-error`
    banner); delete refusal on an unassigned costume holding photos (zero
    delete calls, no delete affordance); origin-routing unit tests (a generic
    `domain.validation` from a **photo** command renders the photo copy); an
    **unknown** binding (row absent locally) is NOT pre-denied — the request
    proceeds and the server decides.
  - Updated: capture-flow fixtures and the delete-confirm fixture now use an
    **assigned** costume (the gate would otherwise hide the affordances).

## Acceptance criteria (from issue)

- [x] Frontend UX: code-keyed, actionable narrative ("Assign the costume to a
      character before managing photos.") and/or client-side gating of the
      upload affordance (AUTHZ-GATE mirror) — both implemented.
- [x] Backend seam question: decided (b) — keep the requirement; client
      enforces/explains. Option (a) noted as a deferred candidate backend
      change (needs `season_id` on the costume projection/contract).
- [x] Tests: err-branch assertion for the rejected upload renders the new
      narrative; gate provably issues zero network calls.
- [ ] (out of scope) Wire test for upload on an unassigned costume returning
      2xx — only relevant if (a) is later implemented.
