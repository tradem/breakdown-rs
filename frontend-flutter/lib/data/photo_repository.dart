// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:async';
import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/clock.dart';

/// Server size budget for photo originals (default 20 MB). The prepare
/// pipeline downscales client-side so uploads satisfy this without provoking
/// a 413; a 413 from the server stays a defensive branch only.
const int kPhotoMaxSizeMb = 20;

/// Bounded watch budget (whole pass): at most this many refetches…
const int kPhotoWatchMaxAttempts = 12;

/// …or this much wall time (evaluated against a fake clock in tests),
/// whichever is reached first.
const Duration kPhotoWatchMaxElapsed = Duration(seconds: 60);

/// Allowed upload content types (raw bytes, NOT multipart).
const Set<String> kPhotoContentTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

/// Upper bound of the default watch backoff (10s cap of the 2s/4s/8s/10s
/// schedule below). Exported so on-device assertions (issue #380) can derive
/// a quiescence window analytically instead of guessing a sleep budget: if
/// the watch had NOT stopped, another refetch would land within this bound.
const Duration kPhotoWatchMaxDelay = Duration(seconds: 10);

/// Default bounded backoff between watch refetches (production path —
/// tests inject a fake `delay`). Exponential 2s/4s/8s capped at
/// [kPhotoWatchMaxDelay]: foreground-only polling stays gentle on radio and
/// battery instead of bursting all attempts back-to-back.
Future<void> _defaultWatchDelay(int attempt) => Future<void>.delayed(
  Duration(seconds: [2, 4, 8, 10][attempt.clamp(1, 4) - 1]),
);

/// Read/write repository for the `Piece | Continuity` photo bounded context
/// (capture/upload, byte fetch, delete — all AUTHZ-GATE'd server-side).
///
/// Upload is raw bytes with the matching `Content-Type` header (NOT
/// multipart). Photo bytes are memory-cached only, never persisted to Drift.
class PhotoRepository extends BaseRepository {
  const PhotoRepository(super.api);

  /// Raw-bytes upload for a fundus garment (`POST /v1/pieces/{id}/photos`,
  /// the split of the retired `/v1/costumes/{id}/photos` route — a literal
  /// that would answer 404 while the compiler stays silent, which is why the
  /// route is asserted in the repository tests).
  Future<Result<PhotoView>> upload(
    String pieceId,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) => _upload(
    '/v1/pieces/$pieceId/photos',
    bytes,
    contentType,
    onSendProgress: onSendProgress,
  );

  /// Raw-bytes upload for a character's composed look
  /// (`POST /v1/outfits/{id}/photos`).
  Future<Result<PhotoView>> uploadOutfit(
    String outfitId,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) => _upload(
    '/v1/outfits/$outfitId/photos',
    bytes,
    contentType,
    onSendProgress: onSendProgress,
  );

