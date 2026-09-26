// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/ai_import_providers.dart';
import '../../l10n/app_localizations_provider.dart';
import 'info_dialog.dart';

/// The dedicated About-AI disclosure screen (spec `flutter-app-dialogs`
/// "Info Dialog Contents → About-AI screen", user decision of issue #538).
///
/// Six content blocks: purpose, data flow, provider/model naming (from the
/// caller's configured NON-secret `AiConfigView` — honest degradation state
/// when none is configured or discovery fails), payload retention (7-day
/// GC), the EU AI Act reference, and the AGPL/license + source link. Static
/// copy + theme roles only; every visible string is ARB-catalog copy
/// (inline-copy gate). Screen spec: `docs/design/screens/about-ai.md`.
class AiDisclosureScreen extends ConsumerWidget {
  const AiDisclosureScreen({super.key, this.launchUri});

  /// Injectable `url_launcher` seam (same pattern as the About dialog):
  /// platform channels do not exist in `flutter test`.
  final LaunchUrl? launchUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final naming = ref.watch(configuredAiNamingProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).aiDisclosureTitle)),
      body: ListView(
        key: const Key('ai-disclosure-screen'),
        padding: const EdgeInsets.all(16),
        children: [
          _Block(
            key: const Key('ai-disclosure-purpose'),
            icon: Icons.psychology_alt_outlined,
            title: l10nOf(context).aiDisclosurePurposeTitle,
            body: l10nOf(context).aiDisclosurePurposeBody,
          ),
          _Block(
            key: const Key('ai-disclosure-flow'),
            icon: Icons.route_outlined,
            title: l10nOf(context).aiDisclosureFlowTitle,
            body: l10nOf(context).aiDisclosureFlowBody,
          ),
          // Block (3): provider/model naming — NEVER an invented name and
          // never a spinner trap: the block renders its copy in every
          // state. Configured: the wire naming (provider + assistant
          // model — non-secret only; no vault reference, no prompt texts).
          // Unconfigured or discovery failure: the honest degradation
          // copy. While the discovery is still loading: the honest loading
          // note that re-renders to the wire naming as soon as it resolves.
          naming.when(
            data: (configured) => _namingBlock(context, configured),
            error: (_, _) => _namingBlock(context, null),
            loading: () => _namingBlock(context, null, loading: true),
            skipLoadingOnReload: true,
          ),
          _Block(
            key: const Key('ai-disclosure-retention'),
            icon: Icons.schedule_outlined,
            title: l10nOf(context).aiDisclosureRetentionTitle,
            body: l10nOf(context).aiDisclosureRetentionBody,
          ),
          _Block(
            key: const Key('ai-disclosure-act'),
            icon: Icons.balance,
            title: l10nOf(context).aiDisclosureActTitle,
            body: l10nOf(context).aiDisclosureActBody,
          ),
          _Block(
            key: const Key('ai-disclosure-source'),
            icon: Icons.balance,
            title: l10nOf(context).infoLicense,
            body: l10nOf(context).infoLicenseBody,
            footer: TextButton.icon(
              key: const Key('ai-disclosure-source-link'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _openSourceLink(context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(l10nOf(context).infoSource),
            ),
          ),
        ],
      ),
    );
  }

  /// Block (3) variant: renders the configured wire naming when an
  /// `AiConfigView` exists; the unconfigured / honest-loading copy
  /// otherwise (`null` configured + [loading] toggles which body).
  Widget _namingBlock(
    BuildContext context,
    AiConfigView? configured, {
    bool loading = false,
  }) => _Block(
    key: const Key('ai-disclosure-naming'),
    icon: Icons.smart_toy_outlined,
    title: l10nOf(context).aiDisclosureNamingTitle,
    body: configured == null
        ? (loading
              ? l10nOf(context).aiDisclosureNamingBodyLoading
              : l10nOf(context).aiDisclosureNamingBodyUnconfigured)
        // gen-l10n positional order: placeholders are bound ALPHABETICALLY
        // (model, provider), not in the template's appearance order — pass
        // the model first (verified against the generated de/en bodies).
        : l10nOf(context).aiDisclosureNamingBodyConfigured(
            configured.assistantModel,
            configured.provider.name,
          ),
  );

  /// Shares the About dialog's source-link: `url_launcher` platform
  /// channels do not exist in `flutter test` (the injectable [launchUri]
  /// seam covers tests).
  Future<void> _openSourceLink(BuildContext context) async {
    bool launched = false;
    try {
      launched = await (launchUri ?? launchUrl)(
        Uri.parse(kSourceRepositoryUrl),
      );
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
}

/// Injected launcher signature shared with the About dialog's seam.
typedef LaunchUrl = Future<bool> Function(Uri url);

/// One disclosure content block: icon surface + title + body (+ optional
/// footer affordance). `tertiaryContainer` surface keeps the whole screen
/// visually distinct (EU AI Act transparency framing, issue #538).
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.tertiary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(body),
          ?footer,
        ],
      ),
    ),
  );
}
