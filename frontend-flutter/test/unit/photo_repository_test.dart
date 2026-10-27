// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

// Tier-1 unit test: pure data-layer logic, no Flutter imports (AGENTS.md test
// pyramid). Verifies that `PhotoRepository.getBytes` preserves and returns the
// fetched photo variant bytes (a `Uint8List` from the generated binary
// response) and maps a server rejection to a `ProblemError` value.

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:one_of/one_of.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:frontend_flutter/core/problem_error.dart';
import 'package:frontend_flutter/data/photo_repository.dart';

/// Interceptor that short-circuits the request without any real network call,
/// resolving with canned [bytes] or rejecting with [exception].
class _FakePhotoBytesInterceptor extends Interceptor {
  _FakePhotoBytesInterceptor({this.bytes, this.exception})
    : assert(bytes != null || exception != null);

  final Uint8List? bytes;
  final DioException? exception;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (exception != null) {
      handler.reject(exception!);
      return;
    }
    handler.resolve(
      Response<Uint8List>(
        requestOptions: options,
        statusCode: 200,
        data: bytes,
      ),
    );
  }
}

BreakdownApi _apiWith(Interceptor interceptor) =>
    BreakdownApi(dio: Dio(), interceptors: [interceptor]);

/// Records the outgoing request path/method and answers with [body].
class _RecordingInterceptor extends Interceptor {
  _RecordingInterceptor({this.body = const <String, Object?>{}});

  final Object body;
  final List<({String method, String path})> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add((method: options.method, path: options.uri.path));
    handler.resolve(
      Response<Object>(requestOptions: options, statusCode: 200, data: body),
    );
  }
}

/// A wire-shaped `PhotoView` body (serialized through the generated
/// serializer, so the DTO contract is the single source of truth).
Object _photoBody(String id) {
  final api = BreakdownApi();
  final view = PhotoView(
    (b) => b
      ..id = id
      ..contentType = 'image/jpeg'
      ..sizeBytes = 3
      ..version = 1
      ..binding.replace(
        PhotoBinding(
          (b) => b
            ..oneOf = OneOf.fromValue1<PhotoBindingOneOfPiece>(
              value: PhotoBindingOneOfPiece((b) => b..pieceId = 'piece-1'),
            ),
        ),
      )
      ..variants.replace(BuiltList<PhotoVariantView>()),
  );
  return api.serializers.serializeWith(PhotoView.serializer, view)!;
}

void main() {
  group('PhotoRepository routes (wardrobe split)', () {
    test('a piece upload posts to /v1/pieces/{id}/photos', () async {
      final recorder = _RecordingInterceptor(body: _photoBody('photo-1'));
      final repo = PhotoRepository(_apiWith(recorder));

      final result = await repo.upload(
        'piece-1',
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );

      expect(recorder.requests.single.method, 'POST');
      expect(recorder.requests.single.path, '/v1/pieces/piece-1/photos');
      // The route is the assertion: the retired `/v1/costumes/{id}/photos`
      // literal was a silent 404 no compiler could catch.
      expect(result.isLeft() || result.isRight(), isTrue);
    });

    test('an outfit upload posts to /v1/outfits/{id}/photos', () async {
      final recorder = _RecordingInterceptor(body: _photoBody('photo-2'));
      final repo = PhotoRepository(_apiWith(recorder));

      final result = await repo.uploadOutfit(
        'outfit-1',
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );

      expect(recorder.requests.single.method, 'POST');
      expect(recorder.requests.single.path, '/v1/outfits/outfit-1/photos');
      expect(result.isLeft() || result.isRight(), isTrue);
    });

    test('an unsupported content type never reaches the network', () async {
      final recorder = _RecordingInterceptor();
      final repo = PhotoRepository(_apiWith(recorder));

      final result = await repo.uploadOutfit(
        'outfit-1',
        Uint8List.fromList([1]),
        'image/gif',
      );

      expect(recorder.requests, isEmpty);
      expect(result.isLeft(), isTrue);
      result.fold(
        (l) => expect(l.code, 'photo.unsupported_media_type'),
        (_) => fail('expected Left'),
      );
    });

    test('outfit byte fetch and delete hit the outfit routes', () async {
      final recorder = _RecordingInterceptor(body: Uint8List.fromList([9]));
      final repo = PhotoRepository(_apiWith(recorder));

      await repo.getOutfitBytes('outfit-1', 'photo-2', 'Thumb');
      expect(
        recorder.requests.last.path,
        '/v1/outfits/outfit-1/photos/photo-2/bytes',
      );

      await repo.deleteOutfitPhoto('outfit-1', 'photo-2');
      expect(recorder.requests.last.method, 'DELETE');
      expect(
        recorder.requests.last.path,
        '/v1/outfits/outfit-1/photos/photo-2',
      );
    });
  });

  group('PhotoRepository.getBytes', () {
    test('returns the fetched photo bytes on success', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final repo = PhotoRepository(
        _apiWith(_FakePhotoBytesInterceptor(bytes: bytes)),
      );

      final result = await repo.getBytes('piece-1', 'photo-1', 'original');

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('expected Right but got Left($l)'),
        (r) => expect(r, bytes),
      );
    });

    test('maps a server rejection to a Left(ProblemError)', () async {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/v1/pieces/c/photos/p/bytes'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/pieces/c/photos/p/bytes'),
          statusCode: 403,
          data: {
            'code': 'photo.forbidden',
            'title': 'Not authorized',
            'status': 403,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = PhotoRepository(
        _apiWith(_FakePhotoBytesInterceptor(exception: exception)),
      );

      final result = await repo.getBytes('c', 'p', 'original');

      expect(result.isLeft(), isTrue);
      result.fold(
        (l) => expect(l, isA<ProblemError>()),
        (r) => fail('expected Left but got Right($r)'),
      );
      result.fold(
        (l) => expect(l.code, 'photo.forbidden'),
        (_) => fail('expected Left'),
      );
    });
  });
}
