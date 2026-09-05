// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// Secure persistence for the dev-flavor runtime backend-URI override
/// (spec `flutter-app-dialogs`, task 6.2).
///
/// The override lives in secure storage under [key] — never in plaintext
/// preferences (AGENTS.md §5). It is flavor-guarded at every application
/// point: applied only when `config.flavor == Flavor.dev` (see
/// `applyApiBaseOverride`), ignored AND cleared on `prod` boot. All methods
/// are [Result]-typed; storage failures are values, never throws.
class ApiBaseOverrideStore {
  const ApiBaseOverrideStore(this._storage);

  /// Production store backed by the platform secure enclave.
  factory ApiBaseOverrideStore.secure() =>
      const ApiBaseOverrideStore(FlutterSecureStorage());

  /// Secure-storage key for the override (spec text: `api_base_override`).
  static const String key = 'api_base_override';

  final FlutterSecureStorage _storage;

  /// Reads the persisted override, or `null` when none is stored.
  Future<Result<String?>> read() async {
    try {
      return Right(await _storage.read(key: key));
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.override_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists [base] (already validated by [validateApiBase] at the dialog).
  Future<Result<void>> write(String base) async {
    try {
      await _storage.write(key: key, value: base);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.override_write_failed', detail: '$e'),
      );
    }
  }

  /// Removes the override (reset-to-default, `prod` boot cleanup).
  Future<Result<void>> clear() async {
    try {
      await _storage.delete(key: key);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.override_clear_failed', detail: '$e'),
      );
    }
  }
}

/// Runtime backend-base override (task 6.3): `null` means "no runtime
/// change since boot — use `AppConfig.apiBase`" (the persisted override, if
/// any, is already merged into the config by `bootstrap()` — task 6.1).
/// Setting it rebuilds `apiDioProvider` (same pinned `SecurityContext`) and
/// every dependent client/repository. KeepAlive by construction — the
/// override outlives any screen.
class RuntimeApiBase extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? base) => state = base;
}

final runtimeApiBaseProvider = NotifierProvider<RuntimeApiBase, String?>(
  RuntimeApiBase.new,
);
