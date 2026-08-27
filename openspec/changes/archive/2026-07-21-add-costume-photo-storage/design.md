## Context

ADR-009 chose OpenDAL over an S3-compatible API for photo storage, with a
three-phase rollout (Phase 1 `fs` service, Phase 2 Garage, Phase 3 cloud S3).
The `Costume` aggregate already carries photo *linking* mechanics
(`PhotoLinked` / `PhotoUnlinked` events, `photos: Vec<Uuid>` state, the
`projection_costume_photo` join, `CostumePhotoView`), but there is no
infrastructure to store, serve, or delete the actual image bytes.

This change closes that gap. Two constraints reshape the design beyond ADR-009's
original sketch:

1. **Data economy & confidentiality.** Costume photos depict people (faces,
   actors in costume). EXIF (incl. GPS) MUST be stripped; every byte transfer
   MUST be authorized per-request.
2. **Single-source-of-truth for disaster recovery.** The rest of the system
   is event-sourced (SierraDB is the SSOT, Postgres projections are
   replay-derived). Photo bytes cannot be event-sourced (they are blobs), but
   the photo *lifecycle* (existence, content-type, size, variant status,
   deletion) MUST be — otherwise a Postgres loss leaves orphaned Garage objects
   and a Garage loss leaves dangling projection references with no way to
   detect them.

Current state of the Costume photo model (preserved unchanged by this change):

```
CostumeAggregate.photos: Vec<Uuid>
CostumeEvent::PhotoLinked { id, photo_id, version }
CostumeEvent::PhotoUnlinked { id, photo_id, version }
projection_costume_photo (costume_id, photo_id) — the M:N join
CostumePhotoView { id: Uuid } — bare reference
```

## Goals / Non-Goals

**Goals:**
- Make photo upload real: store bytes, serve bytes, delete bytes.
- Store bytes in Garage (S3-compatible), accessed via OpenDAL — skip the
  Phase 1 `fs` simulation because it would mask real S3 integration semantics.
- Keep every projection replay-derived from SierraDB events — the photo
  *lifecycle* is an aggregate; the bytes are a side-effect.
- Strip EXIF (incl. orientation handling) from every stored image, including
  the original — enforce data economy by default.
- Authorize every byte transfer per-request (no bearer-token URLs).
- Support N:M photo ↔ costume links with refcount-driven byte deletion.
- Provide a periodic, advisory-locked orphan GC with a history table.
- Testcontainers coverage for Garage (Tier-3 adapter, Tier-4 round-trip).
- Document the v1 authorization limitation ("between-blocks gap") and the v2
  `SeasonCrew` evolution path.

**Non-Goals:**
- A `SeasonCrew` aggregate (v2 evolution; documented below).
- API-driven GC config endpoints (`/admin/photo-gc/*`) — env-configured in v1.
- Presigned URLs for direct client ↔ Garage transfer — proxy-only serving in
  v1 for security.
- C2PA manifest handling verification — a spike to confirm C2PA stripping via
  re-encode is deferred; for v1 we state honestly that EXIF and embedded
  EXIF-style metadata are stripped, C2PA is *expected* to be stripped by the
  same re-encode but is not verified.
- AI-image provenance preservation — out of scope; data-economy priority means
  stripping regardless.
- `turbojpeg` / `libheif` native dependencies — pure-Rust `image` crate is
  the v1 choice; a perf spike is deferred.
- HEIC/HEIF decode on the server — rejected on upload with a clear error;
  clients (Flutter/web) convert before upload.
- Multi-replica GC (the advisory lock is designed-for but untested in v1).
- Hot-reload of GC config.

## Decisions

### Decision 1: Photo is an aggregate, not "just storage"

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

```
SierraDB (SSOT)                        Postgres (replay-derived)         Garage (bytes side-effect)
 PhotoUploaded ─────────────────────►  projection_photo                 (saga stores bytes here)
 VariantGenerated ──────────────────►  projection_photo_variant
 PhotoDeleted ──────────────────────►  rows removed                     (saga deletes bytes here)
```

**Alternatives considered:**
- *Photos as just storage + join tables (no aggregate, bespoke Garage scan
  to rebuild `projection_photo` on PG loss):* rejected — breaks the
  uniform "replay events to restore" recovery story; bespoke S3-aware
  reconciliation is a different procedure than the rest of the system.
- *Refcount on the Photo aggregate:* rejected — the link is a Costume concern
  (`PhotoLinked` / `PhotoUnlinked` live on the `Costume` stream); refcount is
  derived via `COUNT(*)` over `projection_costume_photo`, keeping the two
  aggregates decoupled.

