// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_config_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// List-first config discovery (D2): `GET /v1/ai-import/config` (the
/// caller's configs, newest-first) is authoritative. Tests override this
/// seam.

@ProviderFor(aiConfigDiscovery)
final aiConfigDiscoveryProvider = AiConfigDiscoveryProvider._();

/// List-first config discovery (D2): `GET /v1/ai-import/config` (the
/// caller's configs, newest-first) is authoritative. Tests override this
/// seam.

final class AiConfigDiscoveryProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<AiConfigView>>>,
          Result<List<AiConfigView>>,
          FutureOr<Result<List<AiConfigView>>>
        >
    with
        $FutureModifier<Result<List<AiConfigView>>>,
        $FutureProvider<Result<List<AiConfigView>>> {
  /// List-first config discovery (D2): `GET /v1/ai-import/config` (the
  /// caller's configs, newest-first) is authoritative. Tests override this
  /// seam.
  AiConfigDiscoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigDiscoveryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigDiscoveryHash();

  @$internal
  @override
  $FutureProviderElement<Result<List<AiConfigView>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<AiConfigView>>> create(Ref ref) {
    return aiConfigDiscovery(ref);
  }
}

String _$aiConfigDiscoveryHash() => r'029b979ce2384a80148f3846c6ac5924c230ff3a';

/// The remembered hand-off state for the authenticated subject (task 1.3).

@ProviderFor(aiImportHandoff)
final aiImportHandoffProvider = AiImportHandoffProvider._();

/// The remembered hand-off state for the authenticated subject (task 1.3).

final class AiImportHandoffProvider
    extends
        $FunctionalProvider<
          AsyncValue<AiImportHandoffState>,
          AiImportHandoffState,
          FutureOr<AiImportHandoffState>
        >
    with
        $FutureModifier<AiImportHandoffState>,
        $FutureProvider<AiImportHandoffState> {
  /// The remembered hand-off state for the authenticated subject (task 1.3).
  AiImportHandoffProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportHandoffProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportHandoffHash();

  @$internal
  @override
  $FutureProviderElement<AiImportHandoffState> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AiImportHandoffState> create(Ref ref) {
    return aiImportHandoff(ref);
  }
}

String _$aiImportHandoffHash() => r'1a2a6a11e23e2696fdc421ad0a0472507db9e0e5';

/// Provider/model discovery (D7): the curated catalog from the routes —
/// no hardcoded ids. A 404 (AI import disabled) or a transport failure
/// degrades honestly in the screen.

@ProviderFor(aiProviders)
final aiProvidersProvider = AiProvidersProvider._();

/// Provider/model discovery (D7): the curated catalog from the routes —
/// no hardcoded ids. A 404 (AI import disabled) or a transport failure
/// degrades honestly in the screen.

final class AiProvidersProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<AiProviderInfo>>>,
          Result<List<AiProviderInfo>>,
          FutureOr<Result<List<AiProviderInfo>>>
        >
    with
        $FutureModifier<Result<List<AiProviderInfo>>>,
        $FutureProvider<Result<List<AiProviderInfo>>> {
  /// Provider/model discovery (D7): the curated catalog from the routes —
  /// no hardcoded ids. A 404 (AI import disabled) or a transport failure
  /// degrades honestly in the screen.
  AiProvidersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiProvidersProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiProvidersHash();

  @$internal
  @override
  $FutureProviderElement<Result<List<AiProviderInfo>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<AiProviderInfo>>> create(Ref ref) {
    return aiProviders(ref);
  }
}

String _$aiProvidersHash() => r'1df616f5d772d91244a449d758d423fd2b4d6e15';

/// The selected provider's model set. A 422 (unknown provider) surfaces
/// as `Err` — the "provider unavailable" degradation.

@ProviderFor(aiProviderModels)
final aiProviderModelsProvider = AiProviderModelsFamily._();

/// The selected provider's model set. A 422 (unknown provider) surfaces
/// as `Err` — the "provider unavailable" degradation.

