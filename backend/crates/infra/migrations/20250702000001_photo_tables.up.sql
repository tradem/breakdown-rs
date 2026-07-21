-- Add projection tables for photo lifecycle (change: add-costume-photo-storage).
--
-- Photo bytes live in Garage (S3-compatible object store); these tables are
-- replay-derived from SierraDB events and track the lifecycle metadata.

CREATE TABLE projection_photo (
    photo_id     UUID PRIMARY KEY,
    content_type TEXT NOT NULL,
    size_bytes   BIGINT NOT NULL,
    version      BIGINT NOT NULL DEFAULT 1,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE projection_photo_variant (
    photo_id   UUID NOT NULL REFERENCES projection_photo(photo_id) ON DELETE CASCADE,
    variant    TEXT NOT NULL,       -- "original", "thumb", "medium"
    status     TEXT NOT NULL,       -- "pending", "ready", "failed"
    size_bytes BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (photo_id, variant)
);

CREATE TABLE projection_photo_gc_run (
    run_id           UUID PRIMARY KEY,
    started_at       TIMESTAMPTZ NOT NULL,
    finished_at      TIMESTAMPTZ,
    scanned          BIGINT NOT NULL DEFAULT 0,
    orphans_found    BIGINT NOT NULL DEFAULT 0,
    orphans_deleted  BIGINT NOT NULL DEFAULT 0,
    dry_run          BOOLEAN NOT NULL DEFAULT false
);

-- Index for the GC sweep: list known photo_ids efficiently.
CREATE INDEX idx_projection_photo_photo_id ON projection_photo(photo_id);
