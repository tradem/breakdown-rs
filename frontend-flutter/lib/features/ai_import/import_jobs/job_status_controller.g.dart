// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_status_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
/// #664 battery contract D5).
///
/// The ONLY SSE consumer in the app: subscribes to
/// `jobRepository.watch(jobId)` — the push-based, foreground-only event
/// stream. The subscription lives exactly as long as this provider AND the
/// app is foregrounded:
///
/// * leaving the screen disposes the provider → the subscription (and its
///   Dio cancel token) is cancelled — no stream survives the screen;
/// * the app transitioning to the background (`paused`/`hidden`/
///   `detached`) cancels the subscription immediately — zero background
///   network wake-ups;
/// * returning to the foreground (`resumed`) performs exactly ONE
///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
///   job is still non-terminal.
///
/// There is no cancel affordance (D3 — no server route): the copy says
/// processing continues; the user can only close the screen.

@ProviderFor(AiJobStatusController)
final aiJobStatusControllerProvider = AiJobStatusControllerFamily._();

/// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
/// #664 battery contract D5).
///
/// The ONLY SSE consumer in the app: subscribes to
/// `jobRepository.watch(jobId)` — the push-based, foreground-only event
/// stream. The subscription lives exactly as long as this provider AND the
/// app is foregrounded:
///
/// * leaving the screen disposes the provider → the subscription (and its
///   Dio cancel token) is cancelled — no stream survives the screen;
/// * the app transitioning to the background (`paused`/`hidden`/
///   `detached`) cancels the subscription immediately — zero background
///   network wake-ups;
/// * returning to the foreground (`resumed`) performs exactly ONE
///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
///   job is still non-terminal.
///
/// There is no cancel affordance (D3 — no server route): the copy says
/// processing continues; the user can only close the screen.
final class AiJobStatusControllerProvider
    extends $NotifierProvider<AiJobStatusController, AsyncValue<AiImportJob>> {
  /// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
  /// #664 battery contract D5).
  ///
  /// The ONLY SSE consumer in the app: subscribes to
  /// `jobRepository.watch(jobId)` — the push-based, foreground-only event
  /// stream. The subscription lives exactly as long as this provider AND the
  /// app is foregrounded:
  ///
  /// * leaving the screen disposes the provider → the subscription (and its
  ///   Dio cancel token) is cancelled — no stream survives the screen;
  /// * the app transitioning to the background (`paused`/`hidden`/
  ///   `detached`) cancels the subscription immediately — zero background
  ///   network wake-ups;
  /// * returning to the foreground (`resumed`) performs exactly ONE
  ///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
  ///   job is still non-terminal.
  ///
  /// There is no cancel affordance (D3 — no server route): the copy says
  /// processing continues; the user can only close the screen.
  AiJobStatusControllerProvider._({
    required AiJobStatusControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiJobStatusControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiJobStatusControllerHash();

  @override
  String toString() {
    return r'aiJobStatusControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AiJobStatusController create() => AiJobStatusController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<AiImportJob> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<AiImportJob>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AiJobStatusControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiJobStatusControllerHash() =>
    r'eb95ebc01e32d5621ac62064588e7afde7d6f536';

/// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
/// #664 battery contract D5).
///
/// The ONLY SSE consumer in the app: subscribes to
/// `jobRepository.watch(jobId)` — the push-based, foreground-only event
/// stream. The subscription lives exactly as long as this provider AND the
/// app is foregrounded:
///
/// * leaving the screen disposes the provider → the subscription (and its
///   Dio cancel token) is cancelled — no stream survives the screen;
/// * the app transitioning to the background (`paused`/`hidden`/
///   `detached`) cancels the subscription immediately — zero background
///   network wake-ups;
/// * returning to the foreground (`resumed`) performs exactly ONE
///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
///   job is still non-terminal.
///
/// There is no cancel affordance (D3 — no server route): the copy says
/// processing continues; the user can only close the screen.

final class AiJobStatusControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AiJobStatusController,
          AsyncValue<AiImportJob>,
          AsyncValue<AiImportJob>,
          AsyncValue<AiImportJob>,
          String
        > {
  AiJobStatusControllerFamily._()
    : super(
        retry: null,
        name: r'aiJobStatusControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
  /// #664 battery contract D5).
  ///
  /// The ONLY SSE consumer in the app: subscribes to
  /// `jobRepository.watch(jobId)` — the push-based, foreground-only event
  /// stream. The subscription lives exactly as long as this provider AND the
  /// app is foregrounded:
  ///
  /// * leaving the screen disposes the provider → the subscription (and its
  ///   Dio cancel token) is cancelled — no stream survives the screen;
  /// * the app transitioning to the background (`paused`/`hidden`/
  ///   `detached`) cancels the subscription immediately — zero background
  ///   network wake-ups;
  /// * returning to the foreground (`resumed`) performs exactly ONE
  ///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
  ///   job is still non-terminal.
  ///
  /// There is no cancel affordance (D3 — no server route): the copy says
  /// processing continues; the user can only close the screen.

  AiJobStatusControllerProvider call(String jobId) =>
      AiJobStatusControllerProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobStatusControllerProvider';
}

/// The job-status controller (`flutter-ai-import-workflow` task 3.2, issue
/// #664 battery contract D5).
///
/// The ONLY SSE consumer in the app: subscribes to
/// `jobRepository.watch(jobId)` — the push-based, foreground-only event
/// stream. The subscription lives exactly as long as this provider AND the
/// app is foregrounded:
///
/// * leaving the screen disposes the provider → the subscription (and its
///   Dio cancel token) is cancelled — no stream survives the screen;
/// * the app transitioning to the background (`paused`/`hidden`/
///   `detached`) cancels the subscription immediately — zero background
///   network wake-ups;
/// * returning to the foreground (`resumed`) performs exactly ONE
///   snapshot `GET /v1/ai-import/jobs/{id}` and re-subscribes only if the
///   job is still non-terminal.
///
/// There is no cancel affordance (D3 — no server route): the copy says
/// processing continues; the user can only close the screen.

abstract class _$AiJobStatusController
    extends $Notifier<AsyncValue<AiImportJob>> {
  late final _$args = ref.$arg as String;
  String get jobId => _$args;

  AsyncValue<AiImportJob> build(String jobId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AiImportJob>, AsyncValue<AiImportJob>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AiImportJob>, AsyncValue<AiImportJob>>,
              AsyncValue<AiImportJob>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The persisted apply context of a cached job row (design §2.3): the
/// apply navigation reads the episode/series from HERE, never from the
/// navigation stack. `null` context → the apply screen requires the
/// explicit episode picker.

@ProviderFor(aiJobContext)
final aiJobContextProvider = AiJobContextFamily._();

/// The persisted apply context of a cached job row (design §2.3): the
/// apply navigation reads the episode/series from HERE, never from the
/// navigation stack. `null` context → the apply screen requires the
/// explicit episode picker.

final class AiJobContextProvider
    extends
        $FunctionalProvider<
          AsyncValue<AiJobContext?>,
          AiJobContext?,
          FutureOr<AiJobContext?>
        >
    with $FutureModifier<AiJobContext?>, $FutureProvider<AiJobContext?> {
  /// The persisted apply context of a cached job row (design §2.3): the
  /// apply navigation reads the episode/series from HERE, never from the
  /// navigation stack. `null` context → the apply screen requires the
  /// explicit episode picker.
  AiJobContextProvider._({
    required AiJobContextFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiJobContextProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiJobContextHash();

  @override
  String toString() {
    return r'aiJobContextProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AiJobContext?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AiJobContext?> create(Ref ref) {
    final argument = this.argument as String;
    return aiJobContext(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiJobContextProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiJobContextHash() => r'3a778b76df48fd604dd6a3076e4e429aef4fb2c3';

/// The persisted apply context of a cached job row (design §2.3): the
/// apply navigation reads the episode/series from HERE, never from the
/// navigation stack. `null` context → the apply screen requires the
/// explicit episode picker.

final class AiJobContextFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AiJobContext?>, String> {
  AiJobContextFamily._()
    : super(
        retry: null,
        name: r'aiJobContextProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The persisted apply context of a cached job row (design §2.3): the
  /// apply navigation reads the episode/series from HERE, never from the
  /// navigation stack. `null` context → the apply screen requires the
  /// explicit episode picker.

  AiJobContextProvider call(String jobId) =>
      AiJobContextProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobContextProvider';
}

/// The job's block anchor for the in-preview episode creation: blockId from
/// the cached row (independent of the episode context — a job uploaded
/// without an episode pick still has a block, and the 294.pdf flow showed
/// the creation must not depend on a remembered context) plus the row's
/// remembered projectId (may be empty — the caller falls back to
/// `GET /v1/blocks/{id}`). `null` when the row is unknown/offline.

@ProviderFor(aiJobBlockInfo)
final aiJobBlockInfoProvider = AiJobBlockInfoFamily._();

/// The job's block anchor for the in-preview episode creation: blockId from
/// the cached row (independent of the episode context — a job uploaded
/// without an episode pick still has a block, and the 294.pdf flow showed
/// the creation must not depend on a remembered context) plus the row's
/// remembered projectId (may be empty — the caller falls back to
/// `GET /v1/blocks/{id}`). `null` when the row is unknown/offline.

final class AiJobBlockInfoProvider
    extends
        $FunctionalProvider<
          AsyncValue<({String blockId, String projectId})?>,
          ({String blockId, String projectId})?,
          FutureOr<({String blockId, String projectId})?>
        >
    with
        $FutureModifier<({String blockId, String projectId})?>,
        $FutureProvider<({String blockId, String projectId})?> {
  /// The job's block anchor for the in-preview episode creation: blockId from
  /// the cached row (independent of the episode context — a job uploaded
  /// without an episode pick still has a block, and the 294.pdf flow showed
  /// the creation must not depend on a remembered context) plus the row's
  /// remembered projectId (may be empty — the caller falls back to
  /// `GET /v1/blocks/{id}`). `null` when the row is unknown/offline.
  AiJobBlockInfoProvider._({
    required AiJobBlockInfoFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiJobBlockInfoProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiJobBlockInfoHash();

  @override
  String toString() {
    return r'aiJobBlockInfoProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<({String blockId, String projectId})?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<({String blockId, String projectId})?> create(Ref ref) {
    final argument = this.argument as String;
    return aiJobBlockInfo(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiJobBlockInfoProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiJobBlockInfoHash() => r'7aade1dfa490f1e39abe79a33f9783a3fd4666f4';

/// The job's block anchor for the in-preview episode creation: blockId from
/// the cached row (independent of the episode context — a job uploaded
/// without an episode pick still has a block, and the 294.pdf flow showed
/// the creation must not depend on a remembered context) plus the row's
/// remembered projectId (may be empty — the caller falls back to
/// `GET /v1/blocks/{id}`). `null` when the row is unknown/offline.

final class AiJobBlockInfoFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<({String blockId, String projectId})?>,
          String
        > {
  AiJobBlockInfoFamily._()
    : super(
        retry: null,
        name: r'aiJobBlockInfoProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The job's block anchor for the in-preview episode creation: blockId from
  /// the cached row (independent of the episode context — a job uploaded
  /// without an episode pick still has a block, and the 294.pdf flow showed
  /// the creation must not depend on a remembered context) plus the row's
  /// remembered projectId (may be empty — the caller falls back to
  /// `GET /v1/blocks/{id}`). `null` when the row is unknown/offline.

  AiJobBlockInfoProvider call(String jobId) =>
      AiJobBlockInfoProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobBlockInfoProvider';
}
