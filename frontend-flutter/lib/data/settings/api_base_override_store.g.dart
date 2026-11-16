// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_base_override_store.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Runtime backend-base override (task 6.3): `null` means "no runtime
/// change since boot — use `AppConfig.apiBase`" (the persisted override, if
/// any, is already merged into the config by `bootstrap()` — task 6.1).
/// Setting it rebuilds `apiDioProvider` (same pinned `SecurityContext`) and
/// every dependent client/repository. `keepAlive` — the override outlives any
/// screen (issue #905).

@ProviderFor(RuntimeApiBase)
final runtimeApiBaseProvider = RuntimeApiBaseProvider._();

/// Runtime backend-base override (task 6.3): `null` means "no runtime
/// change since boot — use `AppConfig.apiBase`" (the persisted override, if
/// any, is already merged into the config by `bootstrap()` — task 6.1).
/// Setting it rebuilds `apiDioProvider` (same pinned `SecurityContext`) and
/// every dependent client/repository. `keepAlive` — the override outlives any
/// screen (issue #905).
final class RuntimeApiBaseProvider
    extends $NotifierProvider<RuntimeApiBase, String?> {
  /// Runtime backend-base override (task 6.3): `null` means "no runtime
  /// change since boot — use `AppConfig.apiBase`" (the persisted override, if
  /// any, is already merged into the config by `bootstrap()` — task 6.1).
  /// Setting it rebuilds `apiDioProvider` (same pinned `SecurityContext`) and
  /// every dependent client/repository. `keepAlive` — the override outlives any
  /// screen (issue #905).
  RuntimeApiBaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeApiBaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeApiBaseHash();

  @$internal
  @override
  RuntimeApiBase create() => RuntimeApiBase();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$runtimeApiBaseHash() => r'6f38f3868d4747acacdb34e0465e7cf33a672f52';

/// Runtime backend-base override (task 6.3): `null` means "no runtime
/// change since boot — use `AppConfig.apiBase`" (the persisted override, if
/// any, is already merged into the config by `bootstrap()` — task 6.1).
/// Setting it rebuilds `apiDioProvider` (same pinned `SecurityContext`) and
/// every dependent client/repository. `keepAlive` — the override outlives any
/// screen (issue #905).

abstract class _$RuntimeApiBase extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
