// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_providers.dart';
import '../../design/spacing.dart';

/// Source repository linked from the About dialog (spec
/// `flutter-app-dialogs`: AGPL-3.0 license + source link).
const String kSourceRepositoryUrl = 'https://github.com/tradem/breakdown-rs';

/// Opens [url] in the platform browser. Injectable seam: `url_launcher`
/// hits platform channels, which do not exist in `flutter test`.
typedef LaunchUri = Future<bool> Function(Uri url);

Future<bool> _defaultLaunchUri(Uri url) => launchUrl(url);

/// Shows the About/Info dialog (spec `flutter-app-dialogs`, design.md §6).
Future<void> showAppInfoDialog(BuildContext context, {LaunchUri? launchUri}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AppInfoDialog(launchUri: launchUri),
    );

/// About/Info dialog content (spec `flutter-app-dialogs`):
/// (a) application version, (b) license (GNU AGPL-3.0) with a source link,
/// (c) AI usage notice. Static client copy, l10n-ready; scheme roles and
/// [AppSpacing] tokens only.
///
/// The version comes from `--dart-define=APP_VERSION` (CI-injected from
/// pubspec; `AppConfig.appVersion`), falling back to `'unknown'` for local
/// builds — never hardcoded.
class AppInfoDialog extends ConsumerWidget {
  const AppInfoDialog({super.key, LaunchUri? launchUri})
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
          const SnackBar(content: Text('Could not open the source link.')),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersion = ref.watch(appConfigProvider).appVersion;
    return AlertDialog(
      key: const Key('info-dialog'),
      title: const Text('About Breakdown'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('info-version'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tag),
              title: const Text('Version'),
              subtitle: Text(appVersion),
            ),
            ListTile(
              key: const Key('info-license'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.balance),
              title: const Text('License'),
              subtitle: const Text(
                'GNU Affero General Public License v3.0. This is free '
                'software: you may run, study, share, and modify it.',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('info-source-link'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _openSourceLink(context),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('View source'),
              ),
            ),
            const SizedBox(height: AppSpacing.space8),
            ListTile(
              key: const Key('info-ai-notice'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('AI usage'),
              subtitle: const Text(
                'Schedule and script import features send text you provide '
                'to a server-side configured AI provider when you explicitly '
                'submit it. This app never communicates with an AI provider '
                'directly.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('info-close'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
