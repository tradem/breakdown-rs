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

String _$aiApplyControllerHash() => r'8839747c1c32fbef1a9d57de5f0350e982aab46f';

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
