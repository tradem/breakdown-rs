// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:async' show Completer;
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// Upper bound for the remembered job-id list (task 1.3: bounded N).
const int kMaxRememberedJobIds = 20;

/// The per-user AI-import hand-off state (task 1.3).
///
/// * [configId] — the remembered AI-import configuration id from the create
///   response (D2 fast-path/fallback; the `GET /v1/ai-import/config` list
///   route remains the authoritative discovery).
/// * [jobIds] — the most recent job ids, newest first, bounded to
///   [kMaxRememberedJobIds]. The list route (`GET /v1/ai-import/jobs`) is
///   authoritative for discovery; this list is the fast path and the
///   "what did I import" surface.
class AiImportHandoffState {
  const AiImportHandoffState({this.configId, this.jobIds = const <String>[]});

  final String? configId;

  /// Newest first, deduplicated, bounded to [kMaxRememberedJobIds].
  final List<String> jobIds;

  static const AiImportHandoffState empty = AiImportHandoffState();
}

/// Secure-storage hand-off store for AI-import ids (task 1.3).
///
/// Persists, per authenticated subject (`sub`), the remembered configuration
/// id and the bounded recent job-id list. Same seam as `SecureTokenStore` /
/// `ActiveBlockStore` (`flutter_secure_storage` — Android Keystore). Ids are
/// not secrets; secure storage is chosen for the session-lifecycle coupling:
///
/// * **Keyed by the authenticated `sub`** — user A's state is structurally
///   unreachable while user B is signed in (reads/writes always carry the
///   caller's `sub`), and the unit test pins the A → B switch (user B reads
///   an empty state after user A stored one).
/// * **Cleared on sign-out** — `clear()` deletes the whole document and is
///   awaited by the Phase 1a `SessionReset` (backend switch clears it too —
///   ids are backend-scoped).
///
/// All methods are [Result]-typed; storage failures are values, never throws
/// (AGENTS.md §5). A corrupt payload self-heals to the empty state (same
/// discipline as `ActiveBlockStore`). Mutations run serialized through the
/// write mutex in invocation order (read-modify-write on one key).
class AiImportHandoffStore {
  AiImportHandoffStore(this._storage);

  /// Production store backed by the platform secure enclave.
  factory AiImportHandoffStore.secure() =>
      AiImportHandoffStore(const FlutterSecureStorage());

  /// Secure-storage key for the per-subject state document.
  static const String key = 'breakdown.ai_import_handoff';

  final FlutterSecureStorage _storage;
  final _WriteMutex _mutex = _WriteMutex();

