// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/photo_repository.dart';

/// Photo prepare pipeline (flutter-costume-domains Task 3.1, D4).
///
/// Capture → prepare (background isolate) → raw-bytes upload. Downscaling is
/// NOT a size guarantee (a PNG re-encode can still exceed the budget), so the
/// prepared bytes are measured and, if oversized, iteratively re-encoded at a
/// reduced cap/quality until they fit [kPhotoMaxSizeMb] or fall below a floor
/// — after which the client fails locally with [PrepareFailure.tooLarge] (no
/// upload attempt, localized copy) instead of provoking a 413. 413 from the
/// server therefore stays a defensive branch only.
///
/// The UI thread stays free; progress shows a `LinearProgressIndicator`
/// (prepare + upload). Server-side EXIF stripping is trusted (never
/// re-implemented client-side — orientation is applied via the `image`
/// package's EXIF-aware decode).

/// Longest-side cap for the first prepare pass (px).
const int kPrepareLongestSideCap = 2048;

/// Floor below which the reduction loop gives up (px).
const int kPrepareMinLongestSide = 256;

/// Reduction factor per iteration when the budget is still exceeded.
const double kPrepareReductionFactor = 0.75;

/// JPEG quality for re-encode passes.
const int kPrepareJpegQuality = 85;

/// PNG level is fixed (6); oversized PNGs converge via the side-cap loop.

/// Pure prepare input (isolate-safe: only primitives + bytes cross the
/// isolate boundary).
class PrepareInput {
  const PrepareInput({
    required this.bytes,
    required this.contentType,
    this.longestSideCap = kPrepareLongestSideCap,
    this.maxBytes = -1,
  });

  final Uint8List bytes;
  final String contentType;
  final int longestSideCap;

  /// Size budget override (bytes). Negative means the production
  /// [photoMaxBytes] budget. Exposed so unit tests can force the
  /// iterative-reduction and `too_large` paths with tiny fixtures
  /// instead of 20 MB images (same logic, injectable bound).
  final int maxBytes;
}

/// Pure prepare result: ready-to-upload bytes + content type, or a typed
/// local failure (never a throw — AGENTS.md §5).
sealed class PrepareResult {
  const PrepareResult();
}

class PrepareReady extends PrepareResult {
  const PrepareReady(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

enum PrepareFailureKind { unsupportedFormat, decodeFailed, tooLarge }

class PrepareFailure extends PrepareResult {
  const PrepareFailure(this.kind, this.code);

  final PrepareFailureKind kind;

  /// Stable problem `code` the UI localizes (never `detail` text).
  final String code;

  static const tooLarge = PrepareFailure(
    PrepareFailureKind.tooLarge,
    'photo.too_large',
  );
  static const unsupportedFormat = PrepareFailure(
    PrepareFailureKind.unsupportedFormat,
    'photo.unsupported_media_type',
  );
  static const decodeFailed = PrepareFailure(
    PrepareFailureKind.decodeFailed,
    'photo.decode_failed',
  );
}

/// Maps a file extension / picker mime to the upload content type, or `null`
/// when outside jpeg/png/webp (client rejects before the network).
String? contentTypeForExtension(String extension) {
  final ext = extension.toLowerCase().replaceAll('.', '');
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
}

/// Maximum upload bytes derived from [kPhotoMaxSizeMb].
int get photoMaxBytes => kPhotoMaxSizeMb * 1024 * 1024;

/// Isolate-free pure core (unit-tested with tiny synthetic fixtures, no real
/// camera hardware in CI). Decodes, downscales the longest side to
/// [input.longestSideCap], re-encodes to the picked content type, measures,
/// and iteratively reduces until the budget fits or the floor is hit.
PrepareResult prepareImageCore(PrepareInput input) {
  if (!kPhotoContentTypes.contains(input.contentType)) {
    return PrepareFailure.unsupportedFormat;
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input.bytes);
  } on Object {
    return PrepareFailure.decodeFailed;
  }
  if (decoded == null) return PrepareFailure.decodeFailed;

  var cap = input.longestSideCap;
  final budget = input.maxBytes < 0 ? photoMaxBytes : input.maxBytes;
  while (true) {
    final resized = _downscaleToCap(decoded, cap);
    final encoded = _encode(resized, input.contentType);
    if (encoded.bytes.lengthInBytes <= budget) {
      return PrepareReady(encoded.bytes, encoded.contentType);
    }
    final next = (cap * kPrepareReductionFactor).floor();
    if (next < kPrepareMinLongestSide) {
      return PrepareFailure.tooLarge;
    }
    cap = next;
  }
}

/// Background-isolate entry point: moves [prepareImageCore] off the UI
/// thread. Uses [Isolate.run] (pure Dart — no Flutter dependency, so
/// Tier-1 unit tests stay Flutter-free). The isolate boundary itself
/// cannot complete headless in `flutter_test`; screens therefore call
/// [preparePhotoProvider] (overridable to the synchronous core in tests)
/// instead of this function directly. On-device cover lives in
/// `integration_test/costume_domains_smoke_test.dart` (issue #370: the
/// smoke uses the production seam without override plus a direct
/// `defaultPreparePhoto` → `PrepareReady` boundary assertion).
Future<PrepareResult> prepareImage(PrepareInput input) =>
    Isolate.run(() => prepareImageCore(input));

/// Injectable prepare seam: production runs [prepareImage] (background
/// isolate); widget tests override with the synchronous
/// [prepareImageCore] since isolates never complete headless.
typedef PreparePhoto = Future<PrepareResult> Function(PrepareInput input);

Future<PrepareResult> defaultPreparePhoto(PrepareInput input) =>
    prepareImage(input);

img.Image _downscaleToCap(img.Image src, int cap) {
  final longest = src.width >= src.height ? src.width : src.height;
  if (longest <= cap) return src;
  final scale = cap / longest;
  return img.copyResize(
    src,
    width: (src.width * scale).round(),
    height: (src.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}

/// Encoded bytes plus the truthful content type for the upload header.
///
/// The `image` package has no WebP *encoder* (decode-only), so WebP input
/// is transcoded to JPEG and the effective type is `image/jpeg` — the
/// header always matches the bytes (never JPEG bytes labeled `image/webp`).
({Uint8List bytes, String contentType}) _encode(
  img.Image image,
  String contentType,
) {
  final bytes = switch (contentType) {
    'image/png' => img.encodePng(image),
    _ => img.encodeJpg(image, quality: kPrepareJpegQuality),
  };
  final effectiveType = contentType == 'image/png' ? 'image/png' : 'image/jpeg';
  return (bytes: Uint8List.fromList(bytes), contentType: effectiveType);
}
