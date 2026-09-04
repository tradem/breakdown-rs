<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Design: Core Costume Domains

## 1. Backend contract facts (grounding)

From the checked-in `backend/openapi.yaml` and
`backend/crates/api/src/handlers/mod.rs` (server-owned; backend wins):

- `GET /v1/costumes?season_id=…` → `List<CostumeView>`:
  `character_id` (nullable — assignment), `notes`, `details[]`
  (`id, subject, text, category_id?, category_name`), `photos[]`
  (`id, content_type, size_bytes, variants[{kind,status,size_bytes}]`),
  `version`, `updated_at`. `POST /v1/costumes` — empty request body →
  `IdVersionResponse` (D1).
- `POST /v1/costumes/{id}/assign` (`AssignCostumeRequest:
  {character_id, version}`) → `AggregateVersion`; 409 on conflict.
  `series_id` is derived server-side from the character (correct side
  of the CQRS boundary).
- `POST /v1/costumes/{id}/unassign` (`VersionRequest: {version}`)
  → `AggregateVersion`. (Spec/handler drift fixed by backend issue
  #336 — the spec previously declared `UpdateCostumeNotesRequest`,
  see D2.)
- `POST /v1/costumes/{id}/details` (`AddCostumeDetailRequest:
  {detail: {subject?, text, category_id?}, version}`);
  `PATCH /v1/costumes/{id}/notes` (`UpdateCostumeNotesRequest
  {notes, version}`).
- `GET /v1/characters?season_id=…` → `CharacterView`:
  `name, season_id, category (main_cast|guest|extra),
  measurements{height,weight,chest,waist,hips,shoe_size,hat_size — all
  required strings}, contact{email?,phone?}, version, updated_at`.
  `POST /v1/characters` (`CreateCharacterRequest {season_id, name,
  category}`); `PATCH …/contact`, `PATCH …/measurements`
  (version echo). No rename route.
