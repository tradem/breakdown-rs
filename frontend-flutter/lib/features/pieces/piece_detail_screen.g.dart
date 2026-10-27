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
          AsyncValue<PhotoWatchEvent>,
          PhotoWatchEvent,
          Stream<PhotoWatchEvent>
        >
    with $FutureModifier<PhotoWatchEvent>, $StreamProvider<PhotoWatchEvent> {
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
  $StreamProviderElement<PhotoWatchEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<PhotoWatchEvent> create(Ref ref) {
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

String _$piecePhotoWatchHash() => r'3f0bbc2541bd83acf851ac6f5b7c615d7e3a15c7';

/// Foreground-only variant watch for one piece (D5): bounded-backoff
/// piece refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).

final class PiecePhotoWatchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<PhotoWatchEvent>, (String, String)> {
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
