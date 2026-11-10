// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capabilities_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The capabilities transport, built from the shared pinned-CA client
/// (single Dio, single token interceptor — same seam as every other
/// `data/` repository).

@ProviderFor(capabilitiesRepository)
final capabilitiesRepositoryProvider = CapabilitiesRepositoryProvider._();

/// The capabilities transport, built from the shared pinned-CA client
/// (single Dio, single token interceptor — same seam as every other
/// `data/` repository).

final class CapabilitiesRepositoryProvider
    extends
        $FunctionalProvider<
          CapabilitiesRepository,
          CapabilitiesRepository,
          CapabilitiesRepository
        >
    with $Provider<CapabilitiesRepository> {
  /// The capabilities transport, built from the shared pinned-CA client
  /// (single Dio, single token interceptor — same seam as every other
  /// `data/` repository).
  CapabilitiesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'capabilitiesRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$capabilitiesRepositoryHash();

  @$internal
  @override
  $ProviderElement<CapabilitiesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CapabilitiesRepository create(Ref ref) {
    return capabilitiesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CapabilitiesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CapabilitiesRepository>(value),
    );
  }
}

String _$capabilitiesRepositoryHash() =>
    r'54ece3bc3d15bfbc4f00b0173a0fee74c7fd15a0';
