// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

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

/// Read/write repository for the `Costume | Continuity` photo bounded context
/// (capture/upload, byte fetch, delete — all AUTHZ-GATE'd server-side).
///
/// Upload is raw bytes with the matching `Content-Type` header (NOT
/// multipart). Photo bytes are memory-cached only, never persisted to Drift.
class PhotoRepository extends BaseRepository {
  const PhotoRepository(super.api);

  /// Raw-bytes upload (`POST /v1/costumes/{costume_id}/photos`).
  ///
  /// [contentType] must be one of [kPhotoContentTypes]; the caller (prepare
  /// pipeline) guarantees the bytes fit the size budget, else it fails
  /// locally with `photo_too_large` and never calls this.
  ///
  /// Implemented via the underlying [Dio] (the generated client types the
  /// body as `String`, which cannot carry binary safely) with the same
  /// error mapping as [BaseRepository.run] (RFC 9457 `code`, never `detail`).
  Future<Result<PhotoView>> upload(
    String costumeId,
    Uint8List bytes,
    String contentType, {
    ProgressCallback? onSendProgress,
  }) async {
    if (!kPhotoContentTypes.contains(contentType)) {
      return const Left(ProblemError(code: 'photo.unsupported_media_type'));
    }
    try {
      final response = await api.dio.post<Object>(
        '/v1/costumes/$costumeId/photos',
        data: Stream.fromIterable([bytes]),
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
    String costumeId,
    String photoId,
    String variant,
  ) => run(
    () => api.getHandlersApi().getCostumePhotoBytes(
      costumeId: costumeId,
      photoId: photoId,
      variant: variant,
    ),
  );

  /// Deletes a costume photo (204 → optimistic removal + reconcile).
  /// A `null` body is success (not `dto.invalid`).
  Future<Result<void>> delete(String costumeId, String photoId) async {
    try {
      await api.getHandlersApi().deleteCostumePhoto(
        costumeId: costumeId,
        photoId: photoId,
      );
      return const Right<ProblemError, void>(null);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  /// Bounded-backoff costume refetch stream for variant watching (D5).
  ///
  /// Refetches the costume view via [fetchCostume] until the terminal
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
  Stream<PhotoWatchEvent> watch(
    String costumeId,
    Future<Result<CostumeView>> Function() fetchCostume, {
    Clock clock = Clock.system,
    Future<void> Function(int attempt)? delay,
  }) async* {
    final startedAt = clock.now();
    var attempts = 0;
    while (true) {
      if (attempts >= kPhotoWatchMaxAttempts) {
        final last = await fetchCostume();
        yield* last.match(
          (err) async* {
            yield PhotoWatchEvent.expired(null, err);
          },
          (view) async* {
            yield PhotoWatchEvent.expired(view, null);
          },
        );
        return;
      }
      final elapsed = clock.now().difference(startedAt);
      if (elapsed > kPhotoWatchMaxElapsed) {
        final last = await fetchCostume();
        yield* last.match(
          (err) async* {
            yield PhotoWatchEvent.expired(null, err);
          },
          (view) async* {
            yield PhotoWatchEvent.expired(view, null);
          },
        );
        return;
      }
      if (attempts > 0 && delay != null) {
        await delay(attempts);
      }
      attempts++;
      final result = await fetchCostume();
      final done = await result.match(
        (_) async => false,
        (view) async => isPhotoWatchTerminal(view),
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

/// One emission of [PhotoRepository.watch].
class PhotoWatchEvent {
  const PhotoWatchEvent._(this.state, this.view, this.attempts, this.error);

  const PhotoWatchEvent.progress(
    CostumeView? view,
    int attempts,
    ProblemError? error,
  ) : this._(PhotoWatchState.progress, view, attempts, error);

  const PhotoWatchEvent.terminal(CostumeView view)
    : this._(PhotoWatchState.terminal, view, 0, null);

  const PhotoWatchEvent.expired(CostumeView? view, ProblemError? error)
    : this._(PhotoWatchState.expired, view, 0, error);

  final PhotoWatchState state;
  final CostumeView? view;
  final int attempts;
  final ProblemError? error;
}

/// Terminal condition (whole pass, not per-variant): the variant status lives
/// at `CostumeView.photos[].variants[].status` — `variants` belongs to each
/// `CostumePhotoView` inside `CostumeView.photos`, NOT to `CostumeView`
/// itself. The watch ends only when **every** variant of **every** photo of
/// the watched costume is terminal (`Ready` or `Failed`).
///
/// A photo with one `Ready` and one `Pending` variant keeps the pass running.
/// An empty photo list is terminal (nothing to wait for).
bool isPhotoWatchTerminal(CostumeView view) {
  if (view.photos.isEmpty) return true;
  for (final photo in view.photos) {
    for (final variant in photo.variants) {
      final status = serializers.serializeWith(
        VariantStatus.serializer,
        variant.status,
      );
      if (status != 'Ready' && status != 'Failed') return false;
    }
  }
  return true;
}
