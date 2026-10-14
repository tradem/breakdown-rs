// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/spacing.dart';
import '../../l10n/app_localizations_provider.dart';
import 'app_info_controller.dart';

/// Bundled technology logos for the "Auf der Schulter von Riesen" section
/// (issue #655, user request): the free technologies this app is built on.
/// The Rust logo is a monochrome glyph, so it is tinted with the theme's
/// `onSurface` to stay visible in both brightness modes; the Flutter logo is
/// multicolored and renders as-is.
const String kRustLogoAsset = 'assets/graphics/rust_logo.svg';
const String kFlutterLogoAsset = 'assets/graphics/flutter_logo.svg';

/// Font-size tiers of the word cloud. A term's tier is derived from a
/// deterministic FNV-1a hash of its name ([fnv1a]) — never from
/// `String.hashCode`, whose algorithm is a runtime implementation detail.
const List<double> _kCloudFontSizes = [26, 21, 17, 14];

/// FNV-1a (32 bit) over the UTF-8 bytes of [s]. Pure-Dart and stable across
/// platforms/runs, so the word cloud is deterministic and golden-stable.
int fnv1a(String s) {
  var hash = 0x811c9dc5;
  for (final code in s.codeUnits) {
    hash ^= code & 0xff;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= (code >> 8) & 0xff;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// The credits screen (issue #655): reachable from the About screen, renders
/// all co-authors — deduped LLM models + the human contributors — as a
/// deterministic word cloud, plus the "Auf der Schulter von Riesen" section
/// with the bundled Rust/Flutter logos.
///
/// Determinism: terms are the payload order (backend-sorted), layout is a
/// flow of chips with hash-derived font tiers — no wall-clock, no
/// `String.hashCode`, no randomness — so the golden tests are stable.
/// Accessibility: every cloud term carries a full semantic label
/// ("name, role(s)" for humans, "name, KI-Co-Autor von provider" for LLMs);
/// the painted word is never the only reachable representation.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(metaCreditsProvider);
    final l10n = l10nOf(context);
    return Scaffold(
      key: const Key('credits-screen'),
      appBar: AppBar(
        key: const Key('credits-appbar'),
        title: Text(l10n.creditsTitle),
      ),
      body: ListView(
        key: const Key('credits-list'),
        padding: const EdgeInsets.all(AppSpacing.space16),
        children: [
          Text(
            l10n.creditsCloudTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(l10n.creditsCloudBody),
          const SizedBox(height: AppSpacing.space12),
          switch (credits) {
            // Graceful degradation (same pattern as the About backend
            // versions block): a failed or in-flight fetch never crashes
            // the screen — honest error copy or a bounded spinner.
            AsyncData(:final value) => _WordCloud(
              entries: value.credits.toList(),
            ),
            _ when credits.hasError => Text(
              l10n.creditsError,
              key: const Key('credits-error'),
            ),
            _ => const Center(
              key: Key('credits-loading'),
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.space24),
                child: CircularProgressIndicator(),
              ),
            ),
          },
          const SizedBox(height: AppSpacing.space24),
          const _ShouldersSection(),
        ],
      ),
    );
  }
}

/// The word cloud of one payload: deduped LLM terms + human terms.
class _WordCloud extends StatelessWidget {
  const _WordCloud({required this.entries});

  final List<MetaCreditsEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Wrap(
      key: const Key('credits-cloud'),
      spacing: AppSpacing.space12,
      runSpacing: AppSpacing.space12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in entries)
          entry.provider != null
              ? _LlmTerm(
                  entry: entry,
                  semanticLabel: l10n.creditsSemanticLlm(
                    entry.name,
                    entry.provider!,
                  ),
                )
              : _HumanTerm(
                  entry: entry,
                  semanticLabel: l10n.creditsSemanticHuman(
                    entry.name,
                    entry.roles.join(', '),
                  ),
                ),
      ],
    );
  }
}

/// One painted LLM term: the model name at its hash-derived tier.
/// `excludeSemantics` swaps the bare painted text for the full label.
class _LlmTerm extends StatelessWidget {
  const _LlmTerm({required this.entry, required this.semanticLabel});

  final MetaCreditsEntry entry;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tier = fnv1a(entry.name) % _kCloudFontSizes.length;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      container: true,
      child: Text(
        entry.name,
        key: Key('credit-term-${entry.name}'),
        style: TextStyle(
          fontSize: _kCloudFontSizes[tier],
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// One painted human term: the handle in the accent color plus the role
/// caption underneath — the visual distinction the spec asks for.
class _HumanTerm extends StatelessWidget {
  const _HumanTerm({required this.entry, required this.semanticLabel});

  final MetaCreditsEntry entry;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tier = fnv1a(entry.name) % _kCloudFontSizes.length;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      container: true,
      child: Column(
        key: Key('credit-term-${entry.name}'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.name,
            style: TextStyle(
              fontSize: _kCloudFontSizes[tier],
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          for (final role in entry.roles)
            Text(
              role,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Auf der Schulter von Riesen" (issue #655, user request): the free
/// technologies the app is built on, with their bundled logos.
class _ShouldersSection extends StatelessWidget {
  const _ShouldersSection();

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return Column(
      key: const Key('credits-shoulders'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.creditsShouldersTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.space4),
        Text(l10n.creditsShouldersBody),
        const SizedBox(height: AppSpacing.space12),
        Wrap(
          spacing: AppSpacing.space24,
          runSpacing: AppSpacing.space12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: l10n.creditsRustLabel,
              excludeSemantics: true,
              child: Row(
                key: const Key('credits-rust-logo'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    kRustLogoAsset,
                    height: 40,
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space8),
                  Flexible(child: Text(l10n.creditsRustLabel)),
                ],
              ),
            ),
            Semantics(
              label: l10n.creditsFlutterLabel,
              excludeSemantics: true,
              child: Row(
                key: const Key('credits-flutter-logo'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(kFlutterLogoAsset, height: 34),
                  const SizedBox(width: AppSpacing.space8),
                  Flexible(child: Text(l10n.creditsFlutterLabel)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
