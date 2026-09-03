---
description: Photo bounded context (aggregate, sagas, Garage/S3 storage, GC) - loaded when reading photo code or storage config.
applyTo:
  - "crates/*/src/photo/**"
  - "docker-compose*"
  - "scripts/**"
---

<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.3 (neuralwatt) -->

# Photo bounded context (ADR-019)

`photo` is a bounded context (category `"photo"`) that tracks the lifecycle of costume and
continuity photos (ADR-019). The `Photo` aggregate is event-sourced in SierraDB and stores photo
metadata (content-type, size, variant statuses, `binding`). `binding: PhotoBinding` discriminates
between `Costume { costume_id }` (default for historical events) and `Continuity { scene_shoot_id, costume_id? }`.
The actual image bytes live in **Garage** (S3-compatible object store) accessed via OpenDAL. The
`PhotoStorage` port is a **non-CQRS-split CRUD port** for byte storage (read and write on the
same store), distinct from the command/repository split used by other aggregates. Three sagas
react to photo events:
- `PhotoThumbnailSaga` — on `PhotoUploaded`, fetches original bytes, decodes+re-encodes
  EXIF-stripped, generates Thumb (200×200) and Medium (800×800) variants.
- `PhotoDeletionSaga` — on `PhotoUnlinked` (costume stream), checks refcount via
  `COUNT(*)` on `projection_costume_photo`; dispatches `DeletePhoto` when zero.
- `ContinuityDeletionSaga` — on `ContinuityPhotoUnlinked` (scene_shoot stream), tracks
  in-memory refcounts; checks costume-side refs before dispatching `DeletePhoto` at zero.
- `PhotoBytesCleanupSaga` — on `PhotoDeleted`, removes all variant bytes from Garage.

A periodic `PhotoGcSweepTask` (advisory-locked) reconciles Garage objects against
`projection_photo` and deletes orphans older than `PHOTO_GC_MAX_AGE_SECS`.

**Continuity photo authz:** Handlers under `/shooting-days/{day_id}/scenes/{scene_id}/scene-shoots/{shoot_id}/continuity-photos`
are gated only by `Requirement::Authenticated` and use handler-internal authz (season-scoped
membership check via the shooting_day → episode → block → season chain). They follow the same
`// AUTHZ-GATE:` pattern as the costume photo handlers.


# Photo storage (Garage / S3) — env vars


#### Photo storage (Garage / S3)
- `S3_ENDPOINT` – Garage S3 API endpoint (e.g. `http://garage:3900` in dev; `https://caddy:9443` in production — the Caddy internal TLS site, ADR-024)
- `S3_ACCESS_KEY` – Garage access key
- `S3_SECRET_KEY` – Garage secret key
- `S3_BUCKET` – S3 bucket name (default: `costume-photos`)
- `S3_REGION` – S3 region for OpenDAL (default: `garage`; override for AWS-style external buckets)
- `S3_TLS_ROOT_CERT` – optional PEM path of the pinned root CA for `https://` S3 endpoints (the internal step-ca root in production); OpenDAL pins it via a custom reqwest client
- `PHOTO_MAX_SIZE_MB` – maximum upload size in MB (default: `20`)
- `PHOTO_GC_ENABLED` – enable periodic orphan GC (default: `true`)
- `PHOTO_GC_INTERVAL_SECS` – GC sweep interval (default: `3600`)
- `PHOTO_GC_MAX_AGE_SECS` – only sweep orphans older than this (default: `86400`)
- `PHOTO_GC_BATCH_SIZE` – max orphans per run (default: `1000`)
- `PHOTO_GC_DRY_RUN` – log-only mode (default: `false`; set `true` for first rollout)

