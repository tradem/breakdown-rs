// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/cache/seasons_cache_providers.dart';
import '../../data/meta_repository.dart';

part 'app_info_controller.g.dart';

/// Meta repository for the About screen (issue #656): serves
/// `GET /v1/meta/versions` through the generated client. Tests override the
/// [metaVersionsProvider] fetch, so this wiring stays production-only.
@riverpod
MetaRepository metaRepository(Ref ref) =>
    MetaRepository(ref.watch(apiClientProvider));

/// Backend workspace crate versions for the About screen.
///
/// The repository never throws (Result discipline); this feature-layer
/// adapter converts the `Left(ProblemError)` into the provider's async error
/// so `ref.watch` surfaces a clean `AsyncValue.error` — the screen degrades
/// gracefully, it never crashes on a failed fetch.
@riverpod
Future<MetaVersionsResponse> metaVersions(Ref ref) async {
  final result = await ref.watch(metaRepositoryProvider).versions();
  return result.match((err) => throw err, (v) => v);
}
