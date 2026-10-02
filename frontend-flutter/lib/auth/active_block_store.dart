// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (opencode-go)

import 'dart:async' show Completer;
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// Secure persistence for the per-season active-block scope (issue #382).
///
/// The in-memory sticky scope (`ActiveBlock`) resets on every cold start, so
/// returning users on multi-block seasons re-face the remembered picker.
/// This store keeps a `Map<seasonId, PersistedBlockScope>` as a JSON object
/// under [key] in secure storage — the same seam as `SecureTokenStore` /
/// `ApiBaseOverrideStore`, so the scope stays identity-scoped and dies with
/// sign-out (no cross-identity leak, no plaintext-preference spread).
/// Block ids are not secrets; secure storage is chosen for the
/// session-lifecycle coupling, not for confidentiality.
///
/// **Document shape v2 (issue #548):** values are objects
/// `{"blockId": …, "number": …}` so the scope chip can render a visible
/// label. The read path accepts BOTH shapes — the pre-#548 bare-string
/// values (`{"s1": "b1"}`) load as label-less scopes ("label unknown"
/// degradation, never a failure) and the next write upgrades the document.
///
/// All methods are [Result]-typed; storage failures are values, never
/// throws (AGENTS.md §5). A corrupt payload self-heals to `{}` (best-effort
/// wipe) rather than failing resolution — persistence problems must never
/// break the re-resolution path.
///
/// Mutations ([saveScope], [removeScope], [removeScopeIfMatch], [clear]) run
/// serialized through [_mutex] in invocation order (CodeRabbit review on PR
/// #383): the single-key read-modify-write would otherwise lose updates when
/// two rapid `set` calls interleave, let a stale eviction land after a fresh
/// pick, or let an in-flight write complete after `SessionReset` clears the
/// map and resurrect a previous identity's scope. Reads stay unfenced — a
/// torn read is impossible on one key and either side of a write is a valid
/// map.
/// One persisted scope value: the block id plus (since #548) the picked
/// block's locale-neutral number for the scope chip's visible label.
/// `blockNumber` is `null` for values read from the pre-#548 bare-string
/// document shape — the "label unknown" degradation.
class PersistedBlockScope {
  const PersistedBlockScope({required this.blockId, this.blockNumber});

  static PersistedBlockScope? fromJson(Object? json) => switch (json) {
    // Legacy shape (pre-#548): the value IS the block id.
    final String id => PersistedBlockScope(blockId: id),
    final Map<Object?, Object?> map when map['blockId'] is String =>
      PersistedBlockScope(
        blockId: map['blockId']! as String,
        blockNumber: switch (map['number']) {
          final int n => n,
          _ => null,
        },
      ),
    // Unknown/invalid value shapes degrade to "label unknown" — never a
    // failure (the entry names no block id, so it is dropped; the gate
    // re-resolves).
    _ => null,
  };

  final String blockId;
  final int? blockNumber;

  @override
  bool operator ==(Object other) =>
      other is PersistedBlockScope &&
      other.blockId == blockId &&
      other.blockNumber == blockNumber;

  @override
  int get hashCode => Object.hash(blockId, blockNumber);

  Object? toJson() => blockNumber == null
      ? blockId
      : {'blockId': blockId, 'number': blockNumber};
}

class ActiveBlockStore {
  ActiveBlockStore(this._storage);

  /// Production store backed by the platform secure enclave.
  factory ActiveBlockStore.secure() =>
      ActiveBlockStore(const FlutterSecureStorage());

  /// Secure-storage key for the per-season scope map.
  static const String key = 'breakdown.active_block_scopes';

  final FlutterSecureStorage _storage;
  final _WriteMutex _mutex = _WriteMutex();

