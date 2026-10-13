// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'dart:async' show Completer;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// Secure persistence for the per-season active-episode scope (issue #624).
///
/// The in-memory sticky scope (`ActiveEpisode`) resets on every cold start.
/// This store keeps a `Map<seasonId, PersistedEpisodeScope>` as a JSON object
/// under [key] in secure storage — the same seam as `ActiveBlockStore`, so
/// the scope stays identity-scoped and dies with sign-out (no cross-identity
/// leak, no plaintext-preference spread). Episode ids are not secrets; secure
/// storage is chosen for the session-lifecycle coupling, not for
/// confidentiality.
///
/// **Document shape v1:** values are objects
/// `{"blockId": …, "episodeId": …, "number": …, "name": …?}`. A value whose
/// shape is unknown is dropped (never a failure); a corrupt payload self-heals
/// to `{}` (best-effort wipe) rather than failing resolution.
///
/// All methods are [Result]-typed; storage failures are values, never throws
/// (AGENTS.md §5). Mutations run serialized through [_WriteMutex] in
/// invocation order (same discipline as `ActiveBlockStore`), so overlapping
/// read-modify-write cycles execute in invocation order instead of
/// interleaving.
class PersistedEpisodeScope {
  const PersistedEpisodeScope({
    required this.blockId,
    required this.episodeId,
    required this.episodeNumber,
    this.episodeName,
  });

  static PersistedEpisodeScope? fromJson(Object? json) => switch (json) {
    final Map<Object?, Object?> map
        when map['blockId'] is String &&
            map['episodeId'] is String &&
            map['number'] is int =>
      PersistedEpisodeScope(
        blockId: map['blockId']! as String,
        episodeId: map['episodeId']! as String,
        episodeNumber: map['number']! as int,
        episodeName: switch (map['name']) {
          final String name => name,
          _ => null,
        },
      ),
    // Unknown/invalid value shapes are dropped — never a failure (the entry
    // names no episode, so the chip stays hidden and the gate re-resolves).
    _ => null,
  };

  final String blockId;
  final String episodeId;
  final int episodeNumber;
  final String? episodeName;

  @override
  bool operator ==(Object other) =>
      other is PersistedEpisodeScope &&
      other.blockId == blockId &&
      other.episodeId == episodeId &&
      other.episodeNumber == episodeNumber &&
      other.episodeName == episodeName;

  @override
  int get hashCode =>
      Object.hash(blockId, episodeId, episodeNumber, episodeName);

  Object? toJson() => {
    'blockId': blockId,
    'episodeId': episodeId,
    'number': episodeNumber,
    if (episodeName != null) 'name': episodeName,
  };
}

class ActiveEpisodeStore {
  ActiveEpisodeStore(this._storage);

  /// Production store backed by the platform secure enclave.
  factory ActiveEpisodeStore.secure() =>
      ActiveEpisodeStore(const FlutterSecureStorage());

  /// Secure-storage key for the per-season episode scope map.
  static const String key = 'breakdown.active_episode_scopes';

  final FlutterSecureStorage _storage;
  final _WriteMutex _mutex = _WriteMutex();

  /// Reads the persisted scopes, or `{}` when none is stored. Entries whose
  /// value shape is not a v1 object are dropped.
  Future<Result<Map<String, PersistedEpisodeScope>>> readScopes() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) {
        return Right(<String, PersistedEpisodeScope>{});
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _heal();
        return Right(<String, PersistedEpisodeScope>{});
      }
      final scopes = <String, PersistedEpisodeScope>{};
      for (final entry in decoded.entries) {
        final scope = PersistedEpisodeScope.fromJson(entry.value);
        if (scope case final scope?) scopes[entry.key] = scope;
      }
      return Right(scopes);
    } catch (e) {
      if (e is FormatException) {
        await _heal();
        return Right(<String, PersistedEpisodeScope>{});
      }
      return Left(
        ProblemError(code: 'active_episode.scopes_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists the scope for [seasonId] (insert or overwrite).
  Future<Result<void>> saveScope({
    required String seasonId,
    required String blockId,
    required String episodeId,
    required int episodeNumber,
    String? episodeName,
  }) => _mutex.run(() async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    scopes[seasonId] = PersistedEpisodeScope(
      blockId: blockId,
      episodeId: episodeId,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
    );
    return _writeAll(scopes, 'active_episode.scopes_write_failed');
  });

  /// Evicts the persisted scope for [seasonId] (stale-episode cleanup).
  /// A no-op when nothing is stored for the season.
  Future<Result<void>> removeScope(String seasonId) => _mutex.run(() async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    if (!scopes.containsKey(seasonId)) return const Right(null);
    scopes.remove(seasonId);
    return _writeAll(scopes, 'active_episode.scopes_write_failed');
  });

  /// Removes every persisted scope (sign-out / backend switch). Awaited by
  /// `SessionReset`, so every previously scheduled write settles first and
  /// nothing in flight can resurrect a cleared identity's scope afterwards.
  Future<Result<void>> clear() => _mutex.run(() async {
    try {
      await _storage.delete(key: key);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'active_episode.scopes_clear_failed', detail: '$e'),
      );
    }
  });

  Future<Result<void>> _writeAll(
    Map<String, PersistedEpisodeScope> scopes,
    String code,
  ) async {
    try {
      await _storage.write(key: key, value: jsonEncode(scopes));
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(ProblemError(code: code, detail: '$e'));
    }
  }

  /// Best-effort wipe of a corrupt payload; failures are ignored — the
  /// caller already falls back to `{}` and the next write overwrites it.
  Future<void> _heal() async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Intentionally ignored (see above).
    }
  }
}

/// FIFO async mutex serializing the store's mutations (same pattern as
/// `ActiveBlockStore`): every guarded body runs to completion before the next
/// invocation's body starts, so overlapping read-modify-write cycles execute
/// in invocation order instead of interleaving. Bodies never throw (every
/// store method returns a `Result`), so the chain is deadlock-free by
/// construction.
class _WriteMutex {
  /// Pending tails, newest last. A list (rather than a single field) so
  /// chaining is a `void` add-statement — a bare `Future`-typed assignment
  /// would trip the discard_result rule.
  final List<Future<void>> _tails = [Future.value()];

  Future<T> run<T>(Future<T> Function() body) async {
    final previous = _tails.last;
    final gate = Completer<void>();
    _tails.add(gate.future);
    await previous;
    try {
      return await body();
    } finally {
      _tails.remove(previous);
      gate.complete();
    }
  }
}

final activeEpisodeStoreProvider = Provider<ActiveEpisodeStore>(
  (ref) => ActiveEpisodeStore.secure(),
  name: 'activeEpisodeStore',
);

/// The persisted per-season episode scopes, loaded once and kept alive.
///
/// A store failure degrades to `{}` ("nothing remembered") right here, so the
/// chip simply hides — never a hard failure. Failing the provider instead
/// would arm the Riverpod auto-retry timers, which never settle under
/// `pumpAndSettle` in widget tests and buy nothing in production. Refresh it
/// (invalidate) after every settled store write so watchers converge.
final activeEpisodePersistedProvider =
    FutureProvider<Map<String, PersistedEpisodeScope>>((ref) async {
      final res = await ref.watch(activeEpisodeStoreProvider).readScopes();
      return res.getRight().toNullable() ?? <String, PersistedEpisodeScope>{};
    }, name: 'activeEpisodePersisted');
