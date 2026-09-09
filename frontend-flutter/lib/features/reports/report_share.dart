// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/problem_error.dart';
import '../../core/result.dart';

/// Share seam for report PDFs (testability): production shares via the
/// platform sheet (`share_plus`); tests inject a fake that records the
/// shared file without touching a platform channel.
abstract class ReportShareService {
  /// Shares [file] under [fileName] via the platform sheet. The caller owns
  /// temp cleanup: the staged file is deleted on every exit (share done,
  /// cancelled, or failed) so no partial artifact survives.
  Future<Result<void>> sharePdf(File file, {required String fileName});
}

/// Production share via the platform share sheet (FOSS/store-compliant).
class SharePlusReportShare implements ReportShareService {
  @override
  Future<Result<void>> sharePdf(File file, {required String fileName}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], fileNameOverrides: [fileName]),
      );
      return const Right<ProblemError, void>(null);
    } on Object {
      return const Left(ProblemError(code: 'share.failed'));
    }
  }
}
