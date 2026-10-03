// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';
import '../costumes/costume_identity.dart';

/// Opens the costume picker for a scene costume beat (issue #546): a
/// centered dialog on macOS (side-sheet width cap 480 dp) and a bottom
/// sheet on Android — the create-sheet convention, never a naked
/// `showDialog` list.
///
/// The picker is a SELECTION, not an editor: it returns the picked costume
/// id plus the optional wardrobe cue note. In-place editing stays on the
/// costume detail screen (issue #545). Tile identity uses the SAME helper
/// as the costume grid tile (`costumeTileIdentity` — never a name invented
/// from a random detail).
Future<({String costumeId, String? note})?> showPickCostumeSheet(
  BuildContext context,
  List<CostumeView> costumes,
) {
  final isMacOs = Theme.of(context).platform == TargetPlatform.macOS;
  if (isMacOs) {
    return showDialog<({String costumeId, String? note})>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _PickCostumeForm(costumes: costumes),
        ),
      ),
    );
  }
  return showModalBottomSheet<({String costumeId, String? note})>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
        ),
        child: _PickCostumeForm(costumes: costumes),
      ),
    ),
  );
}

class _PickCostumeForm extends StatefulWidget {
  const _PickCostumeForm({required this.costumes});

  final List<CostumeView> costumes;

  @override
  State<_PickCostumeForm> createState() => _PickCostumeFormState();
}

class _PickCostumeFormState extends State<_PickCostumeForm> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _pick(CostumeView costume) {
    final note = _noteController.text.trim();
    Navigator.of(context)
        .pop((costumeId: costume.id, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.sceneDetailPickCostumeTitle,
              key: const Key('pick-costume-title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('scene-costume-note'),
              controller: _noteController,
              decoration: InputDecoration(
                labelText: l10n.sceneDetailCostumeCueHint,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.costumes.length,
              itemBuilder: (context, i) {
                final costume = widget.costumes[i];
                final identity = costumeTileIdentity(costume);
                return ListTile(
                  key: Key('pick-costume-${costume.id}'),
                  leading: Icon(
                    BreakdownMaterialIcons.forCostumeCategory(
                      identity.categoryName,
                    ),
                  ),
                  title: Text(
                    costumeDisplayName(costume, l10n.costumeTileLabelFallback),
                  ),
                  subtitle: Text(
                    identity.categoryName ?? l10n.costumeCategoryUncategorized,
                  ),
                  onTap: () => _pick(costume),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
