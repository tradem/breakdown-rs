// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';
import 'outfit_detail_screen.dart';
import 'outfits_controller.dart';
import 'outfits_state.dart';

/// The character's **looks** (`GET /v1/characters/{id}/outfits`).
///
/// A look is what a scene casts; a piece (garment) is only its ingredient, so
/// the list lives on the character, never in the fundus wardrobe. Rows carry
/// the look's own `name`, its variant lineage marker and the piece count.
class OutfitListSection extends ConsumerWidget {
  const OutfitListSection({
    super.key,
    required this.season,
    required this.character,
  });

  final SeasonView season;
  final CharacterView character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    final view = ref.watch(outfitsViewProvider(character.id));
    final state = ref.watch(outfitsControllerProvider(character.id));
    final controller = ref.read(
      outfitsControllerProvider(character.id).notifier,
    );
    // AUTHZ-GATE: the create affordance mirrors the backend's handler-internal
    // season-scoped role check. A pending fetch disables (never denies); a
    // resolved denial renders the narrative and issues no request.
    final membership = ref.watch(currentMembershipProvider(season.id));
    final canManage = switch (membership) {
      AsyncData(:final value) => value.hasActiveCostumeRoleInSeason,
      _ => false,
    };
    final denied = switch (membership) {
      AsyncData(:final value) => !value.hasActiveCostumeRoleInSeason,
      _ => false,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.outfitListTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton.icon(
              key: Key('outfit-create-${character.id}'),
              onPressed: canManage
                  ? () => _create(context, ref, controller)
                  : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.outfitCreateAction),
            ),
          ],
        ),
        if (view.isStale)
          _Banner(
            key: const Key('outfit-list-stale'),
            text: l10n.outfitStaleBanner,
            icon: Icons.cloud_off,
          ),
        if (denied)
          Text(
            l10n.outfitErrorForbidden,
            key: const Key('outfit-denied-narrative'),
          ),
        if (state.commandError case final failure?)
          _Banner(
            key: const Key('outfit-command-error'),
            text: outfitCommandErrorCopy(l10n, failure),
            icon: Icons.error_outline,
            onDismiss: controller.clearError,
          ),
        if (view.error case final ProblemError error)
          _Banner(
            key: const Key('outfit-list-error'),
            text: l10n.outfitListFetchError(error.code),
            icon: Icons.error_outline,
            onRetry: controller.refresh,
          ),
        if (state.rows.isEmpty && view.error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.outfitListEmpty,
              key: Key('outfit-list-empty-${character.id}'),
            ),
          )
        else
          for (final row in state.rows)
            switch (row) {
              ProjectedOutfitRow(:final outfit) => _OutfitTile(
                season: season,
                characterId: character.id,
                outfit: outfit,
                reconciling: false,
              ),
              OptimisticOutfitRow(:final overlay) => _OutfitTile(
                season: season,
                characterId: character.id,
                outfit: overlay.overlay,
                reconciling: true,
              ),
            },
      ],
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    OutfitsController controller,
  ) async {
    final name = await showOutfitNameDialog(
      context,
      title: l10nOf(context).outfitCreateTitle,
    );
    if (name == null) return;
    // Handled: failures surface through the command-error banner.
    final result = await controller.create(seasonId: season.id, name: name);
    result.match<void>((_) {}, (id) {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OutfitDetailScreen(
            season: season,
            characterId: character.id,
            outfitId: id,
          ),
        ),
      );
    });
  }
}

/// One look row: name, variant lineage marker, piece count.
class _OutfitTile extends StatelessWidget {
  const _OutfitTile({
    required this.season,
    required this.characterId,
    required this.outfit,
    required this.reconciling,
  });

  final SeasonView season;
  final String characterId;
  final OutfitView outfit;
  final bool reconciling;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final pieces = outfit.pieces.length;
    return ListTile(
      key: Key('outfit-row-${outfit.id}'),
      leading: Icon(
        BreakdownMaterialIcons.forCostumeCategory(
          outfit.pieces.isEmpty ? null : outfit.pieces.first.categoryName,
        ),
      ),
      title: Text(outfit.name),
      subtitle: Text(
        outfit.variantOf == null
            ? l10n.outfitPieceCount(pieces)
            : '${l10n.outfitPieceCount(pieces)} · ${l10n.outfitVariantMarker}',
      ),
      trailing: reconciling
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OutfitDetailScreen(
            season: season,
            characterId: characterId,
            outfitId: outfit.id,
          ),
        ),
      ),
    );
  }
}

/// The shared look-name dialog (create + rename): a blank name is rejected by
/// the aggregate, so the save affordance stays disabled until it is non-blank.
///
/// The dialog owns its text controller (created in `initState` and disposed
/// with the state), so a closing animation can never touch a disposed
/// controller.
Future<String?> showOutfitNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (dialogContext) => _OutfitNameDialog(title: title, initial: initial),
);

class _OutfitNameDialog extends StatefulWidget {
  const _OutfitNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_OutfitNameDialog> createState() => _OutfitNameDialogState();
}

class _OutfitNameDialogState extends State<_OutfitNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final valid = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('outfit-name-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.outfitNameLabel),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (valid) Navigator.of(context).pop(_controller.text.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const Key('outfit-name-save'),
          onPressed: valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.icon,
    this.onRetry,
    this.onDismiss,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListTile(
      leading: Icon(icon),
      title: Text(text),
      trailing: onRetry != null
          ? TextButton(
              onPressed: onRetry,
              child: Text(l10nOf(context).commonRetry),
            )
          : onDismiss != null
          ? IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
              tooltip: l10nOf(context).commonClose,
            )
          : null,
    ),
  );
}
