// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jobs_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The AI-import **jobs view** (issue #547): a started import job stays
/// reachable after the user leaves the status screen.
///
/// The controller is the seasons/blocks seam shape, read-only:
///
/// * **Cached first** — `AiImportRepository.readCached(sub)` paints
///   immediately (identity-scoped by the authenticated `sub`; the Drift
///   cache holds only state the server also holds, AGENTS.md §8). The
///   remembered-id fast path (`AiImportHandoffState.jobIds`) orders the
///   first paint newest-remembered-first — the documented "what did I
///   import" surface (task 1.3 design).
/// * **Then revalidate** — `AiImportRepository.listJobsAndCache()`, the
///   previously-unused `GET /v1/ai-import/jobs` wiring (server-
///   authoritative, newest-first, paginated).
/// * **NO watch** — the list renders cached status and arms nothing (D5:
///   the single foreground job watch stays owned by `AiJobStatusScreen`;
///   a watch per row would rebuild the request-budget problem D5 exists
///   to prevent). A unit test pins the repository watch-call count at
///   zero.
/// * **`Result`-typed throughout** — a fetch `Err` surfaces as
///   `AsyncError` (never silently swallowed, AGENTS.md §5); the retained
///   snapshot keeps the list on screen with the error keyed on the stable
///   problem `code`, never the server `detail`.
///
/// There is no optimistic overlay: this boundary dispatches no commands
/// (rows are navigation targets; the only write surface remains the
/// submit screen's upload and the apply screen's command).
/// The list fetch is ONE `GET /v1/ai-import/jobs` per (re)build — a
/// revalidation, not polling; pull-to-refresh re-runs exactly it.

@ProviderFor(aiImportJobsFetch)
final aiImportJobsFetchProvider = AiImportJobsFetchProvider._();

/// The AI-import **jobs view** (issue #547): a started import job stays
/// reachable after the user leaves the status screen.
///
/// The controller is the seasons/blocks seam shape, read-only:
///
/// * **Cached first** — `AiImportRepository.readCached(sub)` paints
///   immediately (identity-scoped by the authenticated `sub`; the Drift
///   cache holds only state the server also holds, AGENTS.md §8). The
///   remembered-id fast path (`AiImportHandoffState.jobIds`) orders the
///   first paint newest-remembered-first — the documented "what did I
///   import" surface (task 1.3 design).
/// * **Then revalidate** — `AiImportRepository.listJobsAndCache()`, the
///   previously-unused `GET /v1/ai-import/jobs` wiring (server-
///   authoritative, newest-first, paginated).
/// * **NO watch** — the list renders cached status and arms nothing (D5:
///   the single foreground job watch stays owned by `AiJobStatusScreen`;
///   a watch per row would rebuild the request-budget problem D5 exists
///   to prevent). A unit test pins the repository watch-call count at
///   zero.
/// * **`Result`-typed throughout** — a fetch `Err` surfaces as
///   `AsyncError` (never silently swallowed, AGENTS.md §5); the retained
///   snapshot keeps the list on screen with the error keyed on the stable
///   problem `code`, never the server `detail`.
///
/// There is no optimistic overlay: this boundary dispatches no commands
/// (rows are navigation targets; the only write surface remains the
/// submit screen's upload and the apply screen's command).
/// The list fetch is ONE `GET /v1/ai-import/jobs` per (re)build — a
/// revalidation, not polling; pull-to-refresh re-runs exactly it.

final class AiImportJobsFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<AiImportJob>>>,
          Result<List<AiImportJob>>,
          FutureOr<Result<List<AiImportJob>>>
        >
    with
        $FutureModifier<Result<List<AiImportJob>>>,
        $FutureProvider<Result<List<AiImportJob>>> {
  /// The AI-import **jobs view** (issue #547): a started import job stays
  /// reachable after the user leaves the status screen.
  ///
  /// The controller is the seasons/blocks seam shape, read-only:
  ///
  /// * **Cached first** — `AiImportRepository.readCached(sub)` paints
  ///   immediately (identity-scoped by the authenticated `sub`; the Drift
  ///   cache holds only state the server also holds, AGENTS.md §8). The
  ///   remembered-id fast path (`AiImportHandoffState.jobIds`) orders the
  ///   first paint newest-remembered-first — the documented "what did I
  ///   import" surface (task 1.3 design).
  /// * **Then revalidate** — `AiImportRepository.listJobsAndCache()`, the
  ///   previously-unused `GET /v1/ai-import/jobs` wiring (server-
  ///   authoritative, newest-first, paginated).
  /// * **NO watch** — the list renders cached status and arms nothing (D5:
  ///   the single foreground job watch stays owned by `AiJobStatusScreen`;
  ///   a watch per row would rebuild the request-budget problem D5 exists
  ///   to prevent). A unit test pins the repository watch-call count at
  ///   zero.
  /// * **`Result`-typed throughout** — a fetch `Err` surfaces as
  ///   `AsyncError` (never silently swallowed, AGENTS.md §5); the retained
  ///   snapshot keeps the list on screen with the error keyed on the stable
  ///   problem `code`, never the server `detail`.
  ///
  /// There is no optimistic overlay: this boundary dispatches no commands
  /// (rows are navigation targets; the only write surface remains the
  /// submit screen's upload and the apply screen's command).
  /// The list fetch is ONE `GET /v1/ai-import/jobs` per (re)build — a
  /// revalidation, not polling; pull-to-refresh re-runs exactly it.
  AiImportJobsFetchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportJobsFetchProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportJobsFetchHash();

  @$internal
  @override
  $FutureProviderElement<Result<List<AiImportJob>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<AiImportJob>>> create(Ref ref) {
    return aiImportJobsFetch(ref);
  }
}

