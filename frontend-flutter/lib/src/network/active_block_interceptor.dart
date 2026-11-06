// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:dio/dio.dart';

/// Attaches the active-block scope to API traffic (issue #378).
///
/// The backend `authorize_middleware` requires `X-Active-Block` on every
/// block-scoped route (episodes, scenes, shooting days, scene shoots,
/// pieces, characters) and rejects a missing/malformed header with 400.
/// The generated `breakdown_api` client exposes no header parameter for
/// these routes (the header is middleware-enforced, absent from
/// `openapi.yaml`), so this interceptor is the single attachment point —
/// never pass the header per call.
///
/// Behavior:
/// - scope set → `X-Active-Block: <blockId>` on every request (sending it
///   on `Authenticated`-only routes is harmless: the middleware returns
///   before parsing it, so no per-route branching is needed);
/// - scope unset (`null`) → header omitted (seasons/blocks/auth flows keep
///   working headerless);
/// - an empty/blank id is treated as unset (fail-closed, never sends a
///   malformed header the server would 400);
/// - a caller-set `X-Active-Block` header is never overwritten (explicit
///   wins — keeps widget/integration tests that pin the header honest);
/// - `Options.extra[kNoActiveBlockExtra] == true` suppresses the header for
///   that ONE request (issue #829): a block-less AI import is scoped by
///   `X-Declared-Season` alone, and "not sending the header" cannot be expressed
///   by omission because this interceptor attaches it to every call. A blank or
///   sentinel value was rejected — a blank header is a malformed-header `400` on
///   the block-scoped routes and a wire value that means nothing;
///   Never throws.
/// Per-request opt-out key for [ActiveBlockInterceptor] (issue #829).
///
/// `Options.extra[kNoActiveBlockExtra] = true` keeps the ambient
/// `X-Active-Block` OFF one request — the only way to send "this upload has no
/// target block yet". Deliberately an `extra` flag rather than a null/blank
/// header value: the header map cannot express absence here, and a blank header
/// is a malformed-header `400` on every block-scoped route.
const String kNoActiveBlockExtra = 'noActiveBlock';

class ActiveBlockInterceptor extends Interceptor {
  const ActiveBlockInterceptor(this._activeBlockId);

  /// The current scope's block id, or `null` when no scope is set.
  /// Captured per Dio build; [apiDioProvider] rebuilds Dio on scope change.
  final String? _activeBlockId;

  /// The header name enforced by the backend authorization middleware.
  static const headerName = 'X-Active-Block';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final blockId = _activeBlockId;
    final optedOut = options.extra[kNoActiveBlockExtra] == true;
    if (!optedOut &&
        blockId != null &&
        blockId.trim().isNotEmpty &&
        !options.headers.containsKey(headerName)) {
      options.headers[headerName] = blockId;
    }
    handler.next(options);
  }
}
