// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fpdart/fpdart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/problem_error.dart';
import '../core/result.dart';
import 'oidc_client.dart';

/// Opens [url] in the platform browser. Returns `true` when the URL was
/// handed off. Injectable seam: tests script launch outcomes without a
/// device (the platform implementation itself is covered on-device —
/// design.md §3 — since neither Custom Tabs nor deep links exist in
/// `flutter test`).
typedef LaunchBrowser = Future<bool> Function(Uri url);

/// Opens a fresh deep-link subscription. Injectable seam for the same
/// reason: one subscription per in-flight sign-in, cancelled on completion.
typedef OpenLinkStream = Stream<Uri> Function();

/// Default browser leg: Custom Tabs on Android (`inAppBrowserView`) and the
/// platform-default browser elsewhere, launched only on explicit user action
/// (the sign-in button — store-compliant, design.md §3).
Future<bool> _defaultLaunchBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.inAppBrowserView);

/// Default redirect leg: the OS-delivered deep-link stream.
Stream<Uri> _defaultOpenLinkStream() => AppLinks().uriLinkStream;

/// Sentinel for a deep-link stream failure (mapped to
/// `oidc.redirect_capture_failed` at the `Result` boundary — never thrown
/// past the `AuthorizationUi.launch` call).
class _CaptureFailed {
  const _CaptureFailed();
}

/// Production [AuthorizationUi] (spec `flutter-auth-shell`, design.md §3).
///
/// Flow: subscribe to the deep-link stream FIRST (a warm Custom Tab may
/// deliver the redirect before `launchUrl` returns), then open the
/// authorization URL, then await the first redirect that matches the
/// configured [redirectUri] by scheme, host, port, and path (query
/// parameters carry the code/state and are preserved). Unrelated links —
/// including same-scheme ones — are ignored while waiting, so a stray
/// deep link can neither complete nor abort the flow. The subscription is
/// cancelled on every exit path — no listener survives the in-flight
/// sign-in.
///
/// Exactly three platform failure modes (design.md §3), each its own `Err`
/// with a stable `oidc.*` code; the login screen renders localized copy
/// keyed on it. Anything else (notably the `state` CSRF check) is NOT a
/// platform concern: the captured URI is returned verbatim and
/// `OidcClient` owns the `state` comparison (`oidc.state_mismatch`).
class PlatformAuthorizationUi implements AuthorizationUi {
  const PlatformAuthorizationUi({
    required this.redirectUri,
    this.redirectTimeout = const Duration(minutes: 5),
    LaunchBrowser? launchBrowser,
    OpenLinkStream? openLinkStream,
  }) : _launchBrowser = launchBrowser ?? _defaultLaunchBrowser,
       _openLinkStream = openLinkStream ?? _defaultOpenLinkStream;

  /// The configured `OIDC_REDIRECT_URI` (scheme, host, port, and path
  /// select the redirect; the query carries code/state).
  final Uri redirectUri;

  /// How long to wait for the redirect before failing with
  /// `oidc.redirect_timeout` (user interacts with the IdP in between).
  final Duration redirectTimeout;

  final LaunchBrowser _launchBrowser;
  final OpenLinkStream _openLinkStream;

  /// Whether [uri] is the configured IdP callback (scheme, host, port,
  /// and path match; the query is preserved verbatim for `OidcClient`).
  bool _isRedirect(Uri uri) =>
      uri.scheme == redirectUri.scheme &&
      uri.host == redirectUri.host &&
      uri.port == redirectUri.port &&
      uri.path == redirectUri.path;

  @override
  Future<Result<Uri>> launch(Uri authorizationUrl) async {
    final received = Completer<Uri>();
    var settled = false;
    late final StreamSubscription<Uri> sub;
    sub = _openLinkStream().listen(
      (uri) {
        // Only the configured callback completes the flow; unrelated
        // deep links are ignored (the listener never fires for them — a
        // non-matching redirect is a capture failure by absence, and the
        // timeout below bounds the wait).
        if (!settled && _isRedirect(uri)) {
          settled = true;
          received.complete(uri);
        }
      },
      onError: (_) {
        if (!settled) {
          settled = true;
          received.completeError(const _CaptureFailed());
        }
      },
    );

    Future<Result<Uri>> finish(Result<Uri> result) async {
      settled = true;
      await sub.cancel();
      return result;
    }

    bool launched;
    try {
      launched = await _launchBrowser(authorizationUrl);
    } catch (_) {
      // `launchUrl` returns `false` OR throws (`PlatformException`,
      // `ArgumentError` for non-http(s) authorization endpoints) — both
      // are the same platform failure mode.
      return finish(
        const Left(ProblemError(code: 'oidc.browser_launch_failed')),
      );
    }
    if (!launched) {
      return finish(
        const Left(ProblemError(code: 'oidc.browser_launch_failed')),
      );
    }

    final result = await received.future
        .then<Result<Uri>>(
          Right.new,
          onError: (_) => const Left<ProblemError, Uri>(
            ProblemError(code: 'oidc.redirect_capture_failed'),
          ),
        )
        .timeout(
          redirectTimeout,
          onTimeout: () {
            settled = true;
            return const Left(ProblemError(code: 'oidc.redirect_timeout'));
          },
        );
    return finish(result);
  }
}
