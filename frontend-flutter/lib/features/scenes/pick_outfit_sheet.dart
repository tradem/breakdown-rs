// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';

import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';

/// Opens the OUTFIT picker for a scene outfit beat (issue #546; the look
/// replaced the bare costume when the wardrobe split into Piece + Outfit): a
/// centered dialog on macOS (side-sheet width cap 480 dp) and a bottom
/// sheet on Android — the create-sheet convention, never a naked
/// `showDialog` list.
///
/// The picker is a SELECTION, not an editor: it returns the picked outfit id
/// plus the optional wardrobe cue note. Editing the look itself stays on the
/// outfit screens. The label is the look's own `name` (the aggregate requires
/// a non-blank one) — never a name invented from a random piece detail.
Future<({String outfitId, String? note})?> showPickOutfitSheet(
  BuildContext context,
  List<OutfitView> outfits,
) {
  final isMacOs = Theme.of(context).platform == TargetPlatform.macOS;
  if (isMacOs) {
    return showDialog<({String outfitId, String? note})>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _PickOutfitForm(outfits: outfits),
        ),
      ),
    );
  }
  return showModalBottomSheet<({String outfitId, String? note})>(
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
        child: _PickOutfitForm(outfits: outfits),
      ),
    ),
  );
}

class _PickOutfitForm extends StatefulWidget {
  const _PickOutfitForm({required this.outfits});

  final List<OutfitView> outfits;

  @override
  State<_PickOutfitForm> createState() => _PickOutfitFormState();
}

class _PickOutfitFormState extends State<_PickOutfitForm> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _pick(OutfitView outfit) {
    final note = _noteController.text.trim();
    Navigator.of(context)
        .pop((outfitId: outfit.id, note: note.isEmpty ? null : note));
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
              itemCount: widget.outfits.length,
              itemBuilder: (context, i) {
                final outfit = widget.outfits[i];
                // The look's own name is the identity; the piece count plus a
                // variant marker help the crew tell look-alikes apart.
                final pieceCount = outfit.pieces.length;
                return ListTile(
                  key: Key('pick-outfit-${outfit.id}'),
                  leading: Icon(
                    BreakdownMaterialIcons.forCostumeCategory(
                      outfit.pieces.isEmpty
                          ? null
                          : outfit.pieces.first.categoryName,
                    ),
                  ),
                  title: Text(
                    outfit.name.trim().isEmpty
                        ? l10n.costumeTileLabelFallback
                        : outfit.name,
                  ),
                  subtitle: Text(
                    outfit.variantOf == null
                        ? '$pieceCount'
                        : '$pieceCount · ${l10n.costumeDetailReassign}',
                  ),
                  onTap: () => _pick(outfit),
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
