// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_script_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Composes the active season's chronological script view (issue #610).
///
/// The scene read model is episode-scoped (`GET /v1/scenes` requires
/// `episode_id`), so the season-wide overview is a READ-ONLY client
/// composition: blocks of the season → their episodes → their scenes, each
/// level through the existing authenticated fetch seams (which own the Drift
/// cache discipline). No new backend route, no new cache table.
///
/// Failure semantics:
/// - the season's blocks cannot be read → `Left` (the whole view errors);
/// - one block's or one episode's scenes fail → `Right` with
///   [SeasonScript.failedEpisodes] set, so the UI states the partial truth.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").

@ProviderFor(seasonScriptFetch)
final seasonScriptFetchProvider = SeasonScriptFetchFamily._();

/// Composes the active season's chronological script view (issue #610).
///
/// The scene read model is episode-scoped (`GET /v1/scenes` requires
/// `episode_id`), so the season-wide overview is a READ-ONLY client
/// composition: blocks of the season → their episodes → their scenes, each
/// level through the existing authenticated fetch seams (which own the Drift
/// cache discipline). No new backend route, no new cache table.
///
/// Failure semantics:
/// - the season's blocks cannot be read → `Left` (the whole view errors);
/// - one block's or one episode's scenes fail → `Right` with
///   [SeasonScript.failedEpisodes] set, so the UI states the partial truth.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").

final class SeasonScriptFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<SeasonScript>>,
          Result<SeasonScript>,
          FutureOr<Result<SeasonScript>>
        >
    with
        $FutureModifier<Result<SeasonScript>>,
        $FutureProvider<Result<SeasonScript>> {
  /// Composes the active season's chronological script view (issue #610).
  ///
  /// The scene read model is episode-scoped (`GET /v1/scenes` requires
  /// `episode_id`), so the season-wide overview is a READ-ONLY client
  /// composition: blocks of the season → their episodes → their scenes, each
  /// level through the existing authenticated fetch seams (which own the Drift
  /// cache discipline). No new backend route, no new cache table.
  ///
  /// Failure semantics:
  /// - the season's blocks cannot be read → `Left` (the whole view errors);
  /// - one block's or one episode's scenes fail → `Right` with
  ///   [SeasonScript.failedEpisodes] set, so the UI states the partial truth.
  ///
  /// A sticky block scope for THIS season narrows the composition to that
  /// block — the scope chip's promise ("what filters your requests") holds for
  /// the Script view too. A scope belonging to another season is ignored here
  /// (the same reuse rule the block chip renders as "gilt hier nicht").
  SeasonScriptFetchProvider._({
    required SeasonScriptFetchFamily super.from,
    required SeasonView super.argument,
  }) : super(
         retry: null,
         name: r'seasonScriptFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$seasonScriptFetchHash();

  @override
  String toString() {
    return r'seasonScriptFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<SeasonScript>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<SeasonScript>> create(Ref ref) {
    final argument = this.argument as SeasonView;
    return seasonScriptFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SeasonScriptFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$seasonScriptFetchHash() => r'556e51c43ac6687bd1c80ebceb0cf70376af4026';

/// Composes the active season's chronological script view (issue #610).
///
/// The scene read model is episode-scoped (`GET /v1/scenes` requires
/// `episode_id`), so the season-wide overview is a READ-ONLY client
/// composition: blocks of the season → their episodes → their scenes, each
/// level through the existing authenticated fetch seams (which own the Drift
/// cache discipline). No new backend route, no new cache table.
///
/// Failure semantics:
/// - the season's blocks cannot be read → `Left` (the whole view errors);
/// - one block's or one episode's scenes fail → `Right` with
///   [SeasonScript.failedEpisodes] set, so the UI states the partial truth.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").

final class SeasonScriptFetchFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<SeasonScript>>, SeasonView> {
  SeasonScriptFetchFamily._()
    : super(
        retry: null,
        name: r'seasonScriptFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Composes the active season's chronological script view (issue #610).
  ///
  /// The scene read model is episode-scoped (`GET /v1/scenes` requires
  /// `episode_id`), so the season-wide overview is a READ-ONLY client
  /// composition: blocks of the season → their episodes → their scenes, each
  /// level through the existing authenticated fetch seams (which own the Drift
  /// cache discipline). No new backend route, no new cache table.
  ///
  /// Failure semantics:
  /// - the season's blocks cannot be read → `Left` (the whole view errors);
  /// - one block's or one episode's scenes fail → `Right` with
  ///   [SeasonScript.failedEpisodes] set, so the UI states the partial truth.
  ///
  /// A sticky block scope for THIS season narrows the composition to that
  /// block — the scope chip's promise ("what filters your requests") holds for
  /// the Script view too. A scope belonging to another season is ignored here
  /// (the same reuse rule the block chip renders as "gilt hier nicht").

  SeasonScriptFetchProvider call(SeasonView season) =>
      SeasonScriptFetchProvider._(argument: season, from: this);

  @override
  String toString() => r'seasonScriptFetchProvider';
}
