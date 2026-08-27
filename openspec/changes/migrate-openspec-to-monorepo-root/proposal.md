<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

# Proposal: Migrate OpenSpec Root to Monorepo Root

## Why
Foundation `flutter-openspec-home` (Q3→c) decides the canonical OpenSpec
root is `/openspec/` at the monorepo root, so backend and Flutter (and
future frontend) capabilities are siblings. The mechanical move of all
existing `backend/openspec/**` content is deferred to this change so the
(large) rename diff stays reviewable on its own.

## What changes
- Move `backend/openspec/**` → `/openspec/**` (changes, specs, config,
  archive).
- Update OpenSpec tooling resolution (`nearest` root becomes the repo root).
- Update any CI / docs / scripts that reference `backend/openspec` paths.
- Backend capabilities keep their existing names; Flutter capabilities
  carry the `flutter-*` prefix (no rename).

## Dependencies
- **Depends on:** none (mechanical move; can land before or after the
  Flutter follow-ups).
- **Coordinate with:** the foundation change's archive path — foundation's
  artifacts move en bloc here.

## Non-goals
- No capability renames.
- No spec content changes (move-only).
- No new store registration (single nearest root suffices).