  /// Reads the persisted scopes, or `{}` when none is stored. Accepts both
  /// document shapes (see [PersistedBlockScope]); entries whose value shape
  /// is neither a bare string nor a v2 object are dropped.
  Future<Result<Map<String, PersistedBlockScope>>> readScopes() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) {
        return Right(<String, PersistedBlockScope>{});
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _heal();
        return Right(<String, PersistedBlockScope>{});
      }
      final scopes = <String, PersistedBlockScope>{};
      for (final entry in decoded.entries) {
        final scope = PersistedBlockScope.fromJson(entry.value);
        if (scope case final scope?) scopes[entry.key] = scope;
      }
      return Right(scopes);
    } catch (e) {
      if (e is FormatException) {
        await _heal();
        return Right(<String, PersistedBlockScope>{});
      }
      return Left(
        ProblemError(code: 'active_block.scopes_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists the scope for [seasonId] (insert or overwrite); [blockNumber]
  /// rides along for the scope chip's visible label (issue #548).
  Future<Result<void>> saveScope({
    required String seasonId,
    required String blockId,
    int? blockNumber,
  }) => _mutex.run(() async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    scopes[seasonId] = PersistedBlockScope(
      blockId: blockId,
      blockNumber: blockNumber,
    );
    return _writeAll(scopes, 'active_block.scopes_write_failed');
  });

  /// Evicts the persisted scope for [seasonId] (stale-block cleanup).
  /// A no-op when nothing is stored for the season.
  Future<Result<void>> removeScope(String seasonId) => _mutex.run(() async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    if (!scopes.containsKey(seasonId)) return const Right(null);
    scopes.remove(seasonId);
    return _writeAll(scopes, 'active_block.scopes_write_failed');
  });

  /// Evicts the persisted scope for [seasonId] only when it still equals
  /// [blockId] (stale-block cleanup, issue #382): a fresh pick that landed
  /// after the stale read is never deleted, regardless of scheduling order.
  Future<Result<void>> removeScopeIfMatch({
    required String seasonId,
    required String blockId,
  }) => _mutex.run(() async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    if (scopes[seasonId]?.blockId != blockId) return const Right(null);
    scopes.remove(seasonId);
    return _writeAll(scopes, 'active_block.scopes_write_failed');
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
        ProblemError(code: 'active_block.scopes_clear_failed', detail: '$e'),
      );
    }
  });

  Future<Result<void>> _writeAll(
    Map<String, PersistedBlockScope> scopes,
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

/// The [ActiveBlockStore] seam (manual provider — no codegen — so tests can
/// override with an in-memory double via `overrideWithValue`).

/// FIFO async mutex serializing the store's mutations (same pattern as the
/// session-state mutex in `auth_providers.dart`): every guarded body runs to
/// completion before the next invocation's body starts, so overlapping
/// read-modify-write cycles execute in invocation order instead of
/// interleaving. Bodies never throw (every store method returns a `Result`),
/// so the chain is deadlock-free by construction and an unawaited caller can
/// never produce an unhandled async error from the coordinator itself.
class _WriteMutex {
  /// Pending tails, newest last. A list (rather than a single field) so
  /// chaining is a `void` add-statement — a bare `Future`-typed assignment
  /// would trip the discard_result rule (same pattern as the session-state
  /// mutex in `auth_providers.dart`).
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

final activeBlockStoreProvider = Provider<ActiveBlockStore>(
  (ref) => ActiveBlockStore.secure(),
  name: 'activeBlockStore',
);

/// The persisted per-season scopes, loaded once and kept alive.
///
/// The single async seam `blockScopeResolution` watches: while this is
/// loading the gate withholds content (no picker flash). A store failure
/// degrades to `{}` ("nothing remembered") right here, so the gate falls
/// through to the existing re-resolution path — never a hard failure.
/// Failing the provider instead would arm the Riverpod auto-retry timers,
/// which never settle under `pumpAndSettle` in widget tests and buy nothing
/// in production (the next cold start retries naturally).
/// Refresh it (invalidate) after every settled store write so watchers
/// converge; the sticky-scope hit short-circuits the gate meanwhile, so the
/// settle window is unobservable.
final activeBlockPersistedProvider =
    FutureProvider<Map<String, PersistedBlockScope>>((ref) async {
      final res = await ref.watch(activeBlockStoreProvider).readScopes();
      return res.getRight().toNullable() ?? <String, PersistedBlockScope>{};
    }, name: 'activeBlockPersisted');
