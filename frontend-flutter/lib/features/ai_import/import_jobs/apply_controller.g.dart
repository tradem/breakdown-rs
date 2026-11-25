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
///
/// **Totality is part of that contract.** The function used to spell the
/// pending answer only for a `Left` Result, while the two reads above it
/// (`aiJobBlockInfoProvider`'s cached-row read and the Drift `readById`) can
/// throw: an unreadable cache then escaped this provider as an ERROR, and every
/// consumer of the gate reads a `.future` — `apply()` awaits it before the
/// first network call. A throw there is swallowed by the button's async
/// callback in a single turn (both `setState`s land before the next frame), so
/// the reviewer saw an ENABLED submit button that provably did nothing: no
/// spinner, no error, no navigation. An unreadable scope is `null` (pending),
/// exactly as documented — never an exception.

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
///
/// **Totality is part of that contract.** The function used to spell the
/// pending answer only for a `Left` Result, while the two reads above it
/// (`aiJobBlockInfoProvider`'s cached-row read and the Drift `readById`) can
/// throw: an unreadable cache then escaped this provider as an ERROR, and every
/// consumer of the gate reads a `.future` — `apply()` awaits it before the
/// first network call. A throw there is swallowed by the button's async
/// callback in a single turn (both `setState`s land before the next frame), so
/// the reviewer saw an ENABLED submit button that provably did nothing: no
/// spinner, no error, no navigation. An unreadable scope is `null` (pending),
/// exactly as documented — never an exception.

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
  ///
  /// **Totality is part of that contract.** The function used to spell the
  /// pending answer only for a `Left` Result, while the two reads above it
  /// (`aiJobBlockInfoProvider`'s cached-row read and the Drift `readById`) can
  /// throw: an unreadable cache then escaped this provider as an ERROR, and every
  /// consumer of the gate reads a `.future` — `apply()` awaits it before the
  /// first network call. A throw there is swallowed by the button's async
  /// callback in a single turn (both `setState`s land before the next frame), so
  /// the reviewer saw an ENABLED submit button that provably did nothing: no
  /// spinner, no error, no navigation. An unreadable scope is `null` (pending),
  /// exactly as documented — never an exception.
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
    r'2cede92736e0a1324d528fba505a1e1572ab5112';

/// The season a job belongs to — the authorization scope of the apply stream.
///
/// Resolved from the job's OWN scope (the cached job row's `block_id` → the
/// block's `season_id`), never from navigation state: the apply-events handler
/// gates on the job's season, so the mirror must read the same scope. `null`
/// means the scope could not be resolved (no block on the job, or the block is
/// neither cached nor readable) — the gate then stays PENDING, which disables
/// the watch instead of denying it.
///
/// **Totality is part of that contract.** The function used to spell the
/// pending answer only for a `Left` Result, while the two reads above it
/// (`aiJobBlockInfoProvider`'s cached-row read and the Drift `readById`) can
/// throw: an unreadable cache then escaped this provider as an ERROR, and every
/// consumer of the gate reads a `.future` — `apply()` awaits it before the
/// first network call. A throw there is swallowed by the button's async
/// callback in a single turn (both `setState`s land before the next frame), so
/// the reviewer saw an ENABLED submit button that provably did nothing: no
/// spinner, no error, no navigation. An unreadable scope is `null` (pending),
/// exactly as documented — never an exception.

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
  ///
  /// **Totality is part of that contract.** The function used to spell the
  /// pending answer only for a `Left` Result, while the two reads above it
  /// (`aiJobBlockInfoProvider`'s cached-row read and the Drift `readById`) can
  /// throw: an unreadable cache then escaped this provider as an ERROR, and every
  /// consumer of the gate reads a `.future` — `apply()` awaits it before the
  /// first network call. A throw there is swallowed by the button's async
  /// callback in a single turn (both `setState`s land before the next frame), so
  /// the reviewer saw an ENABLED submit button that provably did nothing: no
  /// spinner, no error, no navigation. An unreadable scope is `null` (pending),
  /// exactly as documented — never an exception.

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
///
/// **The gate never throws**, for the same reason [aiApplyJobSeasonId] never
/// does: it is awaited on the dispatch path (`apply()`, the reconciliation's
/// `gate:` callback and the progress stream), and an escaping error there is
/// invisible to the reviewer (see that provider's doc comment).

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
///
/// **The gate never throws**, for the same reason [aiApplyJobSeasonId] never
/// does: it is awaited on the dispatch path (`apply()`, the reconciliation's
/// `gate:` callback and the progress stream), and an escaping error there is
/// invisible to the reviewer (see that provider's doc comment).

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
  ///
  /// **The gate never throws**, for the same reason [aiApplyJobSeasonId] never
  /// does: it is awaited on the dispatch path (`apply()`, the reconciliation's
  /// `gate:` callback and the progress stream), and an escaping error there is
  /// invisible to the reviewer (see that provider's doc comment).
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

String _$aiApplyStreamGateHash() => r'7d17d71971310d6381ed0bc8f2d91caa4d33da7e';

/// The client-side mirror of the backend's AUTHZ-GATE on the apply-events route
/// (D6): `null` = the watch may open, otherwise the stable problem `code` the
/// card localizes (never the server `detail`).
///
/// Reads the backend-computed season predicate through
/// [checkAiImportCapability] — the same gate the AI-import upload/apply dispatch
/// uses. A failed or still-pending membership read stays `membership.pending`
/// (disabled with the waiting line, never the 403 narrative — D3).
///
/// **The gate never throws**, for the same reason [aiApplyJobSeasonId] never
/// does: it is awaited on the dispatch path (`apply()`, the reconciliation's
/// `gate:` callback and the progress stream), and an escaping error there is
/// invisible to the reviewer (see that provider's doc comment).

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
  ///
  /// **The gate never throws**, for the same reason [aiApplyJobSeasonId] never
  /// does: it is awaited on the dispatch path (`apply()`, the reconciliation's
  /// `gate:` callback and the progress stream), and an escaping error there is
  /// invisible to the reviewer (see that provider's doc comment).

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

String _$aiApplyControllerHash() => r'c8385366aea442af9d7e7134dc5828b3d23af992';

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
