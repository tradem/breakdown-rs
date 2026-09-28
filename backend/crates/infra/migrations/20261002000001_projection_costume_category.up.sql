-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
-- Co-authored-by: glm-5.3-flash (opencode-go)

-- The costume's single category (issue #543): `category_id` moves from the
-- detail to the costume aggregate. The columns are nullable — a costume is
-- uncategorised until a `CostumeCategorySet` event (or the legacy-replay
-- derivation rule on `CostumeCreated`/`DetailAdded`) fills them. The
-- denormalised `category_name` is refreshed by the costume_category
-- projector on rename; a projection miss (dangling reference) stays NULL.
--
-- `projection_costume_detail.category_id/category_name` deliberately STAY
-- for legacy replay (the projector keeps writing them); a later migration
-- cleans them up once no client reads the detail category any more.
--
-- NO SQL BACKFILL (issue #543 obstacle 2, CodeRabbit review): the costume
-- events live in SierraDB, not in this Postgres database — a migration
-- cannot fold a stream in event order, and a detail-row-only backfill would
-- (a) use detail-ID ordering where the contract mandates event order, and
-- (b) re-adopt categories from detail rows after an explicit
-- `CostumeCategorySet(category_id = NULL)` clear. The upgrade path is a
-- REPLAY instead: reset the costume projector checkpoint and restart (see
-- `docs/operations/runbooks.md` → "Costume-category backfill (issue #543)")
-- — the projector then folds each stream in event order (derivation until
-- the first `CostumeCategorySet`, explicit Some/None override thereafter)
-- exactly like the aggregate's `apply`, keeping aggregate and projection
-- in parity. Until a deployment runs that replay, pre-existing rows read
-- `category_id = NULL` ("uncategorised"), which is a benign cosmetic state,
-- never a wrong category.

ALTER TABLE projection_costume
    ADD COLUMN category_id   UUID,
    ADD COLUMN category_name TEXT;
