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

ALTER TABLE projection_costume
    ADD COLUMN category_id   UUID,
    ADD COLUMN category_name TEXT;
