// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_scope_chip.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Cache-only backfill of a label-less scope's block number (issue #548).
///
/// A scope restored from the pre-#548 persisted document shape carries no
/// block number, so the chip cannot render `blockTileLabel(number)`. The
/// honest source is the block the user picked — but on this degradation
/// path no `BlockView` is in hand. This provider re-resolves the number
/// ONCE from `blockRepository.readCached(seasonId)` — pure Drift, NEVER a
/// live fetch on a hot path — and `null` when the cache has no row for the
/// block (the chip keeps its explicit "unknown" narrative; a silent filter
/// is never rendered as if unfiltered).

@ProviderFor(resolvedScopeBlockNumber)
final resolvedScopeBlockNumberProvider = ResolvedScopeBlockNumberFamily._();

/// Cache-only backfill of a label-less scope's block number (issue #548).
///
/// A scope restored from the pre-#548 persisted document shape carries no
/// block number, so the chip cannot render `blockTileLabel(number)`. The
/// honest source is the block the user picked — but on this degradation
/// path no `BlockView` is in hand. This provider re-resolves the number
/// ONCE from `blockRepository.readCached(seasonId)` — pure Drift, NEVER a
/// live fetch on a hot path — and `null` when the cache has no row for the
/// block (the chip keeps its explicit "unknown" narrative; a silent filter
/// is never rendered as if unfiltered).

final class ResolvedScopeBlockNumberProvider
    extends $FunctionalProvider<AsyncValue<int?>, int?, FutureOr<int?>>
    with $FutureModifier<int?>, $FutureProvider<int?> {
  /// Cache-only backfill of a label-less scope's block number (issue #548).
  ///
  /// A scope restored from the pre-#548 persisted document shape carries no
  /// block number, so the chip cannot render `blockTileLabel(number)`. The
  /// honest source is the block the user picked — but on this degradation
  /// path no `BlockView` is in hand. This provider re-resolves the number
  /// ONCE from `blockRepository.readCached(seasonId)` — pure Drift, NEVER a
  /// live fetch on a hot path — and `null` when the cache has no row for the
  /// block (the chip keeps its explicit "unknown" narrative; a silent filter
  /// is never rendered as if unfiltered).
  ResolvedScopeBlockNumberProvider._({
    required ResolvedScopeBlockNumberFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'resolvedScopeBlockNumberProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$resolvedScopeBlockNumberHash();

  @override
  String toString() {
    return r'resolvedScopeBlockNumberProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int?> create(Ref ref) {
    final argument = this.argument as (String, String);
    return resolvedScopeBlockNumber(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedScopeBlockNumberProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$resolvedScopeBlockNumberHash() =>
    r'b2c65e34af22d8e389aa817402ef3a38abc10701';

/// Cache-only backfill of a label-less scope's block number (issue #548).
///
/// A scope restored from the pre-#548 persisted document shape carries no
/// block number, so the chip cannot render `blockTileLabel(number)`. The
/// honest source is the block the user picked — but on this degradation
/// path no `BlockView` is in hand. This provider re-resolves the number
/// ONCE from `blockRepository.readCached(seasonId)` — pure Drift, NEVER a
/// live fetch on a hot path — and `null` when the cache has no row for the
/// block (the chip keeps its explicit "unknown" narrative; a silent filter
/// is never rendered as if unfiltered).

final class ResolvedScopeBlockNumberFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int?>, (String, String)> {
  ResolvedScopeBlockNumberFamily._()
    : super(
        retry: null,
        name: r'resolvedScopeBlockNumberProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Cache-only backfill of a label-less scope's block number (issue #548).
  ///
  /// A scope restored from the pre-#548 persisted document shape carries no
  /// block number, so the chip cannot render `blockTileLabel(number)`. The
  /// honest source is the block the user picked — but on this degradation
  /// path no `BlockView` is in hand. This provider re-resolves the number
  /// ONCE from `blockRepository.readCached(seasonId)` — pure Drift, NEVER a
  /// live fetch on a hot path — and `null` when the cache has no row for the
  /// block (the chip keeps its explicit "unknown" narrative; a silent filter
  /// is never rendered as if unfiltered).

  ResolvedScopeBlockNumberProvider call(String seasonId, String blockId) =>
      ResolvedScopeBlockNumberProvider._(
        argument: (seasonId, blockId),
        from: this,
      );

  @override
  String toString() => r'resolvedScopeBlockNumberProvider';
}
