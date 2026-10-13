// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations_provider.dart';
import 'create_scene_sheet.dart';

/// Full-screen Create Scene page (issue #624): the quick-create sheet's
/// "Neue Szene" entry pushes this for the active episode.
///
/// Hosts the SAME [CreateSceneForm] the in-context FAB sheet uses — one form
/// implementation, two presentations. The episode id comes from the active
/// episode scope (the acted-on `EpisodeView`'s id, CQRS boundary); the form
/// dispatches through the episode-keyed controller and surfaces failures
/// inline (the form's banner) as well as through the list screen's
/// command-error provider.
class CreateSceneScreen extends ConsumerWidget {
  const CreateSceneScreen({super.key, required this.episodeId});

  final String episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).scenesCreateTitle)),
      body: CreateSceneForm(episodeId: episodeId),
    );
  }
}
