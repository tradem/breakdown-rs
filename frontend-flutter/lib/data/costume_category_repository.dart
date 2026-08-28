// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../../core/result.dart';
import 'base_repository.dart';

/// Read/write repository for the `CostumeCategory` aggregate boundary (scoped
/// to a Season).
class CostumeCategoryRepository extends BaseRepository {
  const CostumeCategoryRepository(super.api);

  Future<Result<IdVersionResponse>> create(
    String seasonId,
    CreateCostumeCategoryRequest request,
  ) =>
      run(() => api.getHandlersApi().createCostumeCategory(
            seasonId: seasonId,
            createCostumeCategoryRequest: request,
          ));

  Future<Result<int>> update(
    String id,
    UpdateCostumeCategoryRequest request,
  ) =>
      run(() => api.getHandlersApi().updateCostumeCategory(
            id: id,
            updateCostumeCategoryRequest: request,
          ));

  Future<Result<int>> archive(String id, VersionRequest version) =>
      run(() => api.getHandlersApi()
          .archiveCostumeCategory(id: id, versionRequest: version));
}
