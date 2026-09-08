// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../core/problem_error.dart';
import '../core/result.dart';

/// Base class for aggregate-boundary repositories in `data/`.
///
/// Each repository wraps the generated API client ([BreakdownApi]) and exposes
/// use-case-shaped methods that return [Result] — never raw `http`/`dio`
/// types, never thrown exceptions. The [run] helper maps a generated call's
/// happy path to `Right(data)` and any [DioException] to `Left(ProblemError)
/// (parsing RFC 9457 problem+json when present).
///
/// Subclasses forward their calls to [api]; [run] guarantees the error path is
/// always a value the caller must handle (enforced by the `discard-result`
/// lint).
abstract class BaseRepository {
  const BaseRepository(this.api);

  /// The generated, Dio-based API client. In production this is backed by the
  /// pinned-CA Dio from `buildApiClient` (see `lib/src/network/api_client.dart`).
  final BreakdownApi api;

  /// Runs a generated client call, returning its decoded body on success or a
  /// [ProblemError] on failure. Never throws. A `null` body (the generated
  /// client surfaces an empty payload as `null`) maps to [dtoInvalidCode]
  /// so a single-object fetch cannot throw a cast error out of the awaited
  /// call (AGENTS.md §5: no throw in `data/`).
  Future<Result<T>> run<T>(
    Future<Response<T>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    try {
      final response = await call();
      final data = response.data;
      if (data == null) {
        return Left(ProblemError(code: dtoInvalidCode));
      }
      return Right(data);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  /// Runs a generated list call, returning its decoded rows on success or a
  /// [ProblemError] on failure. Never throws. A `null` body (the generated
  /// client surfaces an empty payload as `null`) maps to [dtoInvalidCode]
  /// so list fetches cannot throw a cast error out of [run].
  Future<Result<List<T>>> runList<T>(
    Future<Response<BuiltList<T>>> Function() call, {
    String dtoInvalidCode = 'dto.invalid',
  }) async {
    try {
      final response = await call();
      final data = response.data;
      if (data == null) {
        return Left(ProblemError(code: dtoInvalidCode));
      }
      return Right(data.toList());
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }

  /// Fetches every page from a paginated list endpoint, combining rows.
  ///
  /// The backend defaults list endpoints to 50 rows per page. Without
  /// pagination, a >50-row scope would lose rows on snapshot-replace
  /// (issue #385): the partial page is treated as a complete snapshot,
  /// deleting every cached id outside the page. This helper iterates
  /// pages until one returns fewer than [pageSize] rows (last page) or a
  /// page errors, so the combined rows are a complete snapshot.
  ///
  /// [fetchPage] is called with [limit] and [offset] for each page; it
  /// MUST forward those to the generated client so the backend pages
  /// correctly. Returns the combined rows of all pages, or the first
  /// error — a mid-stream error short-circuits (no partial snapshot is
  /// returned, so callers never apply an incomplete page).
  Future<Result<List<T>>> fetchAllPages<T>(
    Future<Response<BuiltList<T>>> Function({
      required int limit,
      required int offset,
    })
    fetchPage, {
    String dtoInvalidCode = 'dto.invalid',
    int pageSize = 100,
  }) async {
    final allRows = <T>[];
    var offset = 0;
    while (true) {
      final result = await runList(
        () => fetchPage(limit: pageSize, offset: offset),
        dtoInvalidCode: dtoInvalidCode,
      );
      if (result.isLeft()) return result;
      final rows = result.getOrElse((_) => <T>[]);
      allRows.addAll(rows);
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return Right(allRows);
  }
}
