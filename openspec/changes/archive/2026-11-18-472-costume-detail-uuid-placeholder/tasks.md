<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4-flash (neuralwatt) -->

# Tasks — Costume AddDetail client-side UUIDv7 wire id (issue #472)

## Done

- **`lib/core/uuid.dart`** (new): `generateUuidV7()` wrapping `Uuid().v7()`;
  sole reference to the `uuid` package in the app.
- **`lib/features/costumes/costumes_controller.dart`** (`addDetail`): wire
  `detail.id` now `generateUuidV7()`; overlay keeps its separate
  `pending-detail-<version>` transient placeholder (decoupled ids).
- **`frontend-flutter/pubspec.yaml`**: `uuid: ^4.6.0` added (direct dep,
  lockfile updated; uses the v7 generator shipped since uuid 4.4.0); version
  bumped `0.3.0-alpha.13+22` → `0.3.0-alpha.14+23` (per-PR bump convention,
  ADR-033 / #362).
- **Tier-1 unit tests** (`test/unit/uuid_test.dart`): 100 unique RFC-9562
  UUIDv7 strings, never `'pending'`, time-ordered prefix.
- **Tier-2 regression tests** (`test/features/costumes/costumes_screen_test.dart`):
  fake repo captures `lastAddDetailRequest`; wire payload id is a parseable
  UUIDv7 (not `'pending'`) while the overlay still uses `pending-detail-2`;
  422 `domain.validation` surfaces the wire `code` via `costumeErrorCopy`.
- **Sibling audit**: only `addDetail` built the placeholder into a wire
  payload; no other sibling write affected.

## Verified

- `dart format --set-exit-if-changed .`: clean
- `flutter analyze`: clean
- `flutter test`: 989 passed
