<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Proposal: Core Costume Domains — Phase 2

## Why
Phase 1 delivered the hierarchy spine (seasons → blocks → episodes →
scenes) and costume categories. Phase 2 is the roadmap's core user
value: the costume department's day-to-day work — costumes (with
assignment to characters), characters (contact + measurements), photo
capture/upload on costumes, and shooting-day planning/scheduling. The
repo routes exist (`/v1/costumes*`, `/v1/characters*`,
`/v1/episodes/{id}/shooting-days`, `/v1/scenes/{id}/shooting-days`)
and scaffold repositories exist (`lib/data/costume_repository.dart`,
`character_repository.dart`, `photo_repository.dart`,
`shooting_day_repository.dart`) — but there are no caches, no
controllers, no screens.

**Blocker discovered during grounding (documented, not worked around):**
the backend router serves scene-shoot execution and continuity-photo
routes (`/v1/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots…`,
`…/continuity-photos…`, `/v1/shooting-days/{id}/wrap`, JSON reports),
but the checked-in `backend/openapi.yaml` — the single source of truth
for the generated Dart client — does NOT contain them. Per the
never-retrotype-DTOs hard rule, the Soll/Ist scene-shoot UI and the
continuity-photo capture UI are **excluded from this change** and await
a backend OpenAPI re-export + their own change
(`flutter-scene-shoots-screen`). The continuity-photo and Soll-Ist
Gherkin critical scenarios move with them; this change carries the
costume-assignment critical scope (see Non-goals).

## What changes
- **Costumes feature** (`features/costumes/`): season-scoped list,
  create (the create request body is empty by contract — a costume is
  an empty aggregate shell filled by follow-up commands), detail screen
  (detail elements with denormalized category names, notes editor,
  character assignment), `assign`/`unassign` commands
  (version-echo optimistic locking), add-detail form categorized via the
  existing costume categories — AUTHZ-GATE via session + membership
  capabilities on gates the backend derives from
  `has_active_costume_role_in_season`.
- **Characters feature** (`features/characters/`): season-scoped list
  (category chip: main_cast/guest/extra), create,
  detail screen with contact + measurements editors (PATCH, version
  echo).
- **Scene-character binding**: the scenes screen (from Phase 1) gains a
  "characters" section — assigned characters resolved from
  `SceneView.assigned_characters` ids via the characters projection
  (read-DTO join, no aggregate reconstruction), assign/unassign
  (`POost /v1/scenes/{id}/characters`, DELETE
  `/v1/scenes/{id}/characters/{character_id}`) with the scene version
  echo from the acted-on `SceneView`.
- **Photos feature** (`features/photos/`): camera capture via
  `image_picker` — in-app rationale BEFORE the system permission
  prompt, point-of-use only; background-isolate downscaling; raw-bytes
  upload (`POST /v1/costumes/{costume_id}/photos`,
  content-type `image/jpeg|png|webp` — the route takes raw bytes, NOT
  multipart); gallery from the photo references embedded in
  `CostumeView.photos` (there is no photo-list route — the view rides
  with the costume); variant watch (`Pending → Ready | Failed`) via a
  bounded, foreground-only refetch stream; bytes fetch and delete,
  all AUTHZ-GATE'd via membership capabilities before the network call.
- **Shooting days feature** (`features/shooting_days/`): episode-scoped
  list ordered by `order_key`, create (label/date/`Manual` source),
  update (reorder / reschedule / rename / unschedule-date via the
  one-of `UpdateShootingDayRequest`), archive; scene scheduling from
  the scene detail (`POST /v1/scenes/{id}/shooting-days` with the scene
  `version`, unschedule DELETE) — the Soll/Ist execution UI itself is
  the blocked follow-up.
- Drift caches: `costumes`, `characters`, `shooting_days` tables (+
  migration); photo references ride the costume rows. Photo bytes are
  memory-cached only, never persisted to Drift.
- Gherkin (designated critical scope — costume assignment): a
  `flutter_gherkin` feature covering command → optimistic update →
  projection refresh and the client-side role-denial path.

## Capabilities
- `flutter-costumes-screen` (new)
- `flutter-characters-screen` (new)
- `flutter-photos-feature` (new)
- `flutter-shooting-days-screen` (new)

## Dependencies
- **Depends on:** `flutter-login-and-app-shell` (gate, tokens, theme),
  `flutter-hierarchy-navigation` (season context, navigation spine,
  shared reconciliation module, membership provider with strict
  capability parsing).
- **New packages:** `image_picker` (camera/gallery pick at point of use,
  FOSS), `image` (pure-Dart decode/encode for background resizing,
  FOSS). No camera-surface rendering package — capture delegates to the
  system camera. No new state-management or routing packages.

## Non-goals
- No Soll/Ist scene-shoot execution UI, no continuity-photo capture, no
  wrap, no reports (blocked on the OpenAPI export gap; own change after
  the backend re-exports `openapi.yaml`).
- No photo editing/annotation, no offline photo queue (online-first
  commands per `flutter-offline-scope`).
- No costume rename — no such command exists in the API.
- No shooting-day PDF downloads (Phase 4).

## Design Decisions
- **D1 — Costume create is deliberately empty-bodied.**
  `CreateCostumeRequest` has no fields; `POST /v1/costumes` returns an
  `IdVersionResponse` shell whose contents (details, notes,
  assignment) are added by follow-up commands. The client models the
  create sheet as "create + immediately add first detail" to avoid a
  confusing empty dead-end row.
- **D2 — Unassign wire quirk conformed to, flagged.** The
  checked-in spec declares the `unassign` body as
  `UpdateCostumeNotesRequest` (`notes` required) while the handler
  consumes `VersionRequest` only. Backend owns the contract: the client
  sends `notes` echoed unchanged from the acted-on `CostumeView` plus
  `version`. Tracked as a backend spec defect — no client-side
  reinterpretation.
- **D3 — Client AUTHZ-GATE for photo handlers mirrors the server's
  season-scoped photo policy.** Upload/bytes/delete are handler-gated
  on `has_active_costume_role_in_season` server-side; the client gates
  on the same predicate via the membership read (v1 capability set:
  `assign_costumes` / `upload_continuity_photos`, both derived from
  that predicate) with a `// AUTHZ-GATE:` comment and a localized 403
  narrative issued before any network call.
- **D4 — Photo upload is raw bytes, not multipart.** The route consumes
  `image/jpeg|png|webp` raw bodies with size/`415`/`413` server
  validation. The client downscales on a background isolate (longest
  side cap, re-encode to the picked content type) so large captures
  satisfy the size budget without jank; server-side EXIF stripping is
  trusted (never re-implemented client-side).
- **D5 — Foreground-only variant watching.** The
  `photoRepository.watch(costumeId)` stream refetches the costume view
  with bounded backoff until `CostumePhotoView.variants[].status` is
  terminal (`Ready`/`Failed`), and stops when the last subscriber
  leaves — no background polling, no wake-ups (store compliance).
- **D6 — Empty state honesty for blocked features.** The scene detail's
  "shooting days" section shows scheduled days and the schedule/
  unschedule actions that the available routes support; any Soll/Ist
  affordance is absent rather than stubbed.
