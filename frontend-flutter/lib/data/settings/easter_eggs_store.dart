// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// On-device persistence for the global Easter-eggs toggle (issue #516,
/// capability `flutter-easter-eggs`).
///
/// The flag is **not a secret** (no token, no credential), so it lives in
/// plain `shared_preferences` — deliberately NOT in
/// `flutter_secure_storage`, which would misuse the secure enclave
/// (Decision D1 of `add-karl-klammer-easter-egg`; contrast
/// [ApiBaseOverrideStore], which holds a dev-only endpoint override).
///
/// All methods are [Result]-typed; storage failures are values, never
/// throws (the `discard-result` rule applies to callers: handle the Err
/// branch explicitly).
class EasterEggsStore {
  const EasterEggsStore(this._prefs);

  /// Shared-preferences key for the toggle.
  static const String key = 'easter_eggs';

  final SharedPreferencesAsync _prefs;

  /// Reads the persisted toggle; `null` when none is stored yet
  /// (first launch — callers fall back to default **enabled**).
  Future<Result<bool?>> read() async {
    try {
      return Right(await _prefs.getBool(key));
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.easter_eggs_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists the toggle value.
  Future<Result<void>> write(bool enabled) async {
    try {
      await _prefs.setBool(key, enabled);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.easter_eggs_write_failed', detail: '$e'),
      );
    }
  }
}

/// Global Easter-eggs switch (issue #516): default **enabled**, persisted,
/// and effective immediately — consumers (e.g. the Karl Klammer overlay
/// in the AI Import view) `ref.watch` this notifier, so flipping it needs
/// no restart. KeepAlive by construction — the setting outlives any
/// screen.
///
/// Hydration is owned by `bootstrap()` (task 2 of
/// `add-karl-klammer-easter-egg`): it reads [EasterEggsStore] and seeds
/// the notifier state via [HydratedEasterEggs.overrideWith] before the
/// first consumer exists. A failed read falls back to default ON with
/// [readFailed] raised so the settings screen shows a visible error
/// state — never a silent failure.
class EasterEggs extends Notifier<bool> {
  @override
  bool build() => true;

  /// Set when hydration failed (visible error state in the settings
  /// screen; the effective value stays default ON).
  bool get readFailed => false;

  /// Flips the toggle and persists. The in-memory flip is applied
  /// immediately (global reactivity); the write result is returned so
  /// the caller surfaces persistence failures (no silent discard).
  Future<Result<void>> toggle(EasterEggsStore store) async {
    state = !state;
    return store.write(state);
  }
}

/// Bootstrap-seeded variant: carries the value resolved from
/// [EasterEggsStore.read] plus the read-failure flag.
final class HydratedEasterEggs extends EasterEggs {
  HydratedEasterEggs({required this.initial, required this._failed});

  final bool initial;
  final bool _failed;

  @override
  bool build() => initial;

  @override
  bool get readFailed => _failed;
}

final easterEggsProvider = NotifierProvider<EasterEggs, bool>(EasterEggs.new);
