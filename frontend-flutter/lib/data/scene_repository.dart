// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Read/write repository for the `Scene` aggregate boundary (scoped to an
/// Episode).
class SceneRepository extends BaseRepository {
  const SceneRepository(super.api);

  Future<Result<IdVersionResponse>> create(CreateSceneRequest request) =>
      run(() => api.getHandlersApi().createScene(createSceneRequest: request));

  Future<Result<SceneView>> get(String id) =>
      run(() => api.getHandlersApi().getScene(id: id));

  Future<Result<int>> updateDetails(
    String id,
    UpdateSceneDetailsRequest request,
  ) => run(
    () => api.getHandlersApi().updateSceneDetails(
      id: id,
      updateSceneDetailsRequest: request,
    ),
  );

  Future<Result<int>> assignCharacter(
    String id,
    AssignCharacterRequest request,
  ) => run(
    () => api.getHandlersApi().assignSceneCharacter(
      id: id,
      assignCharacterRequest: request,
    ),
  );

  Future<Result<int>> removeCharacter(String id, String characterId) => run(
    () => api.getHandlersApi().removeSceneCharacter(
      id: id,
      characterId: characterId,
    ),
  );

  Future<Result<int>> scheduleOnShootingDay(
    String id,
    ScheduleSceneRequest request,
  ) => run(
    () => api.getHandlersApi().scheduleSceneOnShootingDay(
      id: id,
      scheduleSceneRequest: request,
    ),
  );

  Future<Result<int>> unscheduleFromShootingDay(
    String id,
    String shootingDayId,
  ) => run(
    () => api.getHandlersApi().unscheduleSceneFromShootingDay(
      id: id,
      shootingDayId: shootingDayId,
    ),
  );
}