  /// Shared raw-bytes upload.
  ///
  /// [contentType] must be one of [kPhotoContentTypes]; the caller (prepare
  /// pipeline) guarantees the bytes fit the size budget, else it fails
  /// locally with `photo_too_large` and never calls this.
  ///
  /// Implemented via the underlying [Dio] (the generated client types the
  /// body as `String`, which cannot carry binary safely) with the same
  /// error mapping as [BaseRepository.run] (RFC 9457 `code`, never `detail`).
  Future<Result<PhotoView>> _upload(
    String path,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) async {
    if (!kPhotoContentTypes.contains(contentType)) {
      return const Left(ProblemError(code: 'photo.unsupported_media_type'));
    }
    try {
      final response = await api.dio.post<Object>(
        path,
        // Pass the bytes directly (not a Stream): Dio sets the content
        // length automatically, so `onSendProgress` receives a valid
        // total (a Stream payload leaves the length unset and progress
        // reports -1/null). The endpoint consumes raw `Bytes` either way.
        data: bytes,
        options: Options(
          contentType: contentType,
          responseType: ResponseType.json,
        ),
        onSendProgress: onSendProgress,
      );
      final raw = response.data;
      if (raw == null) {
        return const Left(ProblemError(code: 'photo.dto_invalid'));
      }
      try {
        final view = api.serializers.deserializeWith(PhotoView.serializer, raw);
        if (view == null) {
          return const Left(ProblemError(code: 'photo.dto_invalid'));
        }
        return Right(view);
      } on Object {
        return const Left(ProblemError(code: 'photo.dto_invalid'));
      }
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  /// Fetches the raw bytes of a photo variant.
  ///
  /// The backend returns the variant as a binary `image/*` body; the generated
  /// client surfaces it as `Uint8List` (it is never JSON-deserialized), so the
  /// [Result] carries the undecoded bytes for rendering, caching, or saving.
  Future<Result<Uint8List>> getBytes(
    String pieceId,
    String photoId,
    String variant,
  ) => run(
    () => api.getHandlersApi().getPiecePhotoBytes(
      pieceId: pieceId,
      photoId: photoId,
      variant: variant,
    ),
  );

  /// Deletes a piece photo (204 → optimistic removal + reconcile).
  /// A `null` body is success (not `dto.invalid`).
  Future<Result<void>> delete(String pieceId, String photoId) async {
    try {
      await api.getHandlersApi().deletePiecePhoto(
        pieceId: pieceId,
        photoId: photoId,
      );
      return const Right<ProblemError, void>(null);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  /// Fetches the raw bytes of an outfit (fitting) photo variant
  /// (`GET /v1/outfits/{outfit_id}/photos/{photo_id}/bytes`).
  Future<Result<Uint8List>> getOutfitBytes(
    String outfitId,
    String photoId,
    String variant,
  ) => run(
    () => api.getHandlersApi().getOutfitPhotoBytes(
      outfitId: outfitId,
      photoId: photoId,
      variant: variant,
    ),
  );

  /// Deletes an outfit photo (204 → optimistic removal + reconcile).
  /// A `null` body is success (not `dto.invalid`).
  Future<Result<void>> deleteOutfitPhoto(
    String outfitId,
    String photoId,
  ) async {
    try {
      await api.getHandlersApi().deleteOutfitPhoto(
        outfitId: outfitId,
        photoId: photoId,
      );
      return const Right<ProblemError, void>(null);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  /// Bounded-backoff piece refetch stream for variant watching (D5).
  ///
  /// Refetches the piece view via [fetchPiece] until the terminal
  /// condition holds — **every** variant of **every** photo is
  /// `Ready|Failed` (whole pass, not per-variant) — or the bounded budget
  /// is exhausted ([kPhotoWatchMaxAttempts] refetches or
  /// [kPhotoWatchMaxElapsed] elapsed, whichever first).
  ///
  /// * On expiry emits the current view with [PhotoWatchState.expired]
  ///   (`watch_expired`): polling stops, still-`Pending` variants render a
  ///   neutral "still processing" affordance with manual refresh, and no
  ///   further network call is made until the user re-subscribes.
  /// * The stream stops when the last subscriber leaves (caller cancels the
  ///   subscription — no background polling, foreground-only).
  /// * [delay] is injectable (fake scheduler in tests — never a real
  ///   `Future.delayed` wall-clock).
  Stream<PhotoWatchEvent<PieceView>> watch(
    String pieceId,
    Future<Result<PieceView>> Function() fetchPiece, {
    Clock clock = Clock.system,
    Future<void> Function(int attempt)? delay,
  }) => watchPhotos<PieceView>(
    fetch: fetchPiece,
    isTerminal: isPhotoWatchTerminal,
    clock: clock,
    delay: delay,
  );

  /// The outfit twin of [watch]: the same bounded backoff over the look's
  /// fitting photos, so the two aggregate boundaries share ONE polling
  /// implementation instead of drifting apart.
  Stream<PhotoWatchEvent<OutfitView>> watchOutfit(
    String outfitId,
    Future<Result<OutfitView>> Function() fetchOutfit, {
    Clock clock = Clock.system,
    Future<void> Function(int attempt)? delay,
  }) => watchPhotos<OutfitView>(
    fetch: fetchOutfit,
    isTerminal: isOutfitPhotoWatchTerminal,
    clock: clock,
    delay: delay,
  );

  /// Generic bounded-backoff watch over an enriched view whose photos carry
  /// variants. [isTerminal] decides the whole-pass terminal condition for the
  /// concrete view ([isPhotoWatchTerminal] / [isOutfitPhotoWatchTerminal]).
  Stream<PhotoWatchEvent<View>> watchPhotos<View>({
    required Future<Result<View>> Function() fetch,
    required bool Function(View view) isTerminal,
    Clock clock = Clock.system,
    Future<void> Function(int attempt)? delay,
  }) async* {
    final startedAt = clock.now();
    var attempts = 0;
    Stream<PhotoWatchEvent<View>> emitExpired() async* {
      final last = await fetch();
      yield* last.match(
        (err) async* {
          yield PhotoWatchEvent.expired(null, err);
        },
        (view) async* {
          yield PhotoWatchEvent.expired(view, null);
        },
      );
    }

    while (true) {
      if (attempts >= kPhotoWatchMaxAttempts) {
        yield* emitExpired();
        return;
      }
      if (attempts > 0) {
        await (delay ?? _defaultWatchDelay)(attempts);
      }
      // Rechecked after the delay: a delay can cross the deadline, and
      // only the expiry fetch may run past the budget (never a normal
      // fetch plus an expiry fetch).
      if (clock.now().difference(startedAt) >= kPhotoWatchMaxElapsed) {
        yield* emitExpired();
        return;
      }
      attempts++;
      final result = await fetch();
      final done = await result.match(
        (_) async => false,
        (view) async => isTerminal(view),
      );
      yield* result.match(
        (err) async* {
          yield PhotoWatchEvent.progress(null, attempts, err);
        },
        (view) async* {
          yield done
              ? PhotoWatchEvent.terminal(view)
              : PhotoWatchEvent.progress(view, attempts, null);
        },
      );
      if (done) return;
    }
  }
}

/// Watch event state.
enum PhotoWatchState {
  /// Intermediate refetch (still pending variants).
  progress,

  /// Terminal condition reached (every variant `Ready|Failed`).
  terminal,

  /// Bounded budget exhausted (`watch_expired` — manual refresh required).
  expired,
}

/// One emission of [PhotoRepository.watch] / [PhotoRepository.watchOutfit].
class PhotoWatchEvent<View> {
  const PhotoWatchEvent._(this.state, this.view, this.attempts, this.error);

  const PhotoWatchEvent.progress(View? view, int attempts, ProblemError? error)
    : this._(PhotoWatchState.progress, view, attempts, error);

  const PhotoWatchEvent.terminal(View view)
    : this._(PhotoWatchState.terminal, view, 0, null);

  const PhotoWatchEvent.expired(View? view, ProblemError? error)
    : this._(PhotoWatchState.expired, view, 0, error);

  final PhotoWatchState state;
  final View? view;
  final int attempts;
  final ProblemError? error;
}

/// Terminal condition (whole pass, not per-variant): the variant status lives
/// at `PieceView.photos[].variants[].status` — `variants` belongs to each
/// `PiecePhotoView` inside `PieceView.photos`, NOT to `PieceView`
/// itself. The watch ends only when **every** variant of **every** photo of
/// the watched piece is terminal (`Ready` or `Failed`).
///
/// A photo with one `Ready` and one `Pending` variant keeps the pass running.
/// An empty photo list is terminal (nothing to wait for).
bool isPhotoWatchTerminal(PieceView view) =>
    _variantsTerminal(view.photos.map((photo) => photo.variants));

/// Outfit terminal condition: the same whole-pass rule over
/// `OutfitView.photos[].variants[].status`. A fitting photo whose variant set
/// has not appeared yet keeps the pass running; an empty list is terminal.
bool isOutfitPhotoWatchTerminal(OutfitView view) =>
    _variantsTerminal(view.photos.map((photo) => photo.variants));

/// One rule for both aggregates: every photo must have a variant set, and
/// every variant must be terminal (`Ready` or `Failed`).
bool _variantsTerminal(Iterable<Iterable<PhotoVariantView>> photos) {
  for (final variants in photos) {
    if (variants.isEmpty) return false;
    for (final variant in variants) {
      if (variant.status != VariantStatus.ready &&
          variant.status != VariantStatus.failed) {
        return false;
      }
    }
  }
  return true;
}
