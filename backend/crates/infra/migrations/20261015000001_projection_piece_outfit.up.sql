-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: deepseek-v4.1-flash (opencode-go)

-- Separate the wardrobe domain into `Piece` (fundus garment) and `Outfit`
-- (character look). Clean cut: the `projection_costume*` tables are dropped
-- and replaced by their piece/outfit successors — no compatibility view, no
-- data migration (no production streams exist; dev volumes are reset).
--
-- Rationale: a costume conflated the garment (category, repertoire, details)
-- with the character binding (which look a character wears). Pieces are
-- character-free; outfits compose 0..n pieces and belong to exactly one
-- character; scenes cast outfits.

-- ── piece (wardrobe fundus) ───────────────────────────────────────────
CREATE TABLE projection_piece (
    id                UUID PRIMARY KEY,
    name              TEXT NOT NULL,
    category_id       UUID,
    category_name     TEXT,
    notes             TEXT NOT NULL DEFAULT '',
    version           BIGINT NOT NULL,
    projector_version BIGINT NOT NULL DEFAULT 0,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Season repertoire (m:n): the seasons whose wardrobe lists the piece appears
-- in. This is the piece's only scope relation — there is deliberately no
-- character column.
CREATE TABLE projection_piece_season (
    piece_id  UUID NOT NULL REFERENCES projection_piece(id) ON DELETE CASCADE,
    season_id UUID NOT NULL,
    PRIMARY KEY (piece_id, season_id)
);

CREATE INDEX idx_projection_piece_season_season
    ON projection_piece_season(season_id);

-- Pure-description details: no category columns survive the cut.
CREATE TABLE projection_piece_detail (
    piece_id  UUID NOT NULL REFERENCES projection_piece(id) ON DELETE CASCADE,
    detail_id UUID NOT NULL,
    subject   TEXT,
    text      TEXT NOT NULL,
    PRIMARY KEY (piece_id, detail_id)
);

CREATE TABLE projection_piece_photo (
    piece_id UUID NOT NULL REFERENCES projection_piece(id) ON DELETE CASCADE,
    photo_id UUID NOT NULL,
    PRIMARY KEY (piece_id, photo_id)
);

CREATE INDEX idx_projection_piece_photo_photo
    ON projection_piece_photo(photo_id);

-- ── outfit (character look) ───────────────────────────────────────────
CREATE TABLE projection_outfit (
    id                UUID PRIMARY KEY,
    character_id      UUID NOT NULL,
    name              TEXT NOT NULL,
    variant_of        UUID,
    notes             TEXT NOT NULL DEFAULT '',
    version           BIGINT NOT NULL,
    projector_version BIGINT NOT NULL DEFAULT 0,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_projection_outfit_character
    ON projection_outfit(character_id);

-- Outfit composition. Deliberately NO foreign key to projection_piece:
-- cross-aggregate stream replay order is not guaranteed, and a missing piece
-- row must never poison the outfit projector. `position` preserves the
-- insertion order (layering is permitted, duplicates are not).
CREATE TABLE projection_outfit_piece (
    outfit_id UUID NOT NULL REFERENCES projection_outfit(id) ON DELETE CASCADE,
    piece_id  UUID NOT NULL,
    position  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (outfit_id, piece_id)
);

CREATE INDEX idx_projection_outfit_piece_piece
    ON projection_outfit_piece(piece_id);

CREATE TABLE projection_outfit_photo (
    outfit_id UUID NOT NULL REFERENCES projection_outfit(id) ON DELETE CASCADE,
    photo_id  UUID NOT NULL,
    PRIMARY KEY (outfit_id, photo_id)
);

CREATE INDEX idx_projection_outfit_photo_photo
    ON projection_outfit_photo(photo_id);

-- ── scene casting: costume beats -> outfit beats ──────────────────────
-- Ordered outfits per (scene, character). "A character in this scene wears
-- these outfits, in this order" stays a structural property: the primary key
-- rules out two outfits at one position and duplicate positions. Denseness of
-- `order` is an aggregate fact (max + 1 on add); the projector never
-- renumbers. No cascade to projection_outfit: an outfit is never deleted.
CREATE TABLE projection_scene_outfit_assignment (
    scene_id     UUID NOT NULL REFERENCES projection_scene(id) ON DELETE CASCADE,
    character_id UUID NOT NULL,
    "order"      INTEGER NOT NULL,
    outfit_id    UUID NOT NULL,
    note         TEXT,
    version      BIGINT NOT NULL,
    PRIMARY KEY (scene_id, character_id, "order")
);

-- Reverse lookup: in which scenes is this outfit worn?
CREATE INDEX idx_projection_scene_outfit_assignment_outfit
    ON projection_scene_outfit_assignment(outfit_id);

-- ── retire the costume projections ────────────────────────────────────
DROP TABLE IF EXISTS projection_scene_costume_assignment;
DROP TABLE IF EXISTS projection_costume_photo;
DROP TABLE IF EXISTS projection_costume_detail;
DROP TABLE IF EXISTS projection_costume_season;
DROP TABLE IF EXISTS projection_costume;

-- The photo binding discriminator now names piece/outfit bindings.
UPDATE projection_photo SET binding = 'Piece' WHERE binding = 'Costume';

-- Continuity photos referenced an optional garment (`costume_id`); the garment
-- is a fundus piece now, so the column follows the rename.
ALTER TABLE projection_continuity_photo RENAME COLUMN costume_id TO piece_id;
