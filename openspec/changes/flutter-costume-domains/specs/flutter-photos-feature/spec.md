<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# flutter-photos-feature Specification (delta)

## ADDED Requirements

### Requirement: Point-of-Use Camera Capture With Rationale
Photo capture SHALL use the system picker/camera flow
(`image_picker`) triggered only at the point of use. Before the FIRST
system permission prompt, the app SHALL show its own plain-language
rationale; a denial at the system prompt SHALL show a re-rationale with
an "open settings" affordance; a permission revoked between sessions
SHALL surface as "camera unavailable" copy. The app SHALL NOT read or
cache permission state outside the capture intent, and no background
service or wake-up SHALL hold the camera pipeline alive.

#### Scenario: Permission denied at first capture
- **WHEN** the user denies the camera permission at the first capture
  attempt.
- **THEN** the capture flow ends with the re-rationale ("…enable camera
  access in settings") plus the settings affordance; no crash, no
  retry loop.

#### Scenario: Permission revoked between sessions
- **WHEN** the user granted the permission earlier, revoked it in
  settings and starts a new capture.
- **THEN** the failure surfaces as camera-unavailable copy with the
  settings affordance; state never assumed from the previous session.

### Requirement: AUTHZ-GATE Before Photo Handler Calls
Every photo upload, bytes fetch and delete SHALL run a client-side
membership capability check (the season-scoped photo policy mirror:
an active costume role in the season, expressed through the strict
capability set) BEFORE the network call, annotated with a
`// AUTHZ-GATE:` comment. Client-side denial SHALL render a localized
403 narrative and never issue the request.

#### Scenario: User without the photo role
- **WHEN** a user without an active costume role taps capture/add on a
  costume.
- **THEN** the client short-circuits with the 403 narrative before any
  network call (provable in tests by a fake repository call count of
  zero).

### Requirement: Prepare-Then-Raw-Bytes Upload
The upload pipeline SHALL prepare the capture off the UI thread
(background isolate): decode, downscale to the configured longest-side
cap, re-encode to the picked content type — then upload via
`POST /v1/costumes/{costume_id}/photos` as RAW bytes with the matching
`Content-Type` header (NOT multipart). The UI SHALL show progress
(linear) for prepare+upload and never block the frame; size/`413` and
content-type/`415` server rejections render copy keyed on `code`.

#### Scenario: Large capture
- **WHEN** the user captures a large image (e.g. 48 MP).
- **THEN** downscaling occurs on the isolate (no dropped frames —
  asserted in tests), the upload satisfies the size budget, and on 201
  the gallery shows the optimistic entry with variant `Pending`.

#### Scenario: Rejecting content types
- **WHEN** the pipeline is handed a format outside
  jpeg/png/webp.
- **THEN** the client rejects it before the network with
  copy keyed on the media-type code (no speculative upload).

### Requirement: Variant Watch Terminates at Terminal State
The photos repository SHALL expose a `watch(costumeId)` stream that
refetches the costume view with bounded backoff until every watched
photo's variant `status` is terminal (`Ready` or `Failed`) and stops on
the last unsubscription — no polling while the screen is not visible.
`Failed` variants SHALL show a non-destructive explanation with the
"capture again" affordance (there is no variant retry command).

#### Scenario: Thumbnail becomes Ready
- **WHEN** an upload's variants transition Pending → Ready during the
  watch (bounded retries).
- **THEN** the gallery row renders the thumbnail fetched via the bytes
  endpoint; the watch ends for that photo.

#### Scenario: Subscriber leaves before terminal state
- **WHEN** the user navigates away while variants are still Pending.
- **THEN** the watch stops (no background polling); returning re-arms
  it with a fresh bounded pass.

### Requirement: Gallery From the Costume Projection and Delete
The photo gallery SHALL render from the photo references embedded in
`CostumeView.photos` (there is no separate photo-list route); bytes are
fetched per variant with an in-memory LRU only (never persisted to
Drift). Delete SHALL require explicit confirmation; on 204 the row is
removed optimistically and reconciled; failures surface keyed on
`code`.

#### Scenario: Deleting a photo
- **WHEN** the user confirms deletion of a costume photo.
- **THEN** the DELETE issues after the AUTHZ-GATE; on success the
  entry disappears from the gallery (optimistic, reconciled); on
  failure it remains with the error copy.

#### Scenario: Gallery empty state
- **WHEN** a costume has no photos.
- **THEN** an explicit empty state with the (gated) capture affordance
  renders — no placeholder images pretending to be photos.
