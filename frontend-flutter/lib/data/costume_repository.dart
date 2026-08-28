// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_value/json_object.dart';

import '../../core/result.dart';
import 'base_repository.dart';

class CostumeRepository extends BaseRepository {
  const CostumeRepository(super.api);

  Future<Result<IdVersionResponse>> create(JsonObject body) =>
      run(() => api.getHandlersApi().createCostume(body: body));

  Future<Result<CostumeView>> get(String id) =>
      run(() => api.getHandlersApi().getCostume(id: id));

  Future<Result<int>> addDetail(String id, AddCostumeDetailRequest request) =>
      run(() => api.getHandlersApi()
          .addCostumeDetail(id: id, addCostumeDetailRequest: request));

  Future<Result<int>> updateNotes(
    String id,
    UpdateCostumeNotesRequest request,
  ) =>
      run<int>(() => api.getHandlersApi()
          .updateCostumeNotes(id: id, updateCostumeNotesRequest: request));

  Future<Result<int>> updateMeasurements(
    String id,
    UpdateMeasurementsRequest request,
  ) =>
      run(() => api.getHandlersApi()
          .updateMeasurements(id: id, updateMeasurementsRequest: request));

  Future<Result<int>> assign(String id, AssignCostumeRequest request) =>
      run(() => api.getHandlersApi().assignCostume(id: id, assignCostumeRequest: request));

  Future<Result<int>> unassign(
    String id,
    UpdateCostumeNotesRequest request,
  ) =>
      run(() => api.getHandlersApi()
          .unassignCostume(id: id, updateCostumeNotesRequest: request));
}