### Decision 2: Garage as the S3 backend, Docker-internal-only

Garage (`dxflrs/garage:v1.0.1`) is a Rust-based S3-compatible server (< 1 GB
RAM), matching ADR-009's Phase 2 recommendation. It runs as a Docker
container with **no host port mapping** — only the API binary can reach it via
the internal docker network. The frontend never receives a direct Garage URL.

```
┌─ Docker network: breakdown-net ────────────────────────────────┐
│                                                                │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐         │
│  │  API binary  │   │  Postgres    │   │  SierraDB    │         │
│  │  (host:3000) │   │  (host:5432) │   │  (host:9090)│         │
│  └──────┬───────┘   └──────────────┘   └──────────────┘         │
│         │  (internal only, no host port)                        │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │   Garage     │  S3 API on internal:3900, admin on :3902     │
│  │   bucket:    │                                               │
│  │  costume-    │                                               │
│  │   photos     │                                               │
│  └──────────────┘                                               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

**Why skip ADR-009 Phase 1 (`fs`):** simulating S3 with a filesystem would
mask real integration issues — HEAD semantics, overwrite-by-default,
`ListObjects` ordering, error XML shapes — that we want to surface now while
the integration is small. Going straight to Garage makes the OpenDAL S3 path
the only path; no migration from `fs` to S3 is ever needed.

**OpenDAL key layout (adapter detail, not exposed to the port):**
`{photo_id}/{variant}` — flat, metadata-indexed by Garage (no prefix
optimisation needed, unlike legacy AWS S3). The `PhotoStorage` port only ever
sees `PhotoId` + `PhotoVariant`; key construction is an infra concern.

### Decision 3: Proxy upload and proxy download

```
UPLOAD (proxy):                          DOWNLOAD (proxy):
Frontend ──multipart──► API ──store──► Garage   Frontend ──GET /bytes──► API ──fetch──► Garage
                          │                                  │
                          └─UploadPhoto cmd─► SierraDB       └─stream bytes (Cache-Control: private, max-age=300)
                                                                authz checked on EVERY request
```

- The API receives bytes on upload and streams bytes on download.
- The frontend never receives a presigned URL.
- Every download is authorized per-request via `SeasonPhotoAccessPolicy`.
- `Cache-Control: private, max-age=300` lets the Flutter app / browser cache
  bytes for 5 minutes (keyed by photo_id, not by token — no stale-URL
  problem).

**Why not presigned URLs:** presigned URLs are bearer tokens. Even with a
5-minute expiry, they are a leak surface (logs, screenshots, shared devices).
For confidential photos depicting people, per-request authorisation is the
only defensible security posture. The bandwidth cost (API streams bytes) is
acceptable for a gallery-scale app, not a media-streaming service.

**Presigned URLs are deferred (not abandoned):** if a future use case needs
them (e.g. CDN caching of public marketing images), the `PhotoStorage` port
can grow a `presigned_get` method without restructuring the proxy path — the
two are additive.

### Decision 4: Three variants, EXIF stripped everywhere (incl. original)

```
{photo_id}/original   ← re-encoded upright, EXIF stripped (quality ~95)
{photo_id}/thumb      ← ~200×200, JPEG quality 80, ~20-50 KB
{photo_id}/medium     ← ~800×800, JPEG quality 85, ~100-200 KB
```

Thumbnails are always JPEG (smallest, most compatible — PNG screenshots are
converted; acceptable quality).

**EXIF handling (orientation-aware):**
1. Decode JPEG → `DynamicImage` (raw pixels, wrong orientation).
2. Read EXIF Orientation (6, 3, 8 are common rotations) via `kamadak-exif`.
3. Apply rotation to `DynamicImage` (`image::imageops::rotate90/180/270`).
4. Re-encode → JPEG without EXIF, correctly oriented.

The `image` crate's re-encode does not propagate EXIF or JUMBF (C2PA)
segments, so re-encoding strips both. C2PA stripping via re-encode is
*expected* but not verified in v1 — see Open Questions.

**The thumbnail saga also re-encodes the original.** The temporary window
between upload and saga completion (seconds) has the raw uploaded bytes in
Garage with EXIF; no client downloads during that window (the photo is not
returned in `CostumeView` until `variants[].status = Ready`).

**AI-generated image metadata:** EXIF fields embedded by AI tools
(Midjourney, DALL·E, Stable Diffusion exports — `UserComment`, `Software`,
`ImageDescription`) are EXIF and are stripped by the re-encode. C2PA
manifests (Adobe Firefly and similar) are JUMBF boxes, expected stripped by
re-encode but not verified in v1.

### Decision 5: Content-type allowlist; HEIC rejected

```
Accepted: image/jpeg, image/png, image/webp
Rejected: image/heic, image/heif → 415 Unsupported Media Type
           ("HEIC not supported. Convert to JPEG before upload.")
