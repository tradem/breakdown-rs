// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Read/write repository for the `ShootingDay` aggregate boundary.
class ShootingDayRepository extends BaseRepository {
  const ShootingDayRepository(super.api);

  Future<Result<IdVersionResponse>> create(
    String episodeId,
    CreateShootingDayRequest request,
  ) => run(
    () => api.getHandlersApi().createShootingDay(
      episodeId: episodeId,
      createShootingDayRequest: request,
    ),
  );

  Future<Result<ShootingDayView>> get(String id) =>
      run(() => api.getHandlersApi().getShootingDay(id: id));

  Future<Result<int>> update(String id, UpdateShootingDayRequest request) =>
      run(
        () => api.getHandlersApi().updateShootingDay(
          id: id,
          updateShootingDayRequest: request,
        ),
      );

  Future<Result<int>> archive(String id, VersionRequest version) => run(
    () => api.getHandlersApi().archiveShootingDay(
      id: id,
      versionRequest: version,
    ),
  );
}
