// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_detail_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Foreground-only variant watch for one costume (D5): bounded-backoff
/// costume refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

@ProviderFor(costumePhotoWatch)
final costumePhotoWatchProvider = CostumePhotoWatchFamily._();

/// Foreground-only variant watch for one costume (D5): bounded-backoff
/// costume refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

final class CostumePhotoWatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<PhotoWatchEvent>,
          PhotoWatchEvent,
          Stream<PhotoWatchEvent>
        >
    with $FutureModifier<PhotoWatchEvent>, $StreamProvider<PhotoWatchEvent> {
  /// Foreground-only variant watch for one costume (D5): bounded-backoff
  /// costume refetches while subscribed; terminal variants end the pass; the
  /// subscription dies with the screen (no background polling).
  CostumePhotoWatchProvider._({
    required CostumePhotoWatchFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'costumePhotoWatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$costumePhotoWatchHash();

  @override
  String toString() {
    return r'costumePhotoWatchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<PhotoWatchEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<PhotoWatchEvent> create(Ref ref) {
    final argument = this.argument as (String, String);
    return costumePhotoWatch(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is CostumePhotoWatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$costumePhotoWatchHash() => r'6af831f054d59ad6f7402ee55719d0950665c569';

/// Foreground-only variant watch for one costume (D5): bounded-backoff
/// costume refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

final class CostumePhotoWatchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<PhotoWatchEvent>, (String, String)> {
  CostumePhotoWatchFamily._()
    : super(
        retry: null,
        name: r'costumePhotoWatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Foreground-only variant watch for one costume (D5): bounded-backoff
  /// costume refetches while subscribed; terminal variants end the pass; the
  /// subscription dies with the screen (no background polling).

  CostumePhotoWatchProvider call(String seasonId, String costumeId) =>
      CostumePhotoWatchProvider._(argument: (seasonId, costumeId), from: this);

  @override
  String toString() => r'costumePhotoWatchProvider';
}
