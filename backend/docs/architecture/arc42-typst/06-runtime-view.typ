// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)
// Co-authored-by: gemini-4-carbon (google)

#import "template.typ": *


= Runtime View

== Scenario 1: Create Scene with Middleware AuthZ

#diagram("create-scene-sequence", caption: [POST /v1/scenes write path with middleware authorization])

*Key properties*:

- `auth_middleware` checks the RS256 OIDC JWT, and `authorize_middleware`
  checks active `BlockMember` membership against the `X-Active-Block` header.
- The `POST /v1/scenes` handler reads `projection_episode` at the API edge to
  attach `project_id` to `CreateScene` before command execution.
- `SceneAggregate` checks domain invariants and emits `SceneCreated` (`Manual`
  source) to SierraDB.
- `SceneProjector` writes `projection_scene`, while `SceneAuditProjector` writes
  `projection_audit` from a separate subscription and checkpoint, so a scene can
  appear before its audit row.

== Scenario 2: Cross-Aggregate Uniqueness Reservation

Four global uniqueness rules span multiple aggregates: season numbers, block
numbers, episode numbers per `project_id`, and `(scene_id, shooting_day_id)`
pairs (#adr-ref(num: "036", slug: "es-native-reservation-streams-cross-aggregate-uniqueness", title: "Reservation Streams")).

+ The API handler runs an advisory read-model check and returns `409` if a
  conflict already exists in PostgreSQL.
+ For a never-used key, the command adapter appends a claim event to the
  deterministic `reservation` stream with `ExpectedVersion::Empty`.
+ If the stream already exists (`WrongVer`), the adapter reads its latest event.
  It reclaims a released key with `ExpectedVersion::Exact(last_version)` or
  reuses an existing claim owned by the same aggregate. It returns `409` only
  for a competing holder or exhausted CAS retries.
+ After the aggregate event appends, the background reservation reaper marks
  realized claims consumed and releases orphaned crash claims after TTL expiry.
+ Projectors keep savepoint-isolated unique constraints (`#404`) and the
  `projection_dead_letter` table (`#37`) as final safety layers.

== Scenario 3: Query Scenes with Client Drift Cache

#diagram("query-scenes-sequence", caption: [GET /v1/scenes read path and Flutter Drift cache refresh])

*Key properties*:

- The Flutter repository emits cached rows from local Drift SQLite immediately
  for fast startup and brief network drops.
- `GET /v1/scenes?episode_id=...` queries `projection_scene` in PostgreSQL
  ordered by `scene_number, updated_at DESC`. The client reads all pages before
  it replaces the Drift snapshot.
- Neither SierraDB nor any aggregate actor runs on the read path.

== Scenario 4: Upload Piece Photo and Thumbnail Saga

#diagram("photo-upload-saga-sequence", caption: [POST /v1/pieces/{id}/photos with inline compensation and thumbnail saga])

*Key properties*:

- The handler checks MIME type (`image/jpeg`, `image/png`, or `image/webp`),
  enforces `PHOTO_MAX_SIZE_MB`, and runs the project-scoped `AUTHZ-GATE`.
- The handler stores `Original` bytes in Garage, then sends `UploadPhoto` and
  `LinkPiecePhoto`. If a command fails, the handler attempts best-effort byte
  deletion (`delete_all`) and logs any storage error. It then returns the
  command error, and an accepted `PhotoUploaded` event is not rolled back.
- The handler builds `PhotoView` from the command result and returns
  `201 Created` without waiting for the projector.
- `PhotoThumbnailSaga` reacts to `PhotoUploaded` and overwrites `Original` with
  an EXIF-stripped JPEG. It writes `Thumb` (max `200x200`) and `Medium` (max
  `800x800`) variants to Garage and records variant completion events.
- When users unlink photos, `PhotoDeletionSaga` and `ContinuityDeletionSaga`
  check combined reference counts and send `DeletePhoto` only at zero.

== Scenario 5: AI Script Import, SSE Progress, and Apply

+ The client uploads a screenplay or CSV schedule with `X-Active-Block` or
  `X-Declared-Season` (#adr-ref(num: "039", slug: "target-less-ai-import-declared-season-and-set-once-attach", title: "Target-Less AI Import")).
+ The handler checks `effective_costume_role_in_season` and writes the source
  blob to Garage. A new import inserts a `pending` job. A deduplicated match
  returns `200` with the existing job ID and attempts to delete the duplicate
  blob.
+ A worker claims the job, starts its claim lease heartbeat, and loads the
  source document from Garage before it acquires a cancellation-safe extraction
  concurrency permit.
+ If a `(provider, model)` pair hits repeated transient errors, the durable
  circuit breaker opens and holds matching jobs until a probe succeeds.
+ During extraction, the worker writes fenced progress updates and sends
  PostgreSQL `NOTIFY` events that stream to the Flutter client over SSE (#adr-ref(num: "038", slug: "ai-import-sse-progress-and-event-hub", title: "AI Import SSE Progress")).
+ The user reviews the static preview, attaches a target block if needed, and
  triggers `POST /v1/ai-import/jobs/{id}/apply` to run validated domain commands.