  /// Reads the hand-off state for [sub], or the empty state when nothing is
  /// stored for that subject. A corrupt document self-heals to empty —
  /// persistence problems must never block discovery (the list routes are
  /// authoritative anyway).
  Future<Result<AiImportHandoffState>> read(String sub) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.isEmpty) {
        return const Right(AiImportHandoffState.empty);
      }
      final doc = _tryDecodeDoc(raw);
      if (doc == null) {
        // Corrupt-but-parseable shapes self-heal to the empty state — a
        // broken document must never block discovery (the list routes
        // are authoritative anyway).
        await _heal();
        return const Right(AiImportHandoffState.empty);
      }
      return Right(doc.userState(sub).toState());
    } catch (e) {
      return Left(
        ProblemError(code: 'ai_import.handoff_read_failed', detail: '$e'),
      );
    }
  }

  /// Persists [configId] as [sub]'s remembered configuration id
  /// (fast-path/fallback for the next launch).
  Future<Result<void>> saveConfigId(String sub, String configId) => _mutex.run(
    () => _guarded(() async {
      final doc = await _readDoc();
      final entry = doc.userState(sub);
      doc.users[sub] = entry..configId = configId;
      return _writeDoc(doc);
    }),
  );

  /// Remembers [jobId] for [sub]: deduplicated, prepended newest-first,
  /// bounded to [kMaxRememberedJobIds] (oldest dropped).
  Future<Result<void>> rememberJob(String sub, String jobId) => _mutex.run(
    () => _guarded(() async {
      final doc = await _readDoc();
      final entry = doc.userState(sub);
      final jobs = entry.jobIds.toList()..remove(jobId);
      jobs.insert(0, jobId);
      entry.jobIds = jobs.take(kMaxRememberedJobIds).toList();
      doc.users[sub] = entry;
      return _writeDoc(doc);
    }),
  );

  /// Forgets a single job id for [sub] (e.g. a list-route refetch proved the
  /// remembered id gone). A no-op when the id is not remembered.
  Future<Result<void>> forgetJob(String sub, String jobId) => _mutex.run(
    () => _guarded(() async {
      final doc = await _readDoc();
      final entry = doc.userState(sub);
      if (!entry.jobIds.contains(jobId)) {
        return const Right<ProblemError, void>(null);
      }
      entry.jobIds = entry.jobIds.where((id) => id != jobId).toList();
      doc.users[sub] = entry;
      return _writeDoc(doc);
    }),
  );

  /// Removes every subject's state (sign-out / backend-switch reset).
  /// Awaited by `SessionReset` so scheduled writes settle first.
  Future<Result<void>> clear() => _mutex.run(() async {
    try {
      await _storage.delete(key: key);
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'ai_import.handoff_clear_failed', detail: '$e'),
      );
    }
  });

  Future<_HandoffDoc> _readDoc() async {
    final raw = await _storage.read(key: key);
    // A corrupt document reads as empty in mutations: the next write
    // overwrites it (same self-heal discipline as [read]).
    return _tryDecodeDoc(raw) ?? _HandoffDoc();
  }

  /// Runs a mutation body, converting ANY storage fault (including a
  /// failed internal read) into the `handoff_write_failed` value — a
  /// mutation never throws out of the write mutex (AGENTS.md §5).
  Future<Result<void>> _guarded(Future<Result<void>> Function() body) async {
    try {
      return await body();
    } catch (e) {
      return Left(
        ProblemError(code: 'ai_import.handoff_write_failed', detail: '$e'),
      );
    }
  }

  Future<Result<void>> _writeDoc(_HandoffDoc doc) async {
    try {
      await _storage.write(key: key, value: jsonEncode(doc.toJson()));
      return const Right<ProblemError, void>(null);
    } catch (e) {
      return Left(
        ProblemError(code: 'ai_import.handoff_write_failed', detail: '$e'),
      );
    }
  }

  /// Decodes the stored document, or `null` when the payload is corrupt
  /// (wrong shapes). Malformed JSON propagates as [FormatException] to
  /// the caller's catch — a broken document is a storage fault surfaced
  /// as `ai_import.handoff_read_failed`, never silently swallowed as an
  /// empty state on the read path. Never throws itself (no `throw` in
  /// `data/` — AGENTS.md §5).
  static _HandoffDoc? _tryDecodeDoc(String? raw) {
    if (raw == null || raw.isEmpty) return _HandoffDoc();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final usersJson = decoded['users'];
    if (usersJson is! Map<String, dynamic>) return null;
    final users = <String, _HandoffEntry>{};
    for (final entry in usersJson.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      users[entry.key] = _HandoffEntry.fromJson(entry.value);
    }
    return _HandoffDoc(users: users);
  }

  /// Best-effort wipe of a corrupt payload; failures are ignored — the
  /// caller already degrades to the empty state and the next write
  /// overwrites the document.
  Future<void> _heal() async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Intentionally ignored (see above).
    }
  }
}

/// Internal mutable document shape: `{users: {sub: {config_id, job_ids}}}`.
class _HandoffDoc {
  _HandoffDoc({Map<String, _HandoffEntry>? users}) : users = users ?? {};

  final Map<String, _HandoffEntry> users;

  /// The (always-present, mutable) entry for [sub].
  _HandoffEntry userState(String sub) =>
      users.putIfAbsent(sub, _HandoffEntry.new);

  Map<String, dynamic> toJson() => {
    'users': users.map((sub, entry) => MapEntry(sub, entry.toJson())),
  };
}

class _HandoffEntry {
  String? configId;
  List<String> jobIds = <String>[];

  _HandoffEntry({this.configId, List<String>? jobIds}) {
    if (jobIds != null) this.jobIds = jobIds;
  }

  factory _HandoffEntry.fromJson(Map<String, dynamic> json) {
    final entry = _HandoffEntry();
    final configId = json['config_id'];
    if (configId is String) entry.configId = configId;
    final jobIds = json['job_ids'];
    if (jobIds is List) {
      entry.jobIds = jobIds.whereType<String>().toList();
    }
    return entry;
  }

  AiImportHandoffState toState() => AiImportHandoffState(
    configId: configId,
    jobIds: List<String>.unmodifiable(jobIds),
  );

  Map<String, dynamic> toJson() => {
    if (configId != null) 'config_id': configId,
    'job_ids': jobIds,
  };
}

/// FIFO async mutex serializing the store's mutations (same pattern as
/// `ActiveBlockStore`): every guarded body runs to completion before the
/// next invocation's body starts, so overlapping read-modify-write cycles
/// execute in invocation order instead of interleaving. Bodies never throw
/// (every store method returns a `Result`), so the chain is deadlock-free
/// by construction.
class _WriteMutex {
  /// Pending tails, newest last. A list (rather than a single field) so
  /// chaining is a `void` add-statement — a bare `Future`-typed assignment
  /// would trip the discard_result rule.
  final List<Future<void>> _tails = [Future.value()];

  Future<T> run<T>(Future<T> Function() body) async {
    final previous = _tails.last;
    final gate = Completer<void>();
    _tails.add(gate.future);
    await previous;
    try {
      return await body();
    } finally {
      _tails.remove(previous);
      gate.complete();
    }
  }
}
