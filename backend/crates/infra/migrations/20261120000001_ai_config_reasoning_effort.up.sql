-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors

-- Requested `reasoning_effort` for the assistant model (2026-11-20
-- output-budget investigation).
--
-- NULL means "no explicit level" — the stored `ReasoningEffortChoice::Auto`.
-- Resolution happens at request-build time: the curated profile of the
-- `(provider, model)` pair if one applies, otherwise the provider's own default.
-- That is exactly the behaviour of every configuration written before this
-- column existed. An explicit level is validated against the provider/model
-- capability at save time, so the column only ever holds a level that pair
-- declares.
ALTER TABLE ai_import.projection_ai_config
    ADD COLUMN reasoning_effort TEXT;
