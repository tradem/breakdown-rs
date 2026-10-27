// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'piece_detail_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Foreground-only variant watch for one piece (D5): bounded-backoff
/// piece refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

@ProviderFor(piecePhotoWatch)
final piecePhotoWatchProvider = PiecePhotoWatchFamily._();

/// Foreground-only variant watch for one piece (D5): bounded-backoff
/// piece refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

final class PiecePhotoWatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<PhotoWatchEvent<PieceView>>,
          PhotoWatchEvent<PieceView>,
          Stream<PhotoWatchEvent<PieceView>>
        >
    with
        $FutureModifier<PhotoWatchEvent<PieceView>>,
        $StreamProvider<PhotoWatchEvent<PieceView>> {
  /// Foreground-only variant watch for one piece (D5): bounded-backoff
  /// piece refetches while subscribed; terminal variants end the pass; the
  /// subscription dies with the screen (no background polling).
  PiecePhotoWatchProvider._({
    required PiecePhotoWatchFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'piecePhotoWatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$piecePhotoWatchHash();

  @override
  String toString() {
    return r'piecePhotoWatchProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<PhotoWatchEvent<PieceView>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<PhotoWatchEvent<PieceView>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return piecePhotoWatch(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is PiecePhotoWatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$piecePhotoWatchHash() => r'74c6d785878bab836c90742e6dc64fc61fbce391';

/// Foreground-only variant watch for one piece (D5): bounded-backoff
/// piece refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

final class PiecePhotoWatchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<PhotoWatchEvent<PieceView>>,
          (String, String)
        > {
  PiecePhotoWatchFamily._()
    : super(
        retry: null,
        name: r'piecePhotoWatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Foreground-only variant watch for one piece (D5): bounded-backoff
  /// piece refetches while subscribed; terminal variants end the pass; the
  /// subscription dies with the screen (no background polling).

  PiecePhotoWatchProvider call(String seasonId, String pieceId) =>
      PiecePhotoWatchProvider._(argument: (seasonId, pieceId), from: this);

  @override
  String toString() => r'piecePhotoWatchProvider';
}
