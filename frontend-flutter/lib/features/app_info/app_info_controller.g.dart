// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_info_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Meta repository for the About screen (issue #656): serves
/// `GET /v1/meta/versions` through the generated client. Tests override the
/// [metaVersionsProvider] fetch, so this wiring stays production-only.

@ProviderFor(metaRepository)
final metaRepositoryProvider = MetaRepositoryProvider._();

/// Meta repository for the About screen (issue #656): serves
/// `GET /v1/meta/versions` through the generated client. Tests override the
/// [metaVersionsProvider] fetch, so this wiring stays production-only.

final class MetaRepositoryProvider
    extends $FunctionalProvider<MetaRepository, MetaRepository, MetaRepository>
    with $Provider<MetaRepository> {
  /// Meta repository for the About screen (issue #656): serves
  /// `GET /v1/meta/versions` through the generated client. Tests override the
  /// [metaVersionsProvider] fetch, so this wiring stays production-only.
  MetaRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'metaRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$metaRepositoryHash();

  @$internal
  @override
  $ProviderElement<MetaRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MetaRepository create(Ref ref) {
    return metaRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MetaRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MetaRepository>(value),
    );
  }
}

String _$metaRepositoryHash() => r'9fc5e1f21df23696ade4e1e6a77861727a4aebc8';

/// Backend workspace crate versions for the About screen.
///
/// The repository never throws (Result discipline); this feature-layer
/// adapter converts the `Left(ProblemError)` into the provider's async error
/// so `ref.watch` surfaces a clean `AsyncValue.error` — the screen degrades
/// gracefully, it never crashes on a failed fetch.

@ProviderFor(metaVersions)
final metaVersionsProvider = MetaVersionsProvider._();

/// Backend workspace crate versions for the About screen.
///
/// The repository never throws (Result discipline); this feature-layer
/// adapter converts the `Left(ProblemError)` into the provider's async error
/// so `ref.watch` surfaces a clean `AsyncValue.error` — the screen degrades
/// gracefully, it never crashes on a failed fetch.

final class MetaVersionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<MetaVersionsResponse>,
          MetaVersionsResponse,
          FutureOr<MetaVersionsResponse>
        >
    with
        $FutureModifier<MetaVersionsResponse>,
        $FutureProvider<MetaVersionsResponse> {
  /// Backend workspace crate versions for the About screen.
  ///
  /// The repository never throws (Result discipline); this feature-layer
  /// adapter converts the `Left(ProblemError)` into the provider's async error
  /// so `ref.watch` surfaces a clean `AsyncValue.error` — the screen degrades
  /// gracefully, it never crashes on a failed fetch.
  MetaVersionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'metaVersionsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$metaVersionsHash();

  @$internal
  @override
  $FutureProviderElement<MetaVersionsResponse> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MetaVersionsResponse> create(Ref ref) {
    return metaVersions(ref);
  }
}

String _$metaVersionsHash() => r'806cf1c0b6931ed11164ebb768bac2db6fd3e946';
