// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// The registered Easter eggs (issue #615). Each egg has its own flat
/// `shared_preferences` key so one egg's value never affects another and a
/// partial write stays recoverable (Decision D1 of
/// `615-dejavu-cat-easter-egg`).
enum EasterEggId {
  /// The Karl Kleiderbügel clothes-hanger assistant in the AI Import
  /// view (renamed from "Karl Klammer" in issue #670).
  karlKleiderbuegel('easter_eggs.karl_kleiderbuegel'),

  /// The October-only Deja-vu Cat on the launch splash.
  dejaVuCat('easter_eggs.dejavu_cat');

  const EasterEggId(this.prefsKey);

  /// The flat `shared_preferences` key holding this egg's boolean.
  final String prefsKey;
}

/// A read snapshot of every egg plus the legacy-migration outcome.
final class EasterEggsSnapshot {
  const EasterEggsSnapshot({
    required this.values,
    required this.migratedLegacy,
  });

  /// Stored value per egg; `null` means "no persisted value" (default ON).
  final Map<EasterEggId, bool?> values;

  /// True when the legacy global flag was found and folded into the
  /// per-egg keys during this read.
  final bool migratedLegacy;

  /// The effective value: the stored value or the default **ON**.
  bool effective(EasterEggId id) => values[id] ?? true;
}

/// On-device persistence for the per-egg Easter-eggs switches (issue
/// #615, capability `flutter-easter-eggs`).
///
/// The flags are **not secrets** (no token, no credential), so they live in
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

  /// The pre-#615 global toggle key. Read once during migration, then
  /// removed; a leftover is harmless and ignored on the next boot.
  static const String legacyKey = 'easter_eggs';

  /// The pre-#670 per-egg key of the Karl egg (then "Karl Klammer").
  /// Read once during migration, then removed; a leftover is harmless
  /// and ignored on the next boot (issue #670 rename).
  static const String legacyKarlKlammerKey = 'easter_eggs.karl_klammer';

  final SharedPreferencesAsync _prefs;

  /// Reads one egg; `null` when none is stored yet (first launch —
  /// callers fall back to default **enabled**).
  Future<Result<bool?>> read(EasterEggId id) async {
    try {
      return Right(await _prefs.getBool(id.prefsKey));
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.easter_eggs_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists one egg's value.
  Future<Result<void>> write(EasterEggId id, bool enabled) async {
    try {
      await _prefs.setBool(id.prefsKey, enabled);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.easter_eggs_write_failed', detail: '$e'),
      );
    }
  }

  /// Reads every egg, migrating the legacy global flag on the first launch
  /// after the update (issue #615, Decision D2).
  ///
  /// When the legacy key is present it seeds **only eggs with no stored
  /// value** (a partially-migrated install keeps its explicit per-egg
  /// choices), then removes the legacy key. A failed removal is non-fatal:
  /// the leftover key is ignored on the next boot. Any other failure
  /// (reads, migration writes) surfaces as the stable read-failure code so
  /// the caller can fall back to default ON per egg with a visible error.
  Future<Result<EasterEggsSnapshot>> readAll() async {
    try {
      final values = <EasterEggId, bool?>{};
      for (final id in EasterEggId.values) {
        values[id] = await _prefs.getBool(id.prefsKey);
      }

      // One-time rename migration (issue #670): carry the stored
      // "Karl Klammer" toggle over to the renamed key. Only fires when
      // the new key holds no value yet — an explicit post-rename choice
      // always wins. The old key is removed in either case (a leftover
      // would be harmless, but a clean cut keeps the store tidy).
      const karl = EasterEggId.karlKleiderbuegel;
      final oldKarl = await _prefs.getBool(legacyKarlKlammerKey);
      if (oldKarl != null) {
        if (values[karl] == null) {
          await _prefs.setBool(karl.prefsKey, oldKarl);
          values[karl] = oldKarl;
        }
        try {
          await _prefs.remove(legacyKarlKlammerKey);
        } on Exception {
          // Non-fatal: the leftover old key is ignored on the next
          // boot (the renamed value already won the migration).
        }
      }

      final legacy = await _prefs.getBool(legacyKey);
      var migrated = false;
      if (legacy != null) {
        for (final id in EasterEggId.values) {
          if (values[id] == null) {
            await _prefs.setBool(id.prefsKey, legacy);
            values[id] = legacy;
          }
        }
        migrated = true;
        try {
          await _prefs.remove(legacyKey);
        } on Exception {
          // Non-fatal: the leftover legacy key is ignored on the next
          // boot (the per-egg values already won the migration).
        }
      }

      return Right(
        EasterEggsSnapshot(values: values, migratedLegacy: migrated),
      );
    } catch (e) {
      return Left(
        ProblemError(code: 'settings.easter_eggs_read_failed', detail: '$e'),
      );
    }
  }
}

/// One egg's reactive switch (issue #615, Decision D3): default
/// **enabled**, persisted, and effective immediately. Consumers
/// `ref.watch(easterEggProvider(id))` — flipping one egg never rebuilds
/// the other. KeepAlive by construction — the setting outlives any screen.
///
/// Hydration is owned by `bootstrap()`: it reads [EasterEggsStore] and
/// seeds each family member via [HydratedEasterEggs.overrideWith] before
/// the first consumer exists. A failed read falls back to default ON with
/// [readFailed] raised so the settings screen shows a visible error
/// state — never a silent failure.
class EasterEggs extends Notifier<bool> {
  EasterEggs(this.id);

  /// The egg this notifier owns.
  final EasterEggId id;

  @override
  bool build() => true;

  /// Set when hydration failed (visible error state in the settings
  /// screen; the effective value stays default ON).
  bool get readFailed => false;

  /// Flips this egg and persists. The in-memory flip is applied
  /// immediately (global reactivity); the write result is returned so
  /// the caller surfaces persistence failures (no silent discard).
  Future<Result<void>> toggle(EasterEggsStore store) async {
    state = !state;
    return store.write(id, state);
  }
}

/// Bootstrap-seeded variant: carries the value resolved from
/// [EasterEggsStore.readAll] plus the read-failure flag.
final class HydratedEasterEggs extends EasterEggs {
  HydratedEasterEggs(super.id, {required this.initial, required this.failed});

  final bool initial;
  final bool failed;

  @override
  bool build() => initial;

  @override
  bool get readFailed => failed;
}

/// The per-egg switch family (issue #615). Keyed by [EasterEggId].
final easterEggProvider =
    NotifierProvider.family<EasterEggs, bool, EasterEggId>(EasterEggs.new);
