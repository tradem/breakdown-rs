// SPDX-License-Identifier: AGPL-3.0
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';

import '../core/result.dart';
import 'base_repository.dart';

/// Read-only repository for the meta surface (issue #656): compile-time
/// backend workspace crate versions shown on the About screen; plus the
/// credits surface (issue #655): deduped LLM co-authors + human contributors
/// for the credits screen word cloud.
///
/// Wraps the generated [BreakdownApi] `GET /v1/meta/*` calls and never
/// throws — the [Result] discipline of [BaseRepository]. No caching: the
/// routes are cheap authenticated constants, and the screens render a
/// graceful error state when the fetch fails (stale token, network).
class MetaRepository extends BaseRepository {
  const MetaRepository(super.api);

  /// `GET /v1/meta/versions` — the served workspace crates' versions.
  Future<Result<MetaVersionsResponse>> versions() =>
      run(() => api.getHandlersApi().getMetaVersions());

  /// `GET /v1/meta/credits` — deduped LLM co-authors + human contributors
  /// (issue #655). The client renders both kinds from this one payload:
  /// `provider != null` marks an LLM co-author, humans carry their roles.
  Future<Result<MetaCreditsResponse>> credits() =>
      run(() => api.getHandlersApi().getMetaCredits());
}
