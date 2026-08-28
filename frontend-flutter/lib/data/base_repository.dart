// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
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
  /// [ProblemError] on failure. Never throws.
  Future<Result<T>> run<T>(Future<Response<T>> Function() call) async {
    try {
      final response = await call();
      return Right(response.data as T);
    } on DioException catch (e) {
      return Left(problemErrorFromDio(e));
    }
  }
}
