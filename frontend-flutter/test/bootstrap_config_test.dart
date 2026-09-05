// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

import 'package:frontend_flutter/app.dart';
import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/data/settings/api_base_override_store.dart';

/// Minimal secure-storage double backing [ApiBaseOverrideStore.secure] in
/// these tests (full double lives in the store's own test file).
class _PlatformDouble extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

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
    store[key] = value;
  }
}

const _devBase = AppConfig(
  flavor: Flavor.dev,
  apiBase: 'http://10.0.2.2:3000',
  oidcIss: '',
  devAuthSub: 'dev-user',
  oidcAudience: '',
  oidcClientId: '',
  oidcRedirectUri: '',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: '',
);

const _prodBase = AppConfig(
  flavor: Flavor.prod,
  apiBase: 'https://api.breakdown.rs',
  oidcIss: 'https://idp.example',
  devAuthSub: '',
  oidcAudience: 'breakdown-api',
  oidcClientId: 'client',
  oidcRedirectUri: 'breakdown://redirect',
  devIdpInsecure: '',
  appVersion: '1.0.0+1',
  defaultSeriesId: '',
);

/// Bootstrap pre-application ordering (task 6.1/6.5): the persisted
/// override applies after `fromEnvironment`, before any client
/// construction — flavor-guarded, defensively re-validated.
void main() {
  late _PlatformDouble platform;

  setUp(() {
    platform = _PlatformDouble();
    FlutterSecureStoragePlatform.instance = platform;
  });

  group('applyApiBaseOverride', () {
    test('no stored override: compile-time base unchanged', () async {
      final config = await applyApiBaseOverride(_devBase);
      expect(config.apiBase, 'http://10.0.2.2:3000');
    });

    test('dev: valid stored override replaces the base', () async {
      platform.store[ApiBaseOverrideStore.key] = 'https://dev.example:4000/';
      final config = await applyApiBaseOverride(_devBase);
      expect(config.apiBase, 'https://dev.example:4000');
      // Every other field is untouched.
      expect(config.flavor, Flavor.dev);
      expect(config.devAuthSub, 'dev-user');
      expect(config.appVersion, '1.0.0+1');
    });

    test('dev: invalid stored override is ignored', () async {
      platform.store[ApiBaseOverrideStore.key] = 'http://evil.example/x';
      final config = await applyApiBaseOverride(_devBase);
      expect(config.apiBase, 'http://10.0.2.2:3000');
    });

    test('prod: stored override ignored AND cleared', () async {
      platform.store[ApiBaseOverrideStore.key] = 'https://dev.example:4000';
      final config = await applyApiBaseOverride(_prodBase);
      expect(config.apiBase, 'https://api.breakdown.rs');
      expect(platform.store.containsKey(ApiBaseOverrideStore.key), isFalse);
    });
  });
}
