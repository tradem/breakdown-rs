// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:drift/drift.dart';

/// Small client-local key-value table for shell state that is not a
/// projection mirror — currently the persisted **active season** reference
/// (`redesign-app-shell-navigation` 2.2, design D5: active season =
/// last-opened season, restored on cold start).
///
/// Values are opaque strings; the referenced projection row must be
/// re-validated against the TTL-stamped read cache on every boot (the
/// store persists only the *reference*, never a stale copy of the DTO —
/// "TTL-compliant" by construction: a persisted id whose cached season row
/// has expired or disappeared resolves to `null`, never to a stale
/// object). The `cachedAt` column records the write time for diagnostics.
class ShellStateRows extends Table {
  /// Scope key, e.g. `active_season_id`.
  TextColumn get key => text()();

  /// The persisted opaque value.
  TextColumn get value => text()();

  /// Client-only cache-write time (D2 discipline; diagnostics only).
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
