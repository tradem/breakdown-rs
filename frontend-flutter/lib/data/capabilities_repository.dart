// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/capabilities.dart';
import '../core/result.dart';
import 'base_repository.dart';
import 'cache/seasons_cache_providers.dart';

part 'capabilities_repository.g.dart';

/// Read-only repository for the caller's **global** (deployment-scoped)
/// capabilities (issue #816): `GET /v1/me/capabilities`.
///
/// This is the one wire read that answers "may I manage the AI
/// configuration?" with the predicate the SERVER enforces
/// (`has_active_credential_role`, ADR-027) instead of the season-scoped
/// approximation that also admits `wardrobe_supervisor` and reads a stale
/// scope as a denial. The repository maps the generated DTO onto the
/// client-side [MyCapabilities] value so no widget and no `features/` file
/// needs to import `package:breakdown_api`.
class CapabilitiesRepository extends BaseRepository {
  const CapabilitiesRepository(super.api);

  /// `GET /v1/me/capabilities` — 200 with two booleans.
  ///
  /// A denial is a `Right(false)` (the route never 403s: it is a
  /// self-report), so an `Err` here means the capability is genuinely
  /// UNKNOWN (transport failure, 5xx, unparsable body). Callers must not
  /// render unknown as "no permission".
  Future<Result<MyCapabilities>> fetchMyCapabilities() async {
    final response = await run(
      () => api.getHandlersApi().getMyCapabilities(),
      dtoInvalidCode: 'capabilities.dto_invalid',
    );
    return response.map(
      (dto) => MyCapabilities(
        canManageAiConfig: dto.hasActiveCredentialRole,
        canReadOps: dto.hasActiveOpsRole,
      ),
    );
  }
}

/// The capabilities transport, built from the shared pinned-CA client
/// (single Dio, single token interceptor — same seam as every other
/// `data/` repository).
@riverpod
CapabilitiesRepository capabilitiesRepository(Ref ref) =>
    CapabilitiesRepository(ref.watch(apiClientProvider));