final class AiProviderModelsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<ModelInfo>>>,
          Result<List<ModelInfo>>,
          FutureOr<Result<List<ModelInfo>>>
        >
    with
        $FutureModifier<Result<List<ModelInfo>>>,
        $FutureProvider<Result<List<ModelInfo>>> {
  /// The selected provider's model set. A 422 (unknown provider) surfaces
  /// as `Err` — the "provider unavailable" degradation.
  AiProviderModelsProvider._({
    required AiProviderModelsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiProviderModelsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiProviderModelsHash();

  @override
  String toString() {
    return r'aiProviderModelsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<ModelInfo>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<ModelInfo>>> create(Ref ref) {
    final argument = this.argument as String;
    return aiProviderModels(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiProviderModelsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiProviderModelsHash() => r'd63717e301875b30e2feedda8f7d4294df8513fe';

/// The selected provider's model set. A 422 (unknown provider) surfaces
/// as `Err` — the "provider unavailable" degradation.

final class AiProviderModelsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Result<List<ModelInfo>>>, String> {
  AiProviderModelsFamily._()
    : super(
        retry: null,
        name: r'aiProviderModelsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The selected provider's model set. A 422 (unknown provider) surfaces
  /// as `Err` — the "provider unavailable" degradation.

  AiProviderModelsProvider call(String key) =>
      AiProviderModelsProvider._(argument: key, from: this);

  @override
  String toString() => r'aiProviderModelsProvider';
}

/// The AI-import configuration controller (`flutter-ai-config` task 2.1).
///
/// AUTHZ-GATE exception (D4, documented): the backend gates AI config and
/// credential endpoints on a credential-role policy that is NOT exposed as
/// a season capability, so no client-side capability pre-gate can mirror
/// it. The only client-side gate here is the authenticated session
/// (session-only); a 403 renders the localized "administrator role
/// required" narrative — the call itself is denied server-side.

@ProviderFor(AiConfigController)
final aiConfigControllerProvider = AiConfigControllerProvider._();

/// The AI-import configuration controller (`flutter-ai-config` task 2.1).
///
/// AUTHZ-GATE exception (D4, documented): the backend gates AI config and
/// credential endpoints on a credential-role policy that is NOT exposed as
/// a season capability, so no client-side capability pre-gate can mirror
/// it. The only client-side gate here is the authenticated session
/// (session-only); a 403 renders the localized "administrator role
/// required" narrative — the call itself is denied server-side.
final class AiConfigControllerProvider
    extends $NotifierProvider<AiConfigController, AiConfigScreenState> {
  /// The AI-import configuration controller (`flutter-ai-config` task 2.1).
  ///
  /// AUTHZ-GATE exception (D4, documented): the backend gates AI config and
  /// credential endpoints on a credential-role policy that is NOT exposed as
  /// a season capability, so no client-side capability pre-gate can mirror
  /// it. The only client-side gate here is the authenticated session
  /// (session-only); a 403 renders the localized "administrator role
  /// required" narrative — the call itself is denied server-side.
  AiConfigControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigControllerHash();

  @$internal
  @override
  AiConfigController create() => AiConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiConfigScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiConfigScreenState>(value),
    );
  }
}

String _$aiConfigControllerHash() =>
    r'99c41dbb18c266b9311aad9de2c3a2ec6d83b552';

/// The AI-import configuration controller (`flutter-ai-config` task 2.1).
///
/// AUTHZ-GATE exception (D4, documented): the backend gates AI config and
/// credential endpoints on a credential-role policy that is NOT exposed as
/// a season capability, so no client-side capability pre-gate can mirror
/// it. The only client-side gate here is the authenticated session
/// (session-only); a 403 renders the localized "administrator role
/// required" narrative — the call itself is denied server-side.

abstract class _$AiConfigController extends $Notifier<AiConfigScreenState> {
  AiConfigScreenState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AiConfigScreenState, AiConfigScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AiConfigScreenState, AiConfigScreenState>,
              AiConfigScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