Size cap: PHOTO_MAX_SIZE_MB (default 20 MB)
```

HEIC is the iPhone camera default. The pure-Rust `image` crate does not
decode HEIC; browsers (except Safari) and Flutter-on-Android do not render
HEIC natively. Rather than add `libheif` (C dependency in the Docker image),
the responsibility is pushed to the client: the Flutter app and the web
frontend convert HEIC → JPEG before upload (using the `image` Dart package or
a HEIC plugin; browsers use native canvas APIs). The server stays pure Rust
and rejects HEIC if it arrives, with a clear error.

Normalising both clients from scratch (the user's confirmed posture) lets us
avoid obscure format support entirely.

### Decision 6: N:M link with refcount-driven deletion

A photo can be linked to multiple costumes. The link itself is a `Costume`
event (`PhotoLinked` / `PhotoUnlinked`, unchanged); the refcount is derived
via `COUNT(*)` over `projection_costume_photo`.

```
PhotoUnlinked (costume A, photo P) fires
    │
    ▼
PhotoDeletionSaga:
  1. (the projector already deleted the projection_costume_photo row
     for costume=A, photo=P — that's the Costume projector's job)
  2. SELECT count(*) FROM projection_costume_photo WHERE photo_id = P
  3. IF refs == 0: dispatch DeletePhoto(P, version) on the Photo aggregate
       └─► PhotoDeleted event ──► PhotoBytesCleanupSaga ──► delete_all(P) from Garage
     ELSE: do nothing — the photo is still referenced
```

**Why refcount lives on the projection, not the aggregate:** the link is a
Costume concern (the Costume aggregate owns `PhotoLinked` / `PhotoUnlinked`).
Putting the refcount on the Photo aggregate would couple the two aggregates'
event streams. Deriving refcount via `COUNT(*)` over the join keeps them
decoupled; the deletion saga is the bridge.

### Decision 7: Thumbnail saga reacts to `PhotoUploaded`; deletion is a saga chain

```
PhotoUploaded (event) ──────► PhotoThumbnailSaga
                               ├─ fetch original bytes from Garage
                               ├─ decode + rotate + re-encode original (EXIF-stripped)
                               ├─ dispatch NormalizeOriginal → OriginalNormalized event
                               ├─ generate thumb → dispatch GenerateVariant → VariantGenerated
                               └─ generate medium → dispatch GenerateVariant → VariantGenerated
                               (on error: MarkVariantFailed → VariantFailed)

PhotoUnlinked (Costume event) ─► PhotoDeletionSaga
                                  ├─ refcount check via COUNT(*) on projection_costume_photo
                                  └─ if 0: dispatch DeletePhoto on Photo aggregate
                                       └─► PhotoDeleted event ─► PhotoBytesCleanupSaga
                                                                  └─ delete_all(P) from Garage

(periodic) PhotoGcSweepTask ─► reconcile projection_photo vs Garage listing
                                └─ delete orphans older than MAX_AGE gate (advisory-locked)
```

This follows the existing saga pattern (compare `SeasonSeedingSaga` reacting
to `SeasonCreated`).

### Decision 8: Authorisation v1 — derived; v2 — SeasonCrew (documented)

**v1 (Option A — Derived):** a user can view costume photos in Season S if
they hold any costume-dept role (`costume_designer`, `wardrobe_supervisor`,
`costume_assistant`) in any `active` block of Season S.

```sql
SELECT 1 FROM projection_membership m
JOIN projection_block b ON b.id = m.block_id
WHERE m.user_id = $1
  AND b.season_id = $2
  AND m.role IN ('costume_designer','wardrobe_supervisor','costume_assistant')
  AND m.state = 'active'
