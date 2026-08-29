// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Read/write repository for the `Character` aggregate boundary (scoped to a
/// Season).
class CharacterRepository extends BaseRepository {
  const CharacterRepository(super.api);

  Future<Result<IdVersionResponse>> create(CreateCharacterRequest request) =>
      run(
        () => api.getHandlersApi().createCharacter(
          createCharacterRequest: request,
        ),
      );

  Future<Result<CharacterView>> get(String id) =>
      run(() => api.getHandlersApi().getCharacter(id: id));
}
