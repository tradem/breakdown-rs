// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_providers.dart';
import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import 'ai_disclosure_screen.dart';

/// Source repository linked from the About screen (spec
/// `flutter-app-dialogs`: AGPL-3.0 license + source link).
const String kSourceRepositoryUrl = 'https://github.com/tradem/breakdown-rs';

/// Opens [url] in the platform browser. Injectable seam: `url_launcher`
/// hits platform channels, which do not exist in `flutter test`.
typedef LaunchUri = Future<bool> Function(Uri url);

Future<bool> _defaultLaunchUri(Uri url) => launchUrl(url);

/// Shows the About surface (spec `flutter-app-dialogs`, issue #653): a
/// FULL SCREEN route — explicitly not a dialog. The account drawer's
/// *Über die App* entry pushes this screen onto the active destination's
/// navigator.
void showAppInfoScreen(BuildContext context, {LaunchUri? launchUri}) {
  // Fire-and-forget navigation (no result consumed).
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppInfoScreen(launchUri: launchUri),
      ),
    ),
  );
}

/// About/Info screen (spec `flutter-app-dialogs`, issue #653): a
/// full-screen route with app-bar back navigation carrying
/// (a) application version, (b) license (GNU AGPL-3.0) with a source
/// link, (c) AI usage notice. Static client copy, l10n-ready; scheme
/// roles and [AppSpacing] tokens only.
///
/// The version comes from `--dart-define=APP_VERSION` (CI-injected from
/// pubspec; `AppConfig.appVersion`), falling back to `'unknown'` for local
/// builds — never hardcoded.
///
/// Content keys are the former dialog's (`info-version`, `info-license`,
/// `info-source-link`, `info-ai-notice`) so the migrated tests assert the
/// same content contract the dialog carried.
class AppInfoScreen extends ConsumerWidget {
  const AppInfoScreen({super.key, LaunchUri? launchUri})
    : _launchUri = launchUri ?? _defaultLaunchUri;

  final LaunchUri _launchUri;

  Future<void> _openSourceLink(BuildContext context) async {
    bool launched = false;
    try {
      launched = await _launchUri(Uri.parse(kSourceRepositoryUrl));
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10nOf(context).infoSourceError)),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersion = ref.watch(appConfigProvider).appVersion;
    final l10n = l10nOf(context);
    return Scaffold(
      key: const Key('app-info-screen'),
      appBar: AppBar(
        key: const Key('app-info-appbar'),
        title: Text(l10n.infoTitle),
      ),
      body: ListView(
        key: const Key('app-info-list'),
        padding: const EdgeInsets.all(AppSpacing.space16),
        children: [
          ListTile(
            key: const Key('info-version'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tag),
            title: Text(l10n.infoVersion),
            subtitle: Text(appVersion),
          ),
          ListTile(
            key: const Key('info-license'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.balance),
            title: Text(l10n.infoLicense),
            subtitle: Text(l10n.infoLicenseBody),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('info-source-link'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _openSourceLink(context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10n.infoSource),
            ),
          ),
          const SizedBox(height: AppSpacing.space8),
          ListTile(
            key: const Key('info-ai-notice'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smart_toy_outlined),
            title: Text(l10n.infoAiUsage),
            subtitle: Text(l10n.infoAiBody),
            // Doorway to the dedicated About-AI disclosure screen (spec
            // `flutter-app-dialogs` "About Screen Contents → About-AI
            // screen", issue #538): the notice remains AND navigates.
            // The screen stays in the stack beneath the disclosure.
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Fire-and-forget navigation (no result consumed).
              unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiDisclosureScreen(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
