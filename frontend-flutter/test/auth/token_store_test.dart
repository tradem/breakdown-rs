// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:frontend_flutter/auth/token_store.dart';

/// In-memory [FlutterSecureStoragePlatform] double backed by a map — lets us
/// verify that tokens really round-trip through the secure-storage API (the
/// plugin that surfaces the Android Keystore) and never a plaintext store.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};
  bool failWrites = false;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => store.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      store.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failWrites) {
      throw PlatformException(code: 'write_failed');
    }
    if (value.isEmpty) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }
}

AuthTokens _tokens() => AuthTokens(
  accessToken: 'at-1',
  refreshToken: 'rt-1',
  idToken: _idToken(sub: 'user-42'),
  expiresAt: DateTime.utc(2030),
);

String _idToken({required String sub}) {
  final header = base64Url.encode(utf8.encode('{"alg":"RS256"}'));
  final payload = base64Url.encode(utf8.encode('{"sub":"$sub"}'));
  return '$header.$payload.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStoragePlatform platform;
  late SecureTokenStore store;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    store = SecureTokenStore();
  });

  group('SecureTokenStore', () {
    test('save/read round-trips the full token set (Ok branch)', () async {
      final save = await store.save(_tokens());
      expect(save.isRight(), isTrue);

      final read = await store.read();
      final tokens = read.fold((e) => throw e, (t) => t!);
      expect(tokens.accessToken, 'at-1');
      expect(tokens.refreshToken, 'rt-1');
      expect(tokens.expiresAt, DateTime.utc(2030));
      expect(subFromIdToken(tokens.idToken), 'user-42');
    });

    test(
      'read returns null when signed out (Ok branch, empty store)',
      () async {
        final read = await store.read();
        expect(read.fold((e) => throw e, (t) => t), isNull);
      },
    );

    test('clear wipes all token material', () async {
      await store.save(_tokens());
      final cleared = await store.clear();
      expect(cleared.isRight(), isTrue);
      expect(platform.store, isEmpty);
      expect((await store.read()).fold((e) => throw e, (t) => t), isNull);
    });

    test(
      'a partially persisted session is corrupt → cleared, signed out',
      () async {
        platform.store['breakdown.oidc.access_token'] = 'at-orphan';
        final read = await store.read();
        expect(read.fold((e) => throw e, (t) => t), isNull);
        expect(platform.store, isEmpty);
      },
    );

    test('write failure surfaces as Left (Err branch)', () async {
      platform.failWrites = true;
      final save = await store.save(_tokens());
      final err = save.fold((e) => e, (_) => throw 'expected Left');
      expect(err.code, 'auth.token_store_write_failed');
    });
  });

  group('isExpired', () {
    test('true at/past expiry, false before', () {
      expect(
        AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          idToken: 'i',
          expiresAt: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
        ).isExpired,
        isTrue,
      );
      expect(
        AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          idToken: 'i',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ).isExpired,
        isFalse,
      );
      expect(
        const AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          idToken: 'i',
        ).isExpired,
        isFalse,
      );
    });
  });

  group('subFromIdToken', () {
    test('extracts the sub claim (display only — never verification)', () {
      expect(subFromIdToken(_idToken(sub: 'abc')), 'abc');
    });

    test('returns null for malformed tokens', () {
      expect(subFromIdToken('not-a-jwt'), isNull);
      expect(subFromIdToken('a.b'), isNull);
      expect(
        subFromIdToken('a.${base64Url.encode(utf8.encode('{"x":1}'))}.c'),
        isNull,
      );
    });
  });
}