LIMIT 1
```

Resolved as an impl of `AuthorizationPolicy` (`SeasonPhotoAccessPolicy`),
consistent with the existing `MembershipAuthorizationPolicy` for blocks.

**The between-blocks gap:** a costumer between contracts (left Block 3, not
yet in Block 5) loses photo access. This is arguably *correct* from a security
standpoint (when you're not on the production, you don't get confidential
photos). For users who need persistent access (freelance designers doing
pre-production outside a block), v2 adds an explicit season-scoped grant.

**v2 (Option B — SeasonCrew aggregate, additive, documented here):**

| Trigger for upgrade | Upgrade plan |
|---|---|
| Users hitting the between-blocks gap | Add `SeasonCrew` aggregate (events: `SeasonCrewGranted`, `SeasonCrewRevoked`) |
| Audit finding that long-term costume staff need persistent access | Update `SeasonPhotoAccessPolicy`: `authorized = derived-from-block OR season-crew-grant` |
| | Optional auto-promote saga: on first block join with a costume role, auto-grant season crew (sticky until explicit revoke) |

Migration is zero-downtime and additive: the derived path keeps working; the
`OR season-crew-grant` branch is added; no data backfill is needed (grants
are created as needed). The `SeasonPhotoAccessPolicy` trait method signature
is unchanged — only the impl changes.

This evolution is captured as a Non-Goal in v1 with a pointer to this section.

### Decision 9: Periodic orphan GC — env-configured in v1, API-driven in v2

**Orphan scenarios:**
1. Upload succeeded, `UploadPhoto` command failed (version conflict, network)
   → bytes in Garage, no event.
2. Upload succeeded, client crashed before issuing upload command.
3. `PhotoLinked` event projected but projector crashed before
   `projection_costume_photo` insert → bytes stored, projection missing.
4. Test data / manual `eappend`s leaving dangling bytes.

**v1 design (separate concerns):**

```
PhotoGcScheduler          PhotoGcSweep (pure logic, parameterised by PhotoGcConfig)
 - decides WHEN           - lists Garage objects (PhotoStorage::list)
 - env-configured         - lists projection_photo rows (PhotoRepository)
   interval               - reconciles: orphans = garage - known
 - may be API later       - deletes orphans with MAX_AGE gate
                          - writes projection_photo_gc_run history
