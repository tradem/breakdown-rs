// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// AI-import **configuration** repository: owns the discovery, credential
/// hand-off, config CRUD and rollback routes (task 1.1).

@ProviderFor(aiConfigRepository)
final aiConfigRepositoryProvider = AiConfigRepositoryProvider._();

/// AI-import **configuration** repository: owns the discovery, credential
/// hand-off, config CRUD and rollback routes (task 1.1).

final class AiConfigRepositoryProvider
    extends
        $FunctionalProvider<
          AiConfigRepository,
          AiConfigRepository,
          AiConfigRepository
        >
    with $Provider<AiConfigRepository> {
  /// AI-import **configuration** repository: owns the discovery, credential
  /// hand-off, config CRUD and rollback routes (task 1.1).
  AiConfigRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiConfigRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiConfigRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiConfigRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiConfigRepository create(Ref ref) {
    return aiConfigRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiConfigRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiConfigRepository>(value),
    );
  }
}

String _$aiConfigRepositoryHash() =>
    r'8e196cfd9e8f3835fe747367bbc8ce202b395174';

/// AI-import **workflow** repository: owns the raw-body uploads, job
/// status, preview and apply routes plus the Drift job cache (tasks
/// 1.2/1.4).

@ProviderFor(aiImportRepository)
final aiImportRepositoryProvider = AiImportRepositoryProvider._();

/// AI-import **workflow** repository: owns the raw-body uploads, job
/// status, preview and apply routes plus the Drift job cache (tasks
/// 1.2/1.4).

final class AiImportRepositoryProvider
    extends
        $FunctionalProvider<
          AiImportRepository,
          AiImportRepository,
          AiImportRepository
        >
    with $Provider<AiImportRepository> {
  /// AI-import **workflow** repository: owns the raw-body uploads, job
  /// status, preview and apply routes plus the Drift job cache (tasks
  /// 1.2/1.4).
  AiImportRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiImportRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiImportRepository create(Ref ref) {
    return aiImportRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiImportRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiImportRepository>(value),
    );
  }
}

String _$aiImportRepositoryHash() =>
    r'90fd00af647f7b508b5511460868546341aef2bc';

/// The caller's configured AI naming for the About-AI disclosure screen
/// (EU AI Act Art. 50, issue #538): provider + assistant model — NON-secret
/// wire values only (never the vault reference, never prompt texts). `null`
/// when no configuration exists or discovery fails: the disclosure screen
/// renders its honest "unconfigured" state and NEVER invents a name.

@ProviderFor(configuredAiNaming)
final configuredAiNamingProvider = ConfiguredAiNamingProvider._();

/// The caller's configured AI naming for the About-AI disclosure screen
/// (EU AI Act Art. 50, issue #538): provider + assistant model — NON-secret
/// wire values only (never the vault reference, never prompt texts). `null`
/// when no configuration exists or discovery fails: the disclosure screen
/// renders its honest "unconfigured" state and NEVER invents a name.

final class ConfiguredAiNamingProvider
    extends
        $FunctionalProvider<
          AsyncValue<AiConfigView?>,
          AiConfigView?,
          FutureOr<AiConfigView?>
        >
    with $FutureModifier<AiConfigView?>, $FutureProvider<AiConfigView?> {
  /// The caller's configured AI naming for the About-AI disclosure screen
  /// (EU AI Act Art. 50, issue #538): provider + assistant model — NON-secret
  /// wire values only (never the vault reference, never prompt texts). `null`
  /// when no configuration exists or discovery fails: the disclosure screen
  /// renders its honest "unconfigured" state and NEVER invents a name.
  ConfiguredAiNamingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'configuredAiNamingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$configuredAiNamingHash();

  @$internal
  @override
  $FutureProviderElement<AiConfigView?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AiConfigView?> create(Ref ref) {
    return configuredAiNaming(ref);
  }
}

String _$configuredAiNamingHash() =>
    r'bff5d1984b6df8638c56b0249a75445dd73386ed';
