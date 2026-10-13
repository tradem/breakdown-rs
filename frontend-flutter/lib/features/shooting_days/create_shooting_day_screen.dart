// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import 'create_shooting_day_sheet.dart';

/// Full-screen Create Shooting Day page (issue #624): the quick-create
/// sheet's "Neuer Drehtag" entry pushes this for the active episode.
///
/// Hosts the SAME [CreateShootingDayForm] the in-context FAB sheet uses — one
/// form implementation, two presentations. The episode id comes from the
/// active episode scope (the acted-on `EpisodeView`'s id, CQRS boundary).
class CreateShootingDayScreen extends ConsumerWidget {
  const CreateShootingDayScreen({super.key, required this.episodeId});

  final String episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).shootingDayCreateTitle)),
      body: CreateShootingDayForm(episodeId: episodeId),
    );
  }
}
