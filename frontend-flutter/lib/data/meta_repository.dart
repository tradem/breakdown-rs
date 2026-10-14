// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Read-only repository for the meta surface (issue #656): compile-time
/// backend workspace crate versions shown on the About screen.
///
/// Wraps the generated [BreakdownApi] `GET /v1/meta/versions` call and never
/// throws — the [Result] discipline of [BaseRepository]. No caching: the
/// route is a cheap authenticated constant, and the About screen renders a
/// graceful error state when the fetch fails (stale token, network).
class MetaRepository extends BaseRepository {
  const MetaRepository(super.api);

  /// `GET /v1/meta/versions` — the served workspace crates' versions.
  Future<Result<MetaVersionsResponse>> versions() =>
      run(() => api.getHandlersApi().getMetaVersions());
}