String _$aiImportJobsFetchHash() => r'342ad1444b1626963188cc4970ee321d1309b8e6';

/// Retained last-good snapshot (seasons/blocks pattern): updated after
/// every successful list read and by the cache-first seed, so the
/// selector can serve cached rows while the fetch is loading or failed.

@ProviderFor(AiImportJobsPrevRows)
final aiImportJobsPrevRowsProvider = AiImportJobsPrevRowsProvider._();

/// Retained last-good snapshot (seasons/blocks pattern): updated after
/// every successful list read and by the cache-first seed, so the
/// selector can serve cached rows while the fetch is loading or failed.
final class AiImportJobsPrevRowsProvider
    extends $NotifierProvider<AiImportJobsPrevRows, List<AiImportJobRowView>> {
  /// Retained last-good snapshot (seasons/blocks pattern): updated after
  /// every successful list read and by the cache-first seed, so the
  /// selector can serve cached rows while the fetch is loading or failed.
  AiImportJobsPrevRowsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportJobsPrevRowsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportJobsPrevRowsHash();

  @$internal
  @override
  AiImportJobsPrevRows create() => AiImportJobsPrevRows();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AiImportJobRowView> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AiImportJobRowView>>(value),
    );
  }
}

String _$aiImportJobsPrevRowsHash() =>
    r'0d2b2a2f5ed4cdc2957f7f645bf1cad144eb1a89';

/// Retained last-good snapshot (seasons/blocks pattern): updated after
/// every successful list read and by the cache-first seed, so the
/// selector can serve cached rows while the fetch is loading or failed.

abstract class _$AiImportJobsPrevRows
    extends $Notifier<List<AiImportJobRowView>> {
  List<AiImportJobRowView> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<List<AiImportJobRowView>, List<AiImportJobRowView>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AiImportJobRowView>, List<AiImportJobRowView>>,
              List<AiImportJobRowView>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Read-projection controller. A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (blocks reference pattern): this seeder watches the
/// repository and the fetch ONLY — never [AiImportJobsPrevRows]. It
/// writes the snapshot store but never reads it back through a watch, so
/// its own writes can never invalidate it.

@ProviderFor(AiImportJobsViewController)
final aiImportJobsViewControllerProvider =
    AiImportJobsViewControllerProvider._();

/// Read-projection controller. A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (blocks reference pattern): this seeder watches the
/// repository and the fetch ONLY — never [AiImportJobsPrevRows]. It
/// writes the snapshot store but never reads it back through a watch, so
/// its own writes can never invalidate it.
final class AiImportJobsViewControllerProvider
    extends
        $NotifierProvider<
          AiImportJobsViewController,
          AsyncValue<AiImportJobsState>
        > {
  /// Read-projection controller. A sync `Notifier` (not an `AsyncNotifier`)
  /// so a fetch `Err` surfaces as `AsyncError` rather than triggering
  /// Riverpod's async-notifier retry loop.
  ///
  /// Loop discipline (blocks reference pattern): this seeder watches the
  /// repository and the fetch ONLY — never [AiImportJobsPrevRows]. It
  /// writes the snapshot store but never reads it back through a watch, so
  /// its own writes can never invalidate it.
  AiImportJobsViewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportJobsViewControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportJobsViewControllerHash();

  @$internal
  @override
  AiImportJobsViewController create() => AiImportJobsViewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<AiImportJobsState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<AiImportJobsState>>(
        value,
      ),
    );
  }
}

String _$aiImportJobsViewControllerHash() =>
    r'2cecdb0edf835a14285c5f5579f0a219fec480c5';

/// Read-projection controller. A sync `Notifier` (not an `AsyncNotifier`)
/// so a fetch `Err` surfaces as `AsyncError` rather than triggering
/// Riverpod's async-notifier retry loop.
///
/// Loop discipline (blocks reference pattern): this seeder watches the
/// repository and the fetch ONLY — never [AiImportJobsPrevRows]. It
/// writes the snapshot store but never reads it back through a watch, so
/// its own writes can never invalidate it.

abstract class _$AiImportJobsViewController
    extends $Notifier<AsyncValue<AiImportJobsState>> {
  AsyncValue<AiImportJobsState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AiImportJobsState>,
              AsyncValue<AiImportJobsState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AiImportJobsState>,
                AsyncValue<AiImportJobsState>
              >,
              AsyncValue<AiImportJobsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
