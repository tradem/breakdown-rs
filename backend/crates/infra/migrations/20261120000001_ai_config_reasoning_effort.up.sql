-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Requested `reasoning_effort` for the assistant model (2026-11-20
-- output-budget investigation).
--
-- NULL is the meaningful default and not a missing value: it means "send no
-- field", i.e. the provider's own default — exactly the behaviour of every
-- configuration written before this column existed. The value is validated
-- against the provider/model capability at save time, so the column only ever
-- holds a level that pair declares.
ALTER TABLE ai_import.projection_ai_config
    ADD COLUMN reasoning_effort TEXT;
