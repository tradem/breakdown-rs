// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_status_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The job-status controller (`flutter-ai-import-workflow` task 3.2).
///
/// Subscribes to `jobRepository.watch(jobId)` — the bounded,
/// foreground-only backoff watch (D5). The subscription lives exactly as
/// long as this provider: leaving the screen disposes the provider, which
/// cancels the subscription and STOPS the watch (unsubscribe stop);
/// re-entering re-arms it. Terminal statuses end the stream by
/// themselves. There is no cancel affordance (D3 — no server route): the
/// copy says processing continues; the user can only close the screen.

@ProviderFor(AiJobStatusController)
final aiJobStatusControllerProvider = AiJobStatusControllerFamily._();

/// The job-status controller (`flutter-ai-import-workflow` task 3.2).
///
/// Subscribes to `jobRepository.watch(jobId)` — the bounded,
/// foreground-only backoff watch (D5). The subscription lives exactly as
/// long as this provider: leaving the screen disposes the provider, which
/// cancels the subscription and STOPS the watch (unsubscribe stop);
/// re-entering re-arms it. Terminal statuses end the stream by
/// themselves. There is no cancel affordance (D3 — no server route): the
/// copy says processing continues; the user can only close the screen.
final class AiJobStatusControllerProvider
    extends $NotifierProvider<AiJobStatusController, AsyncValue<AiImportJob>> {
  /// The job-status controller (`flutter-ai-import-workflow` task 3.2).
  ///
  /// Subscribes to `jobRepository.watch(jobId)` — the bounded,
  /// foreground-only backoff watch (D5). The subscription lives exactly as
  /// long as this provider: leaving the screen disposes the provider, which
  /// cancels the subscription and STOPS the watch (unsubscribe stop);
  /// re-entering re-arms it. Terminal statuses end the stream by
  /// themselves. There is no cancel affordance (D3 — no server route): the
  /// copy says processing continues; the user can only close the screen.
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
    r'130956e28ebd51126fa76a175731c5bf4dd13662';

/// The job-status controller (`flutter-ai-import-workflow` task 3.2).
///
/// Subscribes to `jobRepository.watch(jobId)` — the bounded,
/// foreground-only backoff watch (D5). The subscription lives exactly as
/// long as this provider: leaving the screen disposes the provider, which
/// cancels the subscription and STOPS the watch (unsubscribe stop);
/// re-entering re-arms it. Terminal statuses end the stream by
/// themselves. There is no cancel affordance (D3 — no server route): the
/// copy says processing continues; the user can only close the screen.

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

  /// The job-status controller (`flutter-ai-import-workflow` task 3.2).
  ///
  /// Subscribes to `jobRepository.watch(jobId)` — the bounded,
  /// foreground-only backoff watch (D5). The subscription lives exactly as
  /// long as this provider: leaving the screen disposes the provider, which
  /// cancels the subscription and STOPS the watch (unsubscribe stop);
  /// re-entering re-arms it. Terminal statuses end the stream by
  /// themselves. There is no cancel affordance (D3 — no server route): the
  /// copy says processing continues; the user can only close the screen.

  AiJobStatusControllerProvider call(String jobId) =>
      AiJobStatusControllerProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobStatusControllerProvider';
}

/// The job-status controller (`flutter-ai-import-workflow` task 3.2).
///
/// Subscribes to `jobRepository.watch(jobId)` — the bounded,
/// foreground-only backoff watch (D5). The subscription lives exactly as
/// long as this provider: leaving the screen disposes the provider, which
/// cancels the subscription and STOPS the watch (unsubscribe stop);
/// re-entering re-arms it. Terminal statuses end the stream by
/// themselves. There is no cancel affordance (D3 — no server route): the
/// copy says processing continues; the user can only close the screen.

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

String _$aiJobContextHash() => r'834863260818c48cd421a76ae482211fb53df9ea';

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
