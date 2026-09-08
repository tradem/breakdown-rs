// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_block.g.dart';

/// The client-side active-block scope (issue #378).
///
/// The backend `authorize_middleware` classifies episodes, scenes, shooting
/// days, scene shoots, costumes and characters as `BlockMember` and rejects
/// a missing `X-Active-Block` header with 400. This provider tracks the
/// block the user is acting in; [ActiveBlockInterceptor] (see
/// `lib/src/network/active_block_interceptor.dart`) attaches it to every
/// API request. The server stays authoritative — a scope the caller is not
/// a member of surfaces as a 403 through the keyed-on-`code` error path.
///
/// Both ids are tracked (not just the block): season-direct entries
/// (`CostumesScreen`, `CharactersScreen`) reuse the sticky scope only when
/// its `seasonId` matches, so browsing season B never silently sends season
/// A's block. Set implicitly from the DTO the user acted on (CQRS boundary
/// — never a second projection lookup); cleared on sign-out so a new
/// session never inherits the previous user's scope.
class ActiveScope {
  const ActiveScope({required this.seasonId, required this.blockId});

  final String seasonId;
  final String blockId;

  @override
  bool operator ==(Object other) =>
      other is ActiveScope &&
      other.seasonId == seasonId &&
      other.blockId == blockId;

  @override
  int get hashCode => Object.hash(seasonId, blockId);

  @override
  String toString() => 'ActiveScope(seasonId: $seasonId, blockId: $blockId)';
}

/// The sticky active-block scope. `null` means no scope is set (fresh boot
/// or signed out) — requests go out headerless, which is valid for the
/// `Authenticated`-only routes (seasons, `/blocks`, photos, reports).
///
/// `keepAlive: true` so the scope survives screen pops; consumers set it on
/// navigation into block context and clear it on sign-out.
@Riverpod(keepAlive: true)
class ActiveBlock extends _$ActiveBlock {
  @override
  ActiveScope? build() => null;

  /// Sets the scope from the block DTO the user acted on.
  void set({required String seasonId, required String blockId}) {
    state = ActiveScope(seasonId: seasonId, blockId: blockId);
  }

  /// Clears the scope (sign-out / session teardown).
  void clear() {
    state = null;
  }
}
