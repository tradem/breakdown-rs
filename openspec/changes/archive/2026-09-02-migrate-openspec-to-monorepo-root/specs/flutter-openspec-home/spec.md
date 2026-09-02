<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.2 (neuralwatt) -->

## ADDED Requirements

### Requirement: Canonical OpenSpec Root at Monorepo Root
The canonical OpenSpec root SHALL be `/openspec/` at the repository root.
All capabilities — backend, frontend-flutter, future frontends — live as
siblings under `openspec/specs/<capability>/`. Backend capabilities keep
existing names; Flutter capabilities carry the `flutter-*` prefix.

#### Scenario: A new change is authored after migration
- **WHEN** a contributor runs `openspec new change` from anywhere in the
  repo.
- **THEN** the working root resolves to `breakdown-rs/openspec/` and the
  capability lands under `openspec/specs/<name>/`.

#### Scenario: All existing changes still validate post-move
- **WHEN** `git mv backend/openspec openspec` completes.
- **THEN** `openspec doctor` reports healthy and every archived + active
  change still validates against the new root.