- `POST /v1/scenes/{id}/characters` (`AssignCharacterRequest
  {character_id, version}` — the scene's version); `DELETE
  /v1/scenes/{id}/characters/{character_id}?version=…` (optimistic-lock
  version as a query parameter, backend issue #341). `SceneView.
  assigned_characters` carries the ids (read-model join resolves the
  display names from the characters projection).
- Shooting days: `GET/POST /v1/episodes/{episode_id}/shooting-days`
  (`CreateShootingDayRequest {episode_id, order_key, source
  (Manual|AiExtracted), label?, date?}`,
  `ShootingDayView: {id, episode_id, date?, label?, order_key, source,
  archived, wrapped_at?, version}`); `GET/PATCH /v1/shooting-days/{id}`
  (`UpdateShootingDayRequest` — exactly one of order_key / date /
  label; `date: null` means unschedule); `POST
  /v1/shooting-days/{id}/archive` (version).
- Scene scheduling: `POST /v1/scenes/{id}/shooting-days`
  (`ScheduleSceneRequest {shooting_day_id, version — scene's}`);
  `DELETE /v1/scenes/{id}/shooting-days/{shooting_day_id}?version=…`
  (version query parameter, backend issue #341).
- Photos: `POST /v1/costumes/{costume_id}/photos` (RAW body,
  `image/jpeg|png|webp`, ≤ `PHOTO_MAX_SIZE_MB` (default 20 MB), 413/415
  server errors) → 201 `PhotoView`; `GET
  /v1/costumes/{costume_id}/photos/{photo_id}/bytes?variant=…` → binary;
  `DELETE /v1/costumes/{costume_id}/photos/{photo_id}`. Photo handlers
  are season-scoped membership-gated handler-internally (AUTHZ-GATE
  columns in `backend/crates/api/src/auth/authorization.rs`).
  `VariantStatus: Pending → Ready | Failed`.

**Follow-up surface (own change, now unblocked):** scene-shoot plan/start/
actual-order/skip/finish/notes, continuity photos, wrap, JSON reports
(`flutter-shoot-day-execution` / `flutter-reports`; backend issue #333
landed, PR #344). Error responses are per-operation RFC 9457
`application/problem+json` with stable codes (backend issue #343).
(`dispo`, `shoot-day`, `soll-ist`). The backend router serves them; the
checked-in spec does not. The generated client therefore cannot
express them — excluded entirely (see proposal Blocker and design §7).

## 2. Feature architecture

All four features follow the seasons reference pattern (Phase 1
generalized it): ConsumerWidget container + `@riverpod` family
controller (season / / costume context) + `widgets/` pure trees +
Result repository + Drift cache-backed reads + shared reconciliation
(`lib/domain/reconciliation/`) for create/assign/schedule commands.
Exisiting scaffold repos (`costume_repository.dart`,
`character_repository.dart`, `photo_repository.dart`,
`shooting_day_repository.dart`) become cache-backed and gain the
command methods; their current call shapes are preserved where correct.

- Drift migration adds `costumes`, `characters`, `shooting_days`
  tables; the costume row stores `photos`/`details` serialized as
  read-DTO snapshots (projection-shaped, not event-shaped). Photo
  and detail sub-lists never cache independently — they ride the
  costume row and refresh with it (no route to list them separately).
- Costume `assign` (200 `AggregateVersion` ack): optimistic state edit
  — the overlay discipline applies to the *costume row* (set
  `character_id` to the picked id with `reconciling` status). The
  overlay is cleared by a **version fence**, not by any refetch: it is
  dropped only when the refetched row's `version >= acknowledged
  version` (`AggregateVersion` returned by the ack). A stale
  projection (older `version`) MUST NOT restore the pre-command
  `character_id`, notes, or details — the overlay stays visible and
  the next bounded refetch repeats. `unassign` mirrors it.
  `add_detail` / `update_notes`: same row-level optimistic edit and
  the same version fence, keyed on the returned new aggregate version.
- Character PATCH commands (`contact`, `measurements`): full-form
  editors writing whole `ContactInfo`/`CharacterMeasurements` objects
  (both are replacements server-side — "God-Command" semantics); the
  form is pre-filled from the read DTO and `version` echoes it; 409 →
  "changed elsewhere" copy keyed on `code` (no auto-bump retry).
- Scene-character assignment: the picker lists the season's
  `CharacterView`s; `AssignCharacterRequest.version` is the *scene's*
  version from the acted-on `SceneView`; the assigned list renders
  through characters-projection lookups by id.
- Shooting-day create derives `order_key` with the same append rule
  implemented in Phase 1 (shared pure function, `source: Manual`).
  `UpdateShootingDayRequest` is a one-of command: the UI issues
  reorder (drag or move up/down), reschedule/unschedule (date picker,
  `date: null` for unschedule), rename — one PATCH per action, never
  a combined payload.

## 3. Photos pipeline (D4/D5)

1. **Capture:** `image_picker` (camera or gallery, Android + macOS).
   An in-app rationale dialog is shown BEFORE the first system
   permission request ("Photos let the wardrobe team document
   costumes…"), remembered by a local flag. The system prompt fires
   only at the point of capture (store compliance).
2. **Prepare:** on a background `compute` isolate via the `image`
   package: decode, downscale the longest side to the configured cap,
   re-encode to the picked content type. Downscaling is **not** a size
   guarantee (a PNG re-encode can still exceed the budget), so the
   prepared bytes are measured and, if oversized, iteratively
   re-encoded at a reduced cap/quality until they fit
   `PHOTO_MAX_SIZE_MB` or fall below a floor — after which the client
   fails locally with a `photo_too_large` result (no upload attempt,
   localized copy) instead of provoking a 413. 413 from the server
   therefore stays a defensive branch only. The UI thread stays free;
   progress shows a `LinearProgressIndicator` (prepare + upload).
3. **Upload:** `POST` raw bytes with the correct `Content-Type`
   header (image/jpeg|png|webp) — NOT multipart; 201 `PhotoView` ack
   → optimistic gallery entry → bounded reconciliation via costume
   refetch. 415/413/403 keyed on `code` with localized copy; 403 is
   pre-empted client-side by the membership capability gate (D3).
4. **Watch:** `photoRepository.watch(costumeId)` — bounded-backoff
   costume refetches while at least one subscriber exists; terminal
   variant states (`Ready`/`Failed`) end the watch for that photo; a
   `Failed` variant row shows a retry affordance (re-pick a new
   capture — there is no re-upload-variant command).
5. **Bytes:** in-memory LRU keyed by `(photoId, variant)` via a
   repository-backed `ImageProvider`; never persisted to Drift (the
   cache is a read-model store, not a blob store; documented
   consequence: views re-fetch after process death — acceptable for
   20 MB-capped variants, thumbnails first).
6. **Delete:** confirmation dialog (no destructive dark pattern);
   204 → optimistic removal + reconcile.

Camera-permission behavioral matrix (spec scenarios): denied at
prompt → rationale re-shown with "open settings" affordance; granted
then revoked between sessions → capture fails with
`camera.unavailable` copy; permission state is never cached or read
from system APIs outside the capture intent.

## 4. Cross-feature navigation

Entered from the Phase 1 spine, all `Navigator.push`, no new routing:

- Season context (blocks screen toolbar/team area): "Costumes", and
  "Characters" entries (season-scoped lists). Costume detail pushes
  from the row tap; character detail likewise.
- Scene detail (Phase 1 ScenesScreen gains a collapsible sections
  layout): "Characters" (assigned list + assign/remove), "Shooting
  days" (assigned days + schedule/unschedule picker from the parent
  episode's days — EpisodeView context from the navigation stack).
- Episode context gains "Shooting days" entry (list/create/update/
  archive).

## 5. Adaptive UX / accessibility / themes

- Lists: same adaptive treatment as Phase 1 (Android compact cards +
  FAB, macOS focus/hover/Escape, 48 dp targets, goldens in
  {light,dark} × {android,macos}).
- Forms (assign picker, detail add, contact, measurements): full
  keyboard traversal with obvious focus, `textScaler 1.3` no-overflow
  widget tests, destructive actions confirm-first.
- Photo gallery: grid of thumbnails (2/3/4 columns by width class via
  token breakpoints), semantic labels carrying "photo of costume X";
  large-image decode on background isolates so the grid never janks.

## 6. Gherkin — costume assignment (designated critical scope)

`features-spec/costume_assignment.feature` driven by `flutter_gherkin`
on device: create costume → assign to character → optimistic row shows
assignment → projection refresh confirms → role-denial scenario (a
membership without capabilities sees the client-side 403 narrative and
an intercepted request counter proves no network call). Continuity
capture + Soll-Ist features move to the blocked follow-up change
(`flutter-shoot-day-execution`), keeping the Gherkin-tier scope honest.

## 7. Test plan (tiers)

- **Tier 1 unit:** every new repository method Ok/Err; Drift untouched
  on failure; snapshot-replace per list; assign/unassign/notes/detail
  optimistic-edit reducers; measurements/contact request builders
  (full-replacement semantics); order-key append reuse; photo prepare
  pipeline (downscale cap, content-type mapping — isolate-free pure
  core); watch state machine (bounded attempts, terminal stop,
  subscriber-count lifecycle) with fake scheduler/clock (no
  wall-clock); strict capability gate function (allow/deny per
  capability set).
- **Tier 2 widget + golden:** each screen — data/empty/error/stale/
  overlay; assign picker; denial narrative (gate blocks network call —
  fake repo call count 0); photo gallery variant states; schedule/
  unschedule pickers; goldens {light,dark} × {android,macos}.
- **Tier 3 Gherkin:** costume assignment feature (above).
- **Tier 4 integration:** emulator smoke (dev-auth): season →
  costume create+detail → assign to a character → photo capture
  (picker faked) → upload → thumbnail appears after variant Ready.
- Determinism: injected clocks/schedulers; image pipeline tested with
  tiny synthetic fixtures, no real camera hardware in CI.
