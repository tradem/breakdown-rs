// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// The shared in-memory secure-storage platform fake (single source —
/// the three per-suite copies had already diverged: only this one
/// supports [failAll]). Tests assign
/// `FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform()`
/// in `setUp` and assert against [store].
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  /// When true, every platform channel call throws a
  /// [PlatformException] (the storage-fault branch tests).
  bool failAll = false;

  /// Fails only WRITES: the document stays readable, so a cleanup that cannot
  /// be persisted can be shown to leave the (still readable) state alone
  /// instead of spinning (issue #879's failing-eviction case).
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
  }) async {
    if (failAll) throw PlatformException(code: 'delete_failed');
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    if (failAll) throw PlatformException(code: 'delete_failed');
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failAll) throw PlatformException(code: 'read_failed');
    return store[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    if (failAll) throw PlatformException(code: 'read_failed');
    return Map.of(store);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (failAll || failWrites) throw PlatformException(code: 'write_failed');
    store[key] = value;
  }
}
