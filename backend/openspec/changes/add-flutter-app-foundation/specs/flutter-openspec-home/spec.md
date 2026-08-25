<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Canonical OpenSpec Root at Monorepo Root
The canonical OpenSpec root for the `breakdown-rs` monorepo SHALL be
`/openspec/` at the repository root (`breakdown-rs/openspec/`), not nested
under `backend/`. All capabilities — backend, frontend-flutter, and any
future frontend — live as siblings under `openspec/specs/<capability>/`.
Backend capabilities keep their existing names; Flutter capabilities use the
`flutter-*` prefix.

> Rationale: the monorepo already hosts two frontend trees
(`frontend-web/`, future `frontend-flutter/`) plus the backend. A single
shared OpenSpec root at the top level keeps cross-cutting specs reviewable
in one place and avoids per-frontend store registration overhead. The
existing `backend/openspec/` is a historical location to be migrated
(see `flutter-openspec-home/migration` follow-up task), not the target.

#### Scenario: A new Flutter capability spec is authored
- **WHEN** a contributor runs `openspec new change` after migration.
- **THEN** the working root is `breakdown-rs/openspec/` and the new
  capability lands under `openspec/specs/flutter-<name>/`.

#### Scenario: A backend capability spec is edited post-migration
- **WHEN** a contributor edits e.g. `http-error-surface/spec.md`.
- **THEN** the file lives at `openspec/specs/http-error-surface/spec.md`
  (moved from `backend/openspec/specs/...`), and `openspec validate` runs
  against the monorepo root.

### Requirement: Migration of Existing Backend Specs Is a Separate Follow-up
The mechanical move of all existing `backend/openspec/**` content to
`/openspec/**` SHALL NOT be performed inside this change. It is tracked as
a distinct follow-up change (`migrate-openspec-to-monorepo-root`) so that
the (large) rename diff is reviewable on its own and does not muddle this
foundation change. Until that migration lands, this change's artifacts
remain at their created location (`backend/openspec/changes/add-flutter-app-foundation/`)
and validate against the `backend/` nearest root.

#### Scenario: This change is archived before the migration lands
- **WHEN** `add-flutter-app-foundation` is archived into `specs/`.
- **THEN** its `flutter-*` capabilities land under the current nearest root
  (`backend/openspec/specs/`) and are moved to `/openspec/specs/` en bloc
  by the migration change, alongside every other backend capability.
