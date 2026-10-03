// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The picker's rows for ONE job: the job's `block_id` scopes a LIVE
/// `GET /v1/episodes?block_id=…` fetch through the shared
/// [episodesListFetchProvider] seam (tests override it with a fake;
/// the `seasonId` family slot is unused by the fetch and passed empty).
/// A failed fetch falls back to the block's CACHED rows (offline-first,
/// retained-stale-rows pattern — a transient failure never renders as an
/// empty list while stale rows exist); only a failure with an empty cache
/// surfaces the error. A FAILED cache read surfaces as a picker error —
/// it is never mistaken for "the job has no block", which would fall back
/// to the cache-wide read and offer episodes OUTSIDE the job's block. The
/// cache-wide fallback runs only after a successful lookup establishes
/// that the job carries no `block_id`.

@ProviderFor(aiEpisodePickerRows)
final aiEpisodePickerRowsProvider = AiEpisodePickerRowsFamily._();

/// The picker's rows for ONE job: the job's `block_id` scopes a LIVE
/// `GET /v1/episodes?block_id=…` fetch through the shared
/// [episodesListFetchProvider] seam (tests override it with a fake;
/// the `seasonId` family slot is unused by the fetch and passed empty).
/// A failed fetch falls back to the block's CACHED rows (offline-first,
/// retained-stale-rows pattern — a transient failure never renders as an
/// empty list while stale rows exist); only a failure with an empty cache
/// surfaces the error. A FAILED cache read surfaces as a picker error —
/// it is never mistaken for "the job has no block", which would fall back
/// to the cache-wide read and offer episodes OUTSIDE the job's block. The
/// cache-wide fallback runs only after a successful lookup establishes
/// that the job carries no `block_id`.

final class AiEpisodePickerRowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<EpisodeView>>,
          List<EpisodeView>,
          FutureOr<List<EpisodeView>>
        >
    with
        $FutureModifier<List<EpisodeView>>,
        $FutureProvider<List<EpisodeView>> {
  /// The picker's rows for ONE job: the job's `block_id` scopes a LIVE
  /// `GET /v1/episodes?block_id=…` fetch through the shared
  /// [episodesListFetchProvider] seam (tests override it with a fake;
  /// the `seasonId` family slot is unused by the fetch and passed empty).
  /// A failed fetch falls back to the block's CACHED rows (offline-first,
  /// retained-stale-rows pattern — a transient failure never renders as an
  /// empty list while stale rows exist); only a failure with an empty cache
  /// surfaces the error. A FAILED cache read surfaces as a picker error —
  /// it is never mistaken for "the job has no block", which would fall back
  /// to the cache-wide read and offer episodes OUTSIDE the job's block. The
  /// cache-wide fallback runs only after a successful lookup establishes
  /// that the job carries no `block_id`.
  AiEpisodePickerRowsProvider._({
    required AiEpisodePickerRowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiEpisodePickerRowsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiEpisodePickerRowsHash();

  @override
  String toString() {
    return r'aiEpisodePickerRowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<EpisodeView>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<EpisodeView>> create(Ref ref) {
    final argument = this.argument as String;
    return aiEpisodePickerRows(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiEpisodePickerRowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiEpisodePickerRowsHash() =>
    r'4c4a6e8c688b702ee455477b9b67897860532286';

/// The picker's rows for ONE job: the job's `block_id` scopes a LIVE
/// `GET /v1/episodes?block_id=…` fetch through the shared
/// [episodesListFetchProvider] seam (tests override it with a fake;
/// the `seasonId` family slot is unused by the fetch and passed empty).
/// A failed fetch falls back to the block's CACHED rows (offline-first,
/// retained-stale-rows pattern — a transient failure never renders as an
/// empty list while stale rows exist); only a failure with an empty cache
/// surfaces the error. A FAILED cache read surfaces as a picker error —
/// it is never mistaken for "the job has no block", which would fall back
/// to the cache-wide read and offer episodes OUTSIDE the job's block. The
/// cache-wide fallback runs only after a successful lookup establishes
/// that the job carries no `block_id`.

final class AiEpisodePickerRowsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<EpisodeView>>, String> {
  AiEpisodePickerRowsFamily._()
    : super(
        retry: null,
        name: r'aiEpisodePickerRowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The picker's rows for ONE job: the job's `block_id` scopes a LIVE
  /// `GET /v1/episodes?block_id=…` fetch through the shared
  /// [episodesListFetchProvider] seam (tests override it with a fake;
  /// the `seasonId` family slot is unused by the fetch and passed empty).
  /// A failed fetch falls back to the block's CACHED rows (offline-first,
  /// retained-stale-rows pattern — a transient failure never renders as an
  /// empty list while stale rows exist); only a failure with an empty cache
  /// surfaces the error. A FAILED cache read surfaces as a picker error —
  /// it is never mistaken for "the job has no block", which would fall back
  /// to the cache-wide read and offer episodes OUTSIDE the job's block. The
  /// cache-wide fallback runs only after a successful lookup establishes
  /// that the job carries no `block_id`.

  AiEpisodePickerRowsProvider call(String jobId) =>
      AiEpisodePickerRowsProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiEpisodePickerRowsProvider';
}
