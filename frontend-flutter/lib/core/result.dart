// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: longcat-2.0 (opencode-go)

import 'package:fpdart/fpdart.dart';

import 'problem_error.dart';

/// A fallible result: `Right(T)` on success, `Left(ProblemError)` on failure.
///
/// Repositories in `data/` return this type so callers must explicitly handle
/// the error branch (the `discard-result` lint forbids swallowing it). Never
/// surface raw `http`/`dio` types or throw from `data/` — errors are values.
typedef Result<T> = Either<ProblemError, T>;
