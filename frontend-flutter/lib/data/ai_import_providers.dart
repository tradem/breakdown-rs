// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'ai_config_repository.dart';
import 'ai_import_handoff_store.dart';
import 'ai_import_repository.dart';
import 'cache/ai_import_jobs_cache_dao.dart';
import 'cache/seasons_cache_providers.dart';

part 'ai_import_providers.g.dart';

/// AI-import **configuration** repository: owns the discovery, credential
/// hand-off, config CRUD and rollback routes (task 1.1).
@riverpod
AiConfigRepository aiConfigRepository(Ref ref) =>
    AiConfigRepository(ref.watch(apiClientProvider));

/// AI-import **workflow** repository: owns the raw-body uploads, job
/// status, preview and apply routes plus the Drift job cache (tasks
/// 1.2/1.4).
@riverpod
AiImportRepository aiImportRepository(Ref ref) => AiImportRepository(
  ref.watch(apiClientProvider),
  AiImportJobsCacheDao(ref.watch(cacheDatabaseProvider)),
);

/// The AI-import secure-storage hand-off seam (task 1.3 — manual provider,
/// no codegen, so tests override with an in-memory double via
/// `overrideWithValue`; same pattern as `activeBlockStoreProvider`).
final aiImportHandoffStoreProvider = Provider<AiImportHandoffStore>(
  (ref) => AiImportHandoffStore.secure(),
  name: 'aiImportHandoffStore',
);
