// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The typed preview fetch (D1). NEVER cached (regenerable, potentially
/// large — design §3): the provider is auto-dispose and re-armed by the
/// refresh affordance. Tests override this seam.

@ProviderFor(aiPreview)
final aiPreviewProvider = AiPreviewFamily._();

/// The typed preview fetch (D1). NEVER cached (regenerable, potentially
/// large — design §3): the provider is auto-dispose and re-armed by the
/// refresh affordance. Tests override this seam.

final class AiPreviewProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<AiImportPreviewResponse>>,
          Result<AiImportPreviewResponse>,
          FutureOr<Result<AiImportPreviewResponse>>
        >
    with
        $FutureModifier<Result<AiImportPreviewResponse>>,
        $FutureProvider<Result<AiImportPreviewResponse>> {
  /// The typed preview fetch (D1). NEVER cached (regenerable, potentially
  /// large — design §3): the provider is auto-dispose and re-armed by the
  /// refresh affordance. Tests override this seam.
  AiPreviewProvider._({
    required AiPreviewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiPreviewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiPreviewHash();

  @override
  String toString() {
    return r'aiPreviewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<AiImportPreviewResponse>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<AiImportPreviewResponse>> create(Ref ref) {
    final argument = this.argument as String;
    return aiPreview(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiPreviewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiPreviewHash() => r'70821ab6e20bbb9e197824f94708171db01e5b0b';

/// The typed preview fetch (D1). NEVER cached (regenerable, potentially
/// large — design §3): the provider is auto-dispose and re-armed by the
/// refresh affordance. Tests override this seam.

final class AiPreviewFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<AiImportPreviewResponse>>,
          String
        > {
  AiPreviewFamily._()
    : super(
        retry: null,
        name: r'aiPreviewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The typed preview fetch (D1). NEVER cached (regenerable, potentially
  /// large — design §3): the provider is auto-dispose and re-armed by the
  /// refresh affordance. Tests override this seam.

  AiPreviewProvider call(String jobId) =>
      AiPreviewProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiPreviewProvider';
}

/// Live progress of the apply run in flight (issue #762).
///
/// Subscribed by the apply screen only while its `POST` is out, so the stream
/// exists exactly as long as the run does — no background subscription, no
/// polling. The stream is a second SSE channel because an apply runs against a
/// job that is already `succeeded` (its own stream has closed):
/// `GET /v1/ai-import/jobs/{id}/apply-events`.
///
/// Every frame is folded into an [AiApplyRunState]: a progress frame becomes
/// [AiApplyRunRunning] (remembering it), the run's final `null` becomes
/// [AiApplyRunFinished] (the remembered run, not "nothing happened"), and a
/// `Left` becomes [AiApplyRunFailed]. `null` from the stream *before* any run
/// stays [AiApplyRunIdle].

@ProviderFor(aiApplyRun)
final aiApplyRunProvider = AiApplyRunFamily._();

/// Live progress of the apply run in flight (issue #762).
///
/// Subscribed by the apply screen only while its `POST` is out, so the stream
/// exists exactly as long as the run does — no background subscription, no
/// polling. The stream is a second SSE channel because an apply runs against a
/// job that is already `succeeded` (its own stream has closed):
/// `GET /v1/ai-import/jobs/{id}/apply-events`.
///
/// Every frame is folded into an [AiApplyRunState]: a progress frame becomes
/// [AiApplyRunRunning] (remembering it), the run's final `null` becomes
/// [AiApplyRunFinished] (the remembered run, not "nothing happened"), and a
/// `Left` becomes [AiApplyRunFailed]. `null` from the stream *before* any run
/// stays [AiApplyRunIdle].

final class AiApplyRunProvider
    extends
        $FunctionalProvider<
          AsyncValue<AiApplyRunState>,
          AiApplyRunState,
          Stream<AiApplyRunState>
        >
    with $FutureModifier<AiApplyRunState>, $StreamProvider<AiApplyRunState> {
  /// Live progress of the apply run in flight (issue #762).
  ///
  /// Subscribed by the apply screen only while its `POST` is out, so the stream
  /// exists exactly as long as the run does — no background subscription, no
  /// polling. The stream is a second SSE channel because an apply runs against a
  /// job that is already `succeeded` (its own stream has closed):
  /// `GET /v1/ai-import/jobs/{id}/apply-events`.
  ///
  /// Every frame is folded into an [AiApplyRunState]: a progress frame becomes
  /// [AiApplyRunRunning] (remembering it), the run's final `null` becomes
  /// [AiApplyRunFinished] (the remembered run, not "nothing happened"), and a
  /// `Left` becomes [AiApplyRunFailed]. `null` from the stream *before* any run
  /// stays [AiApplyRunIdle].
  AiApplyRunProvider._({
    required AiApplyRunFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiApplyRunProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiApplyRunHash();

  @override
  String toString() {
    return r'aiApplyRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<AiApplyRunState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AiApplyRunState> create(Ref ref) {
    final argument = this.argument as String;
    return aiApplyRun(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiApplyRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiApplyRunHash() => r'1019fd76df943a9d9b3654024457f6d28704bb1a';

/// Live progress of the apply run in flight (issue #762).
///
/// Subscribed by the apply screen only while its `POST` is out, so the stream
/// exists exactly as long as the run does — no background subscription, no
/// polling. The stream is a second SSE channel because an apply runs against a
/// job that is already `succeeded` (its own stream has closed):
/// `GET /v1/ai-import/jobs/{id}/apply-events`.
///
/// Every frame is folded into an [AiApplyRunState]: a progress frame becomes
/// [AiApplyRunRunning] (remembering it), the run's final `null` becomes
/// [AiApplyRunFinished] (the remembered run, not "nothing happened"), and a
/// `Left` becomes [AiApplyRunFailed]. `null` from the stream *before* any run
/// stays [AiApplyRunIdle].

final class AiApplyRunFamily extends $Family
    with $FunctionalFamilyOverride<Stream<AiApplyRunState>, String> {
  AiApplyRunFamily._()
    : super(
        retry: null,
        name: r'aiApplyRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Live progress of the apply run in flight (issue #762).
  ///
  /// Subscribed by the apply screen only while its `POST` is out, so the stream
  /// exists exactly as long as the run does — no background subscription, no
  /// polling. The stream is a second SSE channel because an apply runs against a
  /// job that is already `succeeded` (its own stream has closed):
  /// `GET /v1/ai-import/jobs/{id}/apply-events`.
  ///
  /// Every frame is folded into an [AiApplyRunState]: a progress frame becomes
  /// [AiApplyRunRunning] (remembering it), the run's final `null` becomes
  /// [AiApplyRunFinished] (the remembered run, not "nothing happened"), and a
  /// `Left` becomes [AiApplyRunFailed]. `null` from the stream *before* any run
  /// stays [AiApplyRunIdle].

  AiApplyRunProvider call(String jobId) =>
      AiApplyRunProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiApplyRunProvider';
}

/// The season a job belongs to — the authorization scope of the apply stream.
///
/// Resolved from the job's OWN scope (the cached job row's `block_id` → the
/// block's `season_id`), never from navigation state: the apply-events handler
/// gates on the job's season, so the mirror must read the same scope. `null`
/// means the scope could not be resolved (no block on the job, or the block is
/// neither cached nor readable) — the gate then stays PENDING, which disables
/// the watch instead of denying it.

@ProviderFor(aiApplyJobSeasonId)
final aiApplyJobSeasonIdProvider = AiApplyJobSeasonIdFamily._();

/// The season a job belongs to — the authorization scope of the apply stream.
///
/// Resolved from the job's OWN scope (the cached job row's `block_id` → the
/// block's `season_id`), never from navigation state: the apply-events handler
/// gates on the job's season, so the mirror must read the same scope. `null`
/// means the scope could not be resolved (no block on the job, or the block is
/// neither cached nor readable) — the gate then stays PENDING, which disables
/// the watch instead of denying it.

final class AiApplyJobSeasonIdProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// The season a job belongs to — the authorization scope of the apply stream.
  ///
  /// Resolved from the job's OWN scope (the cached job row's `block_id` → the
  /// block's `season_id`), never from navigation state: the apply-events handler
  /// gates on the job's season, so the mirror must read the same scope. `null`
  /// means the scope could not be resolved (no block on the job, or the block is
  /// neither cached nor readable) — the gate then stays PENDING, which disables
  /// the watch instead of denying it.
  AiApplyJobSeasonIdProvider._({
    required AiApplyJobSeasonIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiApplyJobSeasonIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiApplyJobSeasonIdHash();

  @override
  String toString() {
    return r'aiApplyJobSeasonIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    final argument = this.argument as String;
    return aiApplyJobSeasonId(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiApplyJobSeasonIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiApplyJobSeasonIdHash() =>
    r'9ee64fd42ef12ffba10f4cd21d19ce646bb1a965';

/// The season a job belongs to — the authorization scope of the apply stream.
///
/// Resolved from the job's OWN scope (the cached job row's `block_id` → the
/// block's `season_id`), never from navigation state: the apply-events handler
/// gates on the job's season, so the mirror must read the same scope. `null`
/// means the scope could not be resolved (no block on the job, or the block is
/// neither cached nor readable) — the gate then stays PENDING, which disables
/// the watch instead of denying it.

final class AiApplyJobSeasonIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String?>, String> {
  AiApplyJobSeasonIdFamily._()
    : super(
        retry: null,
        name: r'aiApplyJobSeasonIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The season a job belongs to — the authorization scope of the apply stream.
  ///
  /// Resolved from the job's OWN scope (the cached job row's `block_id` → the
  /// block's `season_id`), never from navigation state: the apply-events handler
  /// gates on the job's season, so the mirror must read the same scope. `null`
  /// means the scope could not be resolved (no block on the job, or the block is
  /// neither cached nor readable) — the gate then stays PENDING, which disables
  /// the watch instead of denying it.

  AiApplyJobSeasonIdProvider call(String jobId) =>
      AiApplyJobSeasonIdProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiApplyJobSeasonIdProvider';
}

/// The client-side mirror of the backend's AUTHZ-GATE on the apply-events route
/// (D6): `null` = the watch may open, otherwise the stable problem `code` the
/// card localizes (never the server `detail`).
///
/// Reads the backend-computed season predicate through
/// [checkAiImportCapability] — the same gate the AI-import upload/apply dispatch
/// uses. A failed or still-pending membership read stays `membership.pending`
/// (disabled with the waiting line, never the 403 narrative — D3).

@ProviderFor(aiApplyStreamGate)
final aiApplyStreamGateProvider = AiApplyStreamGateFamily._();

/// The client-side mirror of the backend's AUTHZ-GATE on the apply-events route
/// (D6): `null` = the watch may open, otherwise the stable problem `code` the
/// card localizes (never the server `detail`).
///
/// Reads the backend-computed season predicate through
/// [checkAiImportCapability] — the same gate the AI-import upload/apply dispatch
/// uses. A failed or still-pending membership read stays `membership.pending`
/// (disabled with the waiting line, never the 403 narrative — D3).

final class AiApplyStreamGateProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProblemError?>,
          ProblemError?,
          FutureOr<ProblemError?>
        >
    with $FutureModifier<ProblemError?>, $FutureProvider<ProblemError?> {
  /// The client-side mirror of the backend's AUTHZ-GATE on the apply-events route
  /// (D6): `null` = the watch may open, otherwise the stable problem `code` the
  /// card localizes (never the server `detail`).
  ///
  /// Reads the backend-computed season predicate through
  /// [checkAiImportCapability] — the same gate the AI-import upload/apply dispatch
  /// uses. A failed or still-pending membership read stays `membership.pending`
  /// (disabled with the waiting line, never the 403 narrative — D3).
  AiApplyStreamGateProvider._({
    required AiApplyStreamGateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiApplyStreamGateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiApplyStreamGateHash();

  @override
  String toString() {
    return r'aiApplyStreamGateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ProblemError?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ProblemError?> create(Ref ref) {
    final argument = this.argument as String;
    return aiApplyStreamGate(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiApplyStreamGateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiApplyStreamGateHash() => r'6d306e49940c6ed09affeae99bdc7711a9e9b20f';

/// The client-side mirror of the backend's AUTHZ-GATE on the apply-events route
/// (D6): `null` = the watch may open, otherwise the stable problem `code` the
/// card localizes (never the server `detail`).
///
/// Reads the backend-computed season predicate through
/// [checkAiImportCapability] — the same gate the AI-import upload/apply dispatch
/// uses. A failed or still-pending membership read stays `membership.pending`
/// (disabled with the waiting line, never the 403 narrative — D3).

final class AiApplyStreamGateFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ProblemError?>, String> {
  AiApplyStreamGateFamily._()
    : super(
        retry: null,
        name: r'aiApplyStreamGateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The client-side mirror of the backend's AUTHZ-GATE on the apply-events route
  /// (D6): `null` = the watch may open, otherwise the stable problem `code` the
  /// card localizes (never the server `detail`).
  ///
  /// Reads the backend-computed season predicate through
  /// [checkAiImportCapability] — the same gate the AI-import upload/apply dispatch
  /// uses. A failed or still-pending membership read stays `membership.pending`
  /// (disabled with the waiting line, never the 403 narrative — D3).

  AiApplyStreamGateProvider call(String jobId) =>
      AiApplyStreamGateProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiApplyStreamGateProvider';
}

/// The apply controller (task 4.2): builds + submits the mappings.

@ProviderFor(AiApplyController)
final aiApplyControllerProvider = AiApplyControllerFamily._();

/// The apply controller (task 4.2): builds + submits the mappings.
final class AiApplyControllerProvider
    extends $NotifierProvider<AiApplyController, AiApplyState> {
  /// The apply controller (task 4.2): builds + submits the mappings.
  AiApplyControllerProvider._({
    required AiApplyControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiApplyControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiApplyControllerHash();

  @override
  String toString() {
    return r'aiApplyControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AiApplyController create() => AiApplyController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiApplyState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiApplyState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AiApplyControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiApplyControllerHash() => r'f3d56878ef591a732975eafd9f088842939945bd';

/// The apply controller (task 4.2): builds + submits the mappings.

final class AiApplyControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AiApplyController,
          AiApplyState,
          AiApplyState,
          AiApplyState,
          String
        > {
  AiApplyControllerFamily._()
    : super(
        retry: null,
        name: r'aiApplyControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The apply controller (task 4.2): builds + submits the mappings.

  AiApplyControllerProvider call(String jobId) =>
      AiApplyControllerProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiApplyControllerProvider';
}

/// The apply controller (task 4.2): builds + submits the mappings.

abstract class _$AiApplyController extends $Notifier<AiApplyState> {
  late final _$args = ref.$arg as String;
  String get jobId => _$args;

  AiApplyState build(String jobId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AiApplyState, AiApplyState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AiApplyState, AiApplyState>,
              AiApplyState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
