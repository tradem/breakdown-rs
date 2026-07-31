-- Add `binding` column to `projection_photo` so downstream consumers
-- (continuity deletion saga, read adapters) can query the binding without
-- depending on a serde default. Historical rows default to Costume
-- (the historical default).

ALTER TABLE projection_photo
    ADD COLUMN IF NOT EXISTS binding TEXT NOT NULL DEFAULT 'Costume';
