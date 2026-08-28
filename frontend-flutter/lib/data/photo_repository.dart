// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

import '../../core/result.dart';
import 'base_repository.dart';

/// Read/write repository for the `Costume | Continuity` photo bounded context
/// (capture/upload, byte fetch, delete — all AUTHZ-GATE'd server-side).
class PhotoRepository extends BaseRepository {
  const PhotoRepository(super.api);

  Future<Result<PhotoView>> upload(String costumeId, String body) =>
      run(() => api.getHandlersApi().uploadCostumePhoto(costumeId: costumeId, body: body));

  /// Fetches the raw bytes of a photo variant. The bytes live in the response
  /// body; the generated wrapper returns `Response<void>` because the OpenAPI
  /// schema models the variant as an opaque stream.
  Future<Result<void>> getBytes(
    String costumeId,
    String photoId,
    String variant,
  ) =>
      run(() => api.getHandlersApi()
          .getCostumePhotoBytes(costumeId: costumeId, photoId: photoId, variant: variant));

  Future<Result<void>> delete(String costumeId, String photoId) =>
      run(() => api.getHandlersApi()
          .deleteCostumePhoto(costumeId: costumeId, photoId: photoId));
}
