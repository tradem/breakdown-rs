// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../../core/result.dart';
import 'base_repository.dart';

/// Read/write repository for the `Season` aggregate boundary.
///
/// Wraps the generated [BreakdownApi] calls and returns [Result] so the error
/// branch is always an explicit value. Never throws, never exposes raw HTTP
/// types. This is the canonical aggregate repository — the pattern it
/// establishes (generated call → [BaseRepository.run] → [Result]) is reused by
/// every other `data/` repository.
class SeasonRepository extends BaseRepository {
  const SeasonRepository(super.api);

  /// Creates a new season.
  Future<Result<IdVersionResponse>> create(CreateSeasonRequest request) =>
      run(() => api.getHandlersApi().createSeason(createSeasonRequest: request));

  /// Fetches a single season by id.
  Future<Result<SeasonView>> get(String id) =>
      run(() => api.getHandlersApi().getSeason(id: id));

  /// Renames an existing season.
  Future<Result<int>> rename(String id, RenameSeasonRequest request) =>
      run(() => api.getHandlersApi()
          .renameSeason(id: id, renameSeasonRequest: request));
}
