// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_block_gate.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Resolves the active-block scope for a season-direct entry.
///
/// - Sticky scope matches `seasonId` → ready immediately (zero taps).
/// - Otherwise consults the existing `blocksListFetchProvider` seam
///   (`GET /v1/blocks?season_id=…` is `Authenticated` — works headerless):
///   - exactly one block → sets the sticky scope and yields one loading
///     frame, so content (and its controller fetches) only builds after
///     the Dio carries the header — no headerless-400 flash;
///   - several → `needsPick` (one-tap remembered picker);
///   - none → `empty` (inline hint);
///   - fetch failure → `AsyncError` (screen renders its retry surface).
///
/// The single-block set is guarded by equality, so the resulting
/// Dio/client/controller rebuilds converge instead of looping.

@ProviderFor(blockScopeResolution)
final blockScopeResolutionProvider = BlockScopeResolutionFamily._();

/// Resolves the active-block scope for a season-direct entry.
///
/// - Sticky scope matches `seasonId` → ready immediately (zero taps).
/// - Otherwise consults the existing `blocksListFetchProvider` seam
///   (`GET /v1/blocks?season_id=…` is `Authenticated` — works headerless):
///   - exactly one block → sets the sticky scope and yields one loading
///     frame, so content (and its controller fetches) only builds after
///     the Dio carries the header — no headerless-400 flash;
///   - several → `needsPick` (one-tap remembered picker);
///   - none → `empty` (inline hint);
///   - fetch failure → `AsyncError` (screen renders its retry surface).
///
/// The single-block set is guarded by equality, so the resulting
/// Dio/client/controller rebuilds converge instead of looping.

final class BlockScopeResolutionProvider
    extends
        $FunctionalProvider<
          AsyncValue<BlockScopeResolution>,
          AsyncValue<BlockScopeResolution>,
          AsyncValue<BlockScopeResolution>
        >
    with $Provider<AsyncValue<BlockScopeResolution>> {
  /// Resolves the active-block scope for a season-direct entry.
  ///
  /// - Sticky scope matches `seasonId` → ready immediately (zero taps).
  /// - Otherwise consults the existing `blocksListFetchProvider` seam
  ///   (`GET /v1/blocks?season_id=…` is `Authenticated` — works headerless):
  ///   - exactly one block → sets the sticky scope and yields one loading
  ///     frame, so content (and its controller fetches) only builds after
  ///     the Dio carries the header — no headerless-400 flash;
  ///   - several → `needsPick` (one-tap remembered picker);
  ///   - none → `empty` (inline hint);
  ///   - fetch failure → `AsyncError` (screen renders its retry surface).
  ///
  /// The single-block set is guarded by equality, so the resulting
  /// Dio/client/controller rebuilds converge instead of looping.
  BlockScopeResolutionProvider._({
    required BlockScopeResolutionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blockScopeResolutionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blockScopeResolutionHash();

  @override
  String toString() {
    return r'blockScopeResolutionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AsyncValue<BlockScopeResolution>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<BlockScopeResolution> create(Ref ref) {
    final argument = this.argument as String;
    return blockScopeResolution(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<BlockScopeResolution> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<BlockScopeResolution>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlockScopeResolutionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blockScopeResolutionHash() =>
    r'88641b9bb7f50938313cf339c7265d8b0e072872';

/// Resolves the active-block scope for a season-direct entry.
///
/// - Sticky scope matches `seasonId` → ready immediately (zero taps).
/// - Otherwise consults the existing `blocksListFetchProvider` seam
///   (`GET /v1/blocks?season_id=…` is `Authenticated` — works headerless):
///   - exactly one block → sets the sticky scope and yields one loading
///     frame, so content (and its controller fetches) only builds after
///     the Dio carries the header — no headerless-400 flash;
///   - several → `needsPick` (one-tap remembered picker);
///   - none → `empty` (inline hint);
///   - fetch failure → `AsyncError` (screen renders its retry surface).
///
/// The single-block set is guarded by equality, so the resulting
/// Dio/client/controller rebuilds converge instead of looping.

final class BlockScopeResolutionFamily extends $Family
    with $FunctionalFamilyOverride<AsyncValue<BlockScopeResolution>, String> {
  BlockScopeResolutionFamily._()
    : super(
        retry: null,
        name: r'blockScopeResolutionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Resolves the active-block scope for a season-direct entry.
  ///
  /// - Sticky scope matches `seasonId` → ready immediately (zero taps).
  /// - Otherwise consults the existing `blocksListFetchProvider` seam
  ///   (`GET /v1/blocks?season_id=…` is `Authenticated` — works headerless):
  ///   - exactly one block → sets the sticky scope and yields one loading
  ///     frame, so content (and its controller fetches) only builds after
  ///     the Dio carries the header — no headerless-400 flash;
  ///   - several → `needsPick` (one-tap remembered picker);
  ///   - none → `empty` (inline hint);
  ///   - fetch failure → `AsyncError` (screen renders its retry surface).
  ///
  /// The single-block set is guarded by equality, so the resulting
  /// Dio/client/controller rebuilds converge instead of looping.

  BlockScopeResolutionProvider call(String seasonId) =>
      BlockScopeResolutionProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'blockScopeResolutionProvider';
}
