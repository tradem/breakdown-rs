// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark (opencode-go)

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
/// This store keeps a `Map<seasonId, blockId>` as a JSON object under [key]
/// in secure storage — the same seam as `SecureTokenStore` /
/// `ApiBaseOverrideStore`, so the scope stays identity-scoped and dies with
/// sign-out (no cross-identity leak, no plaintext-preference spread).
/// Block ids are not secrets; secure storage is chosen for the
/// session-lifecycle coupling, not for confidentiality.
///
/// All methods are [Result]-typed; storage failures are values, never
/// throws (AGENTS.md §5). A corrupt payload self-heals to `{}` (best-effort
/// wipe) rather than failing resolution — persistence problems must never
/// break the re-resolution path.
class ActiveBlockStore {
  const ActiveBlockStore(this._storage);

  /// Production store backed by the platform secure enclave.
  factory ActiveBlockStore.secure() =>
      const ActiveBlockStore(FlutterSecureStorage());

  /// Secure-storage key for the per-season scope map.
  static const String key = 'breakdown.active_block_scopes';

  final FlutterSecureStorage _storage;

  /// Reads the persisted scopes, or `{}` when none is stored.
  Future<Result<Map<String, String>>> readScopes() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) return Right(<String, String>{});
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _heal();
        return Right(<String, String>{});
      }
      final scopes = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.value is String) scopes[entry.key] = entry.value as String;
      }
      return Right(scopes);
    } catch (e) {
      if (e is FormatException) {
        await _heal();
        return Right(<String, String>{});
      }
      return Left(
        ProblemError(code: 'active_block.scopes_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists the scope for [seasonId] (insert or overwrite).
  Future<Result<void>> saveScope({
    required String seasonId,
    required String blockId,
  }) async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    scopes[seasonId] = blockId;
    return _writeAll(scopes, 'active_block.scopes_write_failed');
  }

  /// Evicts the persisted scope for [seasonId] (stale-block cleanup).
  /// A no-op when nothing is stored for the season.
  Future<Result<void>> removeScope(String seasonId) async {
    final current = await readScopes();
    final scopes = current.getRight().toNullable();
    if (scopes == null) {
      return Left(current.getLeft().toNullable()!);
    }
    if (!scopes.containsKey(seasonId)) return const Right(null);
    scopes.remove(seasonId);
    return _writeAll(scopes, 'active_block.scopes_write_failed');
  }

  /// Removes every persisted scope (sign-out / backend switch).
  Future<Result<void>> clear() async {
    try {
      await _storage.delete(key: key);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'active_block.scopes_clear_failed', detail: '$e'),
      );
    }
  }

  Future<Result<void>> _writeAll(
    Map<String, String> scopes,
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
final activeBlockPersistedProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final res = await ref.watch(activeBlockStoreProvider).readScopes();
  return res.getRight().toNullable() ?? <String, String>{};
}, name: 'activeBlockPersisted');
