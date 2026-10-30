// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/active_block.dart';
import '../../../data/cache/seasons_cache_providers.dart';
import '../../blocks/active_block_gate.dart';

part 'import_target.g.dart';

/// The season the AI import screen acts in (issue #771).
///
/// The entry point decides it: the season-setup wizard's completion CTA passes
/// the created season explicitly, every other entry has no season of its own and
/// inherits the ambient scope's season (the block pill's minimum requirement).
/// `null` means "no season context at all" — the import then has NO resolvable
/// target and must not dispatch, which is the honest state the screen renders
/// instead of sending an upload blindly.
///
/// This is the ONE seam: the target line, the picker's candidates, the submit
/// affordance and the dispatch guard all read this season, so the target the
/// user is shown and the season the request declares cannot drift apart.
@riverpod
String? aiImportSeasonContext(Ref ref, String? explicitSeasonId) =>
    explicitSeasonId ?? ref.watch(activeBlockProvider)?.seasonId;

/// The season NUMBER of the import target, resolved CACHE-ONLY.
///
/// A label that is not cached yields `null`, and the target line renders its
/// explicit "season unknown" narrative rather than triggering a network read on
/// the submit path (same discipline as the scope chip's cache-only number
/// backfill, issue #548). The block number is never resolved this way: it rides
/// on the acted-on `BlockView` / the resolved scope.
@riverpod
Future<String?> aiImportSeasonNumber(Ref ref, String seasonId) async {
  final res = await ref.watch(seasonRepositoryProvider).readCached();
  return res.match((_) => null, (rows) {
    for (final season in rows) {
      if (season.id == seasonId) return '${season.number}';
    }
    return null;
  });
}

/// The block the import will actually write into, as resolved for the screen.
///
/// `null` while unresolved (loading, picker pending, no block, fetch failure):
/// the submit affordance stays disabled, so a request can never carry a block
/// the user was not shown.
ActiveScope? aiImportResolvedScope(
  AsyncValue<BlockScopeResolution>? resolution,
) => resolution?.value?.scope;
