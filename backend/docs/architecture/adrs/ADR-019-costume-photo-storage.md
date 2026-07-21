# ADR-019: Costume Photo Storage — Aggregate, Garage, Proxy Serving, Derived Auth

- **Status:** Accepted
- **Date:** 2026-07-21
- **Supersedes:** ADR-009 Phase 1 (`fs` service plan is superseded / skipped)
- **Related:** ADR-009 (S3-compatible storage abstraction — Phase 1 `fs` skipped
  in favour of direct Garage), ADR-002 (CQRS/ES patterns — photo lifecycle is
  event-sourced; bytes are a side-effect), ADR-001 (Hexagonal Architecture),
  ADR-014 (Testcontainers Integration Testing), ADR-015 (SierraDB + Postgres
  projections), ADR-016 (SierraDB runtime and round-trip)
- **Source change:** `openspec/changes/add-costume-photo-storage`

## Context

The `Costume` aggregate already carries photo *linking* mechanics
(`PhotoLinked` / `PhotoUnlinked` events, `photos: Vec<Uuid>` state,
`projection_costume_photo` join, `CostumePhotoView`), but there is no
infrastructure to store, serve, or delete the actual image bytes. ADR-009
chose OpenDAL over a raw S3 client and sketched a three-phase rollout
(Phase 1 `fs` service, Phase 2 Garage, Phase 3 cloud S3).

Two constraints reshape the design beyond ADR-009's original sketch:

1. **Data economy & confidentiality.** Costume photos depict people (faces,
   actors in costume). EXIF (including GPS) MUST be stripped; every byte
   transfer MUST be authorized per-request.
2. **Single-source-of-truth for disaster recovery.** The rest of the system
   is event-sourced (SierraDB is the SSOT, Postgres projections are
   replay-derived). Photo bytes cannot be event-sourced (they are blobs),
   but the photo *lifecycle* (existence, content-type, size, variant status,
   deletion) MUST be — otherwise a Postgres loss leaves orphaned Garage
   objects and a Garage loss leaves dangling projection references with no
   way to detect them.

## Decision

We make four architectural decisions:

### D1: Garage-as-S3 (superseding ADR-009 Phase 1 `fs`)

Garage (`dxflrs/garage:v1.0.1`) is a Rust-based S3-compatible server
(< 1 GB RAM). It runs as a Docker container with **no host port mapping**
— only the API binary can reach it via the internal docker network. The
frontend never receives a direct Garage URL.

We skip ADR-009's Phase 1 (`fs` service) entirely: simulating S3 with a
filesystem would mask the real integration issues (HEAD semantics,
overwrite-by-default, `ListObjects` ordering, error XML shapes) that we
want to surface now while the integration is small. Going straight to Garage
makes the OpenDAL S3 path the only path; no migration from `fs` to S3 is ever
needed.

OpenDAL is the byte-storage abstraction, configured with the `services-s3`
feature. The key layout `{photo_id}/{variant}` is an infra-internal detail;
the `PhotoStorage` port only ever sees `PhotoId` + `PhotoVariant`.

### D2: Photo is an aggregate, not "just storage"

Photo *bytes* are blobs and cannot be event-sourced. But photo *lifecycle*
— existence, content-type, size, variant generation status, EXIF-stripped
flag, deletion — MUST be tracked in SierraDB so that:

- `projection_photo` and `projection_photo_variant` are replay-derived (same
  disaster-recovery story as the rest of the system).
- Variant STATUS (`pending` / `ready` / `failed`) is live aggregate state,
  not infra state hiding in a side table.
- An existing `PhotoUploaded` event with a missing Garage object is a
  *detectable* inconsistency (fetch returns 404; the saga can re-issue),
  rather than a silent dangling reference.

The refcount (N:M link to costumes) is derived via `COUNT(*)` over
`projection_costume_photo` — it does NOT live on the `Photo` aggregate,
keeping the two aggregates decoupled.

### D3: Proxy upload and proxy download (security over bandwidth)

The API receives bytes on upload and streams bytes on download; the frontend
never receives a presigned URL. Every download is authorized per-request via
`SeasonPhotoAccessPolicy`. `Cache-Control: private, max-age=300` lets the
client cache bytes for 5 minutes.

Presigned URLs are deferred: if a future use case needs them (e.g. CDN caching
of public marketing images), the `PhotoStorage` port can grow a `presigned_get`
method without restructuring the proxy path.

### D4: Derived authorisation v1 with documented v2 `SeasonCrew` evolution

**v1 (derived):** a user can view costume photos in Season S if they hold any
costume-dept role (`costume_designer`, `wardrobe_supervisor`,
`costume_assistant`) in any `active` block of Season S. This is implemented as
a `SeasonPhotoAccessPolicy` impl of the existing `AuthorizationPolicy` trait.

**The between-blocks gap:** a costumer between contracts (left Block 3, not
yet in Block 5) loses photo access. This is accepted as correct from a
security standpoint. The **v2 evolution** adds an additive `SeasonCrew`
aggregate with `SeasonCrewGranted` / `SeasonCrewRevoked` events; the policy
then checks `authorized = derived-from-active-block OR season-crew-grant`.
The upgrade is zero-downtime: the trait method signature is unchanged, only
the impl changes.

## Alternatives Considered

- **Photos as just storage + join tables (no aggregate, bespoke Garage scan
  to rebuild `projection_photo` on PG loss):** rejected — breaks the uniform
  "replay events to restore" recovery story; bespoke S3-aware reconciliation
  is a different procedure than the rest of the system.
- **Refcount on the Photo aggregate:** rejected — the link is a Costume concern
  (`PhotoLinked`/`PhotoUnlinked` live on the `Costume` stream); putting refcount
  on Photo would couple the two aggregates' event streams.
- **Presigned URLs for download:** rejected for v1 — they are bearer tokens
  for confidential photos depicting people; per-request authorisation is the
  only defensible posture. Presigned URLs are deferred as an additive v2 option.
- **Phase 1 `fs` service (per ADR-009):** rejected — simulating S3 with a
  filesystem would mask real S3 integration semantics we want to surface now.

## Consequences

- **Bandwidth:** Proxy download doubles API bandwidth (API streams bytes from
  Garage to client). Mitigation: gallery-scale traffic, not media-streaming;
  `Cache-Control: private, max-age=300` lets clients cache.
- **Latency:** Thumbnail saga is eventual; `VariantStatus = pending` for
  seconds after upload. The Flutter app shows a placeholder until `Ready`.
- **Memory:** `image` crate decode of a 12 MB camera JPEG uses ~100+ MB RAM.
  v1 accepts this for gallery-scale concurrent uploads.
- **Between-blocks gap:** documented as a v1 Non-Goal; v2 `SeasonCrew`
  aggregate is the explicit upgrade path.
- **C2PA unverified:** Re-encode is expected to strip C2PA JUMBF manifests,
  but this is not verified in v1. Honest spec states EXIF stripping only.
- **Garage backup risk:** Garage runs with a persistent named volume; if
  Garage is lost, projections still say photos exist (event-sourced); fetches
  return 404; users can re-upload.
- **Additive change:** No existing data migrated or reinterpreted. Disabling
  the API routes and not spawning the sagas/GC task reverts to pre-change
  behaviour.