```

**v1 env vars:**
- `PHOTO_GC_ENABLED` (default `true`)
- `PHOTO_GC_INTERVAL_SECS` (default `3600` — 1 hour)
- `PHOTO_GC_MAX_AGE_SECS` (default `86400` — only sweep objects older than 24h;
  protects against in-flight uploads whose window is seconds, not days)
- `PHOTO_GC_BATCH_SIZE` (default `1000` — cap per-run work)
- `PHOTO_GC_DRY_RUN` (default `false` — set `true` for the first rollout)

**v2 evolution:** `PhotoGcConfig` is already a domain type in v1. v2 reads it
from a `projection_config` table (singleton row keyed by config name) and
exposes `GET/PATCH /admin/photo-gc/config`, `POST /admin/photo-gc/run`,
`GET /admin/photo-gc/runs[/{id}]`. The scheduler reloads config every N
(env-configurable) ticks so UI edits take effect without restart.

**Concurrency safety:** a Postgres advisory lock
(`SELECT pg_try_advisory_lock($1)`) at sweep start guarantees at most one
sweep per cycle, even under future multi-replica deploys. v1 is single-process
(`tokio::spawn` of one task; no `tokio::spawn` inside the sweep loop),
but the advisory lock is included now as cheap insurance.

### Decision 10: Testcontainers for Garage (ADR-014 one-harness rule)

- **Tier 3 (PG + Garage):** `OpenDalPhotoStorage` adapter — `store`, `fetch`,
  `delete_all`, `store_variant` against real S3 semantics; verifies HEAD,
  overwrite, listing behaviour against Garage.
- **Tier 4 (PG + SierraDB + Garage):** full saga round-trip — upload →
  `PhotoUploaded` → `PhotoThumbnailSaga` generates variants + normalises
  original → poll `projection_photo_variant` until `Ready` → assert thumb
  dimensions (decode, check) → assert original has no EXIF (decode with exif
  reader, expect `None`) → proxy download bytes match → `DELETE` →
  `PhotoUnlinked` → refcount saga → `PhotoDeleted` → bytes gone from Garage.
  N:M variant: link P to costumes A and B, unlink from A (bytes survive),
  unlink from B (bytes gone). GC variant: write orphans directly into Garage
  without `UploadPhoto`, run sweep, assert orphans deleted with `MAX_AGE`
  gate respected.

Excluded from `cargo-mutants` (consistent with the existing Tier-3/Tier-4
policy in `.cargo/mutants.toml`).

## Risks / Trade-offs

- **[Bandwidth]** Proxy download doubles API bandwidth (API streams bytes from
  Garage to client). → *Mitigation:* `Cache-Control: private, max-age=300`
  lets clients cache; gallery-scale traffic, not media-streaming. Presigned
  URLs are a v2 option for non-confidential content if a use case emerges.
- **[Latency]** Thumbnail saga is eventual; `VariantStatus = pending` for
  seconds after upload. → *Mitigation:* `CostumePhotoView.variants[].status`
  is exposed; the Flutter app shows a placeholder until `Ready`. The window
  is seconds (one decode + three re-encodes for a typical camera photo).
- **[Memory]** `image` crate decode of a 12 MB camera JPEG uses ~100+ MB RAM
  (full pixel decode). → *Mitigation:* v1 accepts this (gallery-scale
  concurrent uploads are low). v2 spike: `turbojpeg` (libjpeg-turbo bindings)
  for faster/lower-memory decode if负载 warrants.
- **[Between-blocks gap]** v1 derived authorisation revokes photo access when
  a costumer's last block membership ends. → *Mitigation:* documented as a v1
  Non-Goal; v2 `SeasonCrew` aggregate is the explicit upgrade path.
- **[C2PA unverified]** Re-encode is expected to strip C2PA JUMBF manifests,
  but this is not verified in v1. → *Mitigation:* stated honestly in the spec;
  a verification spike with sample AI-generated images is an Open Question.
- **[Garage backup]** Garage is a SSOT for bytes (events say bytes *should*
  exist; an existing `PhotoUploaded` event + missing Garage object is
  detectable loss). → *Mitigation:* Garage runs with a persistent named
  volume in both dev and prod compose; the prod runbook documents volume
  snapshot backup. If Garage is lost, projections still say photos exist
  (event-sourced); fetches return 404; users can re-upload (the upload
  re-issues `UploadPhoto`).
- **[Saga failure during variant generation]** `VariantFailed` is a terminal
  state for that variant; the original may still be `Ready`. → *Mitigation:*
  `VariantFailed` carries an error message; a future admin endpoint can
  re-trigger generation. v1 leaves failed variants visible as failed in the
  read model (honest state); the original is still downloadable.
- **[Orphan GC deletes in-flight uploads]** if `MAX_AGE` is mis-configured
  below the upload window. → *Mitigation:* default `MAX_AGE_SECS=86400`
  (24h) is orders of magnitude above the seconds-scale upload window; the gate
  is documented and env-configurable.

## Migration Plan

This is additive — no existing data is migrated or reinterpreted.

1. **Crates**: add `opendal`, `image`, `kamadak-exif` to `crates/infra/Cargo.toml`.
2. **Migrations**: new `projection_photo`, `projection_photo_variant`,
   `projection_photo_gc_run` tables. `projection_costume_photo` already
   exists and is unchanged.
3. **Docker**: add `garage` service to `docker-compose.dev.yml` and
   `docker-compose.prod.yml` (internal-only). Document env vars
   (`S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET`) and the
   boot sequence (bucket + key provisioning before API start) in
   `backend/AGENTS.md`.
4. **ADRs**: write **ADR-019** recording (a) the Garage-as-S3 decision
   (superseding ADR-009's Phase 1 `fs` plan), (b) the Photo-as-aggregate
   decision (SSOT alignment), (c) the proxy-only serving decision
   (security over bandwidth), (d) the derived-authorisation v1 decision with
   the v2 `SeasonCrew` evolution pointer. Cross-link from ADR-009.
5. **Rollout**: ship with `PHOTO_GC_DRY_RUN=true` for the first deployment;
   observe orphan detection logs; flip to `false` after a confidence window.
6. **Rollback**: the feature is additive. Disabling the API routes (return
   503) and not spawning the sagas/GC task reverts to pre-change behaviour.
   Garage can be stopped; `projection_photo_*` tables remain empty. Existing
   `Costume` photo-link events are unchanged, so no data inconsistency.

## Open Questions

- **C2PA stripping verification.** Re-encode via the `image` crate is
  *expected* to strip JUMBF (C2PA) segments because the re-encode only carries
  pixel data, but this is not verified in v1. A spike with sample
  AI-generated images (Adobe Firefly, Synthesia) should confirm before any
  claim of C2PA stripping is relied upon. v1 spec states EXIF stripping only.
- **Variant sizes.** 200×200 (thumb) and 800×800 (medium) are proposed.
  Confirm against the actual Flutter UI mockups before committing — some UIs
  want 64×64 avatars or 128×128 list tiles. Adding a variant later is
  additive (new enum variant + saga step; projection gains a row).
- **Photo storage of non-costume entities.** This design is scoped to costume
  photos. If photos are later needed for characters, scenes, or shooting days,
  the `PhotoStorage` port generalises, but the link semantics
  (`PhotoLinked`/`PhotoUnlinked`) live on each owning aggregate. A future
  change would extend those aggregates; the Photo aggregate itself is
  already owner-agnostic (it only knows its own lifecycle).
