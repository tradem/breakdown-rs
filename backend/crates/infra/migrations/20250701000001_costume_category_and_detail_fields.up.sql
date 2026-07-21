-- Add categorisation slots to costume details and a season-scoped
-- costume-category vocabulary table (change: categorize-costume-parts).

ALTER TABLE projection_costume_detail
    ADD COLUMN subject       TEXT,
    ADD COLUMN category_id    UUID,
    ADD COLUMN category_name  TEXT;   -- denormalised; refreshed by costume_category projector

CREATE TABLE projection_costume_category (
    id          UUID PRIMARY KEY,
    season_id   UUID NOT NULL,
    name        TEXT NOT NULL,
    order_key   TEXT NOT NULL,
    archived    BOOLEAN NOT NULL DEFAULT false,
    version     BIGINT NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_projection_costume_category_season
    ON projection_costume_category(season_id, order_key);
