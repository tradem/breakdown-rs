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
