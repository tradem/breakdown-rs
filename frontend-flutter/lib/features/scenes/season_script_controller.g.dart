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
/// - one block's episodes or one episode's scenes fail → `Right` with the
///   respective [SeasonScript.failedBlocks] / [SeasonScript.failedEpisodes]
///   entry set, so the UI states the partial truth. A block whose episode
///   read failed contributes NO scenes, and saying so is the whole point:
///   silently omitting them would present a short list as the season's
///   complete script.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").
///
/// Issue #709: the sticky EPISODE scope (when it belongs to this season)
/// wins over the block scope — the composition narrows to the episode's
/// block and the scene reads skip every other episode of it (fewer reads,
/// same result: the filter works on the already composed parts, no second
/// projection, no new read seams). A stale scope whose block is not among
/// the season's blocks (e.g. the block was deleted) composes no rows; a
/// block read that FAILS under the scope still surfaces through the
/// partial notices as today.

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
/// - one block's episodes or one episode's scenes fail → `Right` with the
///   respective [SeasonScript.failedBlocks] / [SeasonScript.failedEpisodes]
///   entry set, so the UI states the partial truth. A block whose episode
///   read failed contributes NO scenes, and saying so is the whole point:
///   silently omitting them would present a short list as the season's
///   complete script.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").
///
/// Issue #709: the sticky EPISODE scope (when it belongs to this season)
/// wins over the block scope — the composition narrows to the episode's
/// block and the scene reads skip every other episode of it (fewer reads,
/// same result: the filter works on the already composed parts, no second
/// projection, no new read seams). A stale scope whose block is not among
/// the season's blocks (e.g. the block was deleted) composes no rows; a
/// block read that FAILS under the scope still surfaces through the
/// partial notices as today.

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
  /// - one block's episodes or one episode's scenes fail → `Right` with the
  ///   respective [SeasonScript.failedBlocks] / [SeasonScript.failedEpisodes]
  ///   entry set, so the UI states the partial truth. A block whose episode
  ///   read failed contributes NO scenes, and saying so is the whole point:
  ///   silently omitting them would present a short list as the season's
  ///   complete script.
  ///
  /// A sticky block scope for THIS season narrows the composition to that
  /// block — the scope chip's promise ("what filters your requests") holds for
  /// the Script view too. A scope belonging to another season is ignored here
  /// (the same reuse rule the block chip renders as "gilt hier nicht").
  ///
  /// Issue #709: the sticky EPISODE scope (when it belongs to this season)
  /// wins over the block scope — the composition narrows to the episode's
  /// block and the scene reads skip every other episode of it (fewer reads,
  /// same result: the filter works on the already composed parts, no second
  /// projection, no new read seams). A stale scope whose block is not among
  /// the season's blocks (e.g. the block was deleted) composes no rows; a
  /// block read that FAILS under the scope still surfaces through the
  /// partial notices as today.
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

String _$seasonScriptFetchHash() => r'ba458e640d5f8b3d9ad0e94513c525ab4012f387';

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
/// - one block's episodes or one episode's scenes fail → `Right` with the
///   respective [SeasonScript.failedBlocks] / [SeasonScript.failedEpisodes]
///   entry set, so the UI states the partial truth. A block whose episode
///   read failed contributes NO scenes, and saying so is the whole point:
///   silently omitting them would present a short list as the season's
///   complete script.
///
/// A sticky block scope for THIS season narrows the composition to that
/// block — the scope chip's promise ("what filters your requests") holds for
/// the Script view too. A scope belonging to another season is ignored here
/// (the same reuse rule the block chip renders as "gilt hier nicht").
///
/// Issue #709: the sticky EPISODE scope (when it belongs to this season)
/// wins over the block scope — the composition narrows to the episode's
/// block and the scene reads skip every other episode of it (fewer reads,
/// same result: the filter works on the already composed parts, no second
/// projection, no new read seams). A stale scope whose block is not among
/// the season's blocks (e.g. the block was deleted) composes no rows; a
/// block read that FAILS under the scope still surfaces through the
/// partial notices as today.

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
  /// - one block's episodes or one episode's scenes fail → `Right` with the
  ///   respective [SeasonScript.failedBlocks] / [SeasonScript.failedEpisodes]
  ///   entry set, so the UI states the partial truth. A block whose episode
  ///   read failed contributes NO scenes, and saying so is the whole point:
  ///   silently omitting them would present a short list as the season's
  ///   complete script.
  ///
  /// A sticky block scope for THIS season narrows the composition to that
  /// block — the scope chip's promise ("what filters your requests") holds for
  /// the Script view too. A scope belonging to another season is ignored here
  /// (the same reuse rule the block chip renders as "gilt hier nicht").
  ///
  /// Issue #709: the sticky EPISODE scope (when it belongs to this season)
  /// wins over the block scope — the composition narrows to the episode's
  /// block and the scene reads skip every other episode of it (fewer reads,
  /// same result: the filter works on the already composed parts, no second
  /// projection, no new read seams). A stale scope whose block is not among
  /// the season's blocks (e.g. the block was deleted) composes no rows; a
  /// block read that FAILS under the scope still surfaces through the
  /// partial notices as today.

  SeasonScriptFetchProvider call(SeasonView season) =>
      SeasonScriptFetchProvider._(argument: season, from: this);

  @override
  String toString() => r'seasonScriptFetchProvider';
}
