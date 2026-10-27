// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfit_detail_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Foreground-only variant watch for one look's fitting photos: bounded
/// backoff over `GET /v1/outfits/{id}` until every variant is terminal; the
/// subscription dies with the screen (no background polling).

@ProviderFor(outfitPhotoWatch)
final outfitPhotoWatchProvider = OutfitPhotoWatchFamily._();

/// Foreground-only variant watch for one look's fitting photos: bounded
/// backoff over `GET /v1/outfits/{id}` until every variant is terminal; the
/// subscription dies with the screen (no background polling).

final class OutfitPhotoWatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<PhotoWatchEvent<OutfitView>>,
          PhotoWatchEvent<OutfitView>,
          Stream<PhotoWatchEvent<OutfitView>>
        >
    with
        $FutureModifier<PhotoWatchEvent<OutfitView>>,
        $StreamProvider<PhotoWatchEvent<OutfitView>> {
  /// Foreground-only variant watch for one look's fitting photos: bounded
  /// backoff over `GET /v1/outfits/{id}` until every variant is terminal; the
  /// subscription dies with the screen (no background polling).
  OutfitPhotoWatchProvider._({
    required OutfitPhotoWatchFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'outfitPhotoWatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$outfitPhotoWatchHash();

  @override
  String toString() {
    return r'outfitPhotoWatchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<PhotoWatchEvent<OutfitView>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<PhotoWatchEvent<OutfitView>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return outfitPhotoWatch(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is OutfitPhotoWatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$outfitPhotoWatchHash() => r'35368f21faca232c38a0af7a45367521726100e2';

/// Foreground-only variant watch for one look's fitting photos: bounded
/// backoff over `GET /v1/outfits/{id}` until every variant is terminal; the
/// subscription dies with the screen (no background polling).

final class OutfitPhotoWatchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<PhotoWatchEvent<OutfitView>>,
          (String, String)
        > {
  OutfitPhotoWatchFamily._()
    : super(
        retry: null,
        name: r'outfitPhotoWatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Foreground-only variant watch for one look's fitting photos: bounded
  /// backoff over `GET /v1/outfits/{id}` until every variant is terminal; the
  /// subscription dies with the screen (no background polling).

  OutfitPhotoWatchProvider call(String characterId, String outfitId) =>
      OutfitPhotoWatchProvider._(argument: (characterId, outfitId), from: this);

  @override
  String toString() => r'outfitPhotoWatchProvider';
}
