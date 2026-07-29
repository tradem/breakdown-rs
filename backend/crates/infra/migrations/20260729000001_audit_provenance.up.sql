-- SPDX-License-Identifier: AGPL-3.0
-- Copyright (C) 2024-2026 Breakdown RS Contributors
--
-- Add `provenance` column to `projection_audit` so cross-cutting audit rows
-- carry the origin discriminator (Human / Saga(...) / System).
--
-- Prior to this column, the projector wrote `NULL` for provenance
-- (membership-only v1 had no provenance concept).  New rows written by the
-- generalized projector will populate it; pre-existing rows stay `NULL`.

ALTER TABLE projection_audit ADD COLUMN provenance TEXT;
