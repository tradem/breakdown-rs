// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny (opencode-go)

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations_provider.dart';
import 'season_scope_chip.dart';

/// Shared empty/failure states of the three shell view roots (issue #610).
///
/// They live in one leaf file so Cast, Script and Schedule/Dispo render the
/// SAME "no season yet" affordance (open the season scope picker) instead
/// of three drifting copies. Every state is a plain-language narrative with
/// a visible label — never an error where the user simply has not chosen a
/// scope yet.

/// "No active season" — an empty state, never an error. Its call to action
/// opens the season scope picker, the one surface that can SET the season
/// (there is no Season destination any more).
class SeasonRequiredView extends StatelessWidget {
  const SeasonRequiredView({super.key, required this.emptyKey});

  final Key emptyKey;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return ListView(
      key: emptyKey,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.video_collection_outlined, size: 48),
        const SizedBox(height: 16),
        Center(child: Text(l10n.castNoSeason)),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            key: const Key('view-pick-season-cta'),
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SeasonScopePickerScreen(),
                ),
              ),
            ),
            child: Text(l10n.castPickSeason),
          ),
        ),
      ],
    );
  }
}

/// A "nothing here yet" narrative for a scoped view (no rows, no failure).
class ViewEmptyState extends StatelessWidget {
  const ViewEmptyState({
    super.key,
    required this.emptyKey,
    required this.message,
    required this.icon,
  });

  final Key emptyKey;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: emptyKey,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 48),
        const SizedBox(height: 16),
        Center(child: Text(message)),
      ],
    );
  }
}

/// A failure state keyed on the stable RFC 9457 problem `code` — never on
/// the server's `detail` text (the backend localizes `detail`; the client
/// explains per code).
class ViewErrorState extends StatelessWidget {
  const ViewErrorState({
    super.key,
    required this.errorKey,
    required this.message,
    this.onRetry,
  });

  final Key errorKey;

  /// Already formatted with the code (per view, e.g.
  /// `l10n.scriptFetchError(code)`).
  final String message;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: errorKey,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 16),
        Center(child: Text(message)),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          Center(
            child: FilledButton.tonal(
              key: const Key('view-retry'),
              onPressed: onRetry,
              child: Text(l10nOf(context).genericProblemAction),
            ),
          ),
        ],
      ],
    );
  }
}

/// The "loaded, but not completely" banner both composed views render above
/// their rows when one episode failed. A partial list is never presented as
/// the complete one.
class ViewPartialNotice extends StatelessWidget {
  const ViewPartialNotice({
    super.key,
    required this.noticeKey,
    required this.message,
  });

  final Key noticeKey;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: noticeKey,
      leading: Icon(
        Icons.warning_amber_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(message),
    );
  }
}
