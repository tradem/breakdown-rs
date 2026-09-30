// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'dart:async';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../auth/auth_providers.dart';
import '../../auth/membership/capability.dart';
import '../../auth/membership/membership_providers.dart';
import '../../core/problem_error.dart';
import '../../data/photo_repository.dart';
import '../../design/material_icons.dart';
import '../../l10n/app_localizations_provider.dart';
import '../characters/characters_controller.dart';
import '../costume_categories/costume_categories_controller.dart';
import '../photos/capture.dart';
import '../photos/prepare.dart';
import '../photos/widgets/photo_gallery.dart';
import 'costumes_controller.dart';
import 'costumes_state.dart';
import 'widgets/costumes_widgets.dart';

part 'costume_detail_screen.g.dart';

/// Foreground-only variant watch for one costume (D5): bounded-backoff
/// costume refetches while subscribed; terminal variants end the pass; the
/// subscription dies with the screen (no background polling).
@riverpod
Stream<PhotoWatchEvent> costumePhotoWatch(
  Ref ref,
  String seasonId,
  String costumeId,
) async* {
  final photos = ref.watch(costumePhotoRepositoryProvider);
  final costumes = ref.watch(costumeRepositoryProvider);
  yield* photos.watch(
    costumeId,
    () => costumes.getAndCache(seasonId, costumeId),
  );
}

/// `CostumeDetailScreen` is retained as a compatibility entry point for
/// callers that still provide a route. New overview navigation uses
/// [CostumeDetailPanel] directly, keeping editing on the first screen.
class CostumeDetailScreen extends ConsumerWidget {
  const CostumeDetailScreen({
    super.key,
    required this.season,
    required this.costumeId,
  });

  final SeasonView season;
  final String costumeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final controller = ref.read(costumesControllerProvider(season.id).notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10nOf(context).costumeDetailTitle)),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          key: Key('costume-detail-$costumeId'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            CostumeDetailPanel(
              season: season,
              costumeId: costumeId,
              showCommandError: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// The costume identity editor embedded below the overview tile grid.
///
/// It deliberately contains the existing assignment, detail, notes, and photo
/// controls so the old detail route is no longer required for editing.
class CostumeDetailPanel extends ConsumerWidget {
  const CostumeDetailPanel({
    super.key,
    required this.season,
    required this.costumeId,
    this.showCommandError = false,
  });

  final SeasonView season;
  final String costumeId;
  final bool showCommandError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the variant watch alive while the panel is visible; terminal
    // events refresh the costume cache and rebuild the projection.
    ref.listen(costumePhotoWatchProvider(season.id, costumeId), (_, _) {});
    final state = ref.watch(costumesControllerProvider(season.id));
    final controller = ref.read(costumesControllerProvider(season.id).notifier);
    final costume = _resolveCostume(state);
    if (costume == null) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: CircularProgressIndicator(key: Key('costume-loading')),
        ),
      );
    }
    return Column(
      key: Key('costume-editor-body-$costumeId'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text(
            l10nOf(context).costumeDetailTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 16),
        if (showCommandError)
          if (state.commandError case final failure?)
            _InlineError(
              text: costumeCommandErrorCopy(l10nOf(context), failure),
              onDismiss: controller.dismissCommandError,
            ),
        _AssignmentSection(season: season, costume: costume),
        const Divider(height: 32),
        // Issue #543: the costume's single category sits in the identity
        // section ABOVE the details (details are pure description now).
        CostumeCategorySection(season: season, costume: costume),
        const Divider(height: 32),
        // Identity is primary; notes are deliberately secondary.
        _DetailsSection(season: season, costume: costume),
        const Divider(height: 32),
        _NotesSection(season: season, costume: costume),
        const Divider(height: 32),
        _PhotosSection(season: season, costume: costume),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Resolves the effective row: the fence-held overlay first, then the
  /// projected/cached row. The overlay version is the freshest command ack.
  CostumeView? _resolveCostume(CostumesScreenState state) {
    for (final o in state.overlays) {
      if (o.id == costumeId) return o.overlay;
    }
    for (final c in state.cachedRows) {
      if (c.id == costumeId) return c;
    }
    return null;
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const Key('costume-detail-error'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: l10nOf(context).episodesDismiss,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

/// Assignment section: current character (read-DTO join) + picker.
///
/// // AUTHZ-GATE: the picker's confirm path runs the membership capability
/// check inside the controller before any network call.
class _AssignmentSection extends ConsumerWidget {
  const _AssignmentSection({required this.season, required this.costume});

  final SeasonView season;
  final CostumeView costume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final characters = ref.watch(charactersViewProvider(season.id));
    final names = {for (final c in characters.rows) c.id: c.name};
    // Fence-held overlays render the optimistic key (Gherkin contract);
    // reconciled rows render the authoritative key.
    final controllerState = ref.watch(costumesControllerProvider(season.id));
    final fenceHeld = controllerState.overlays.any((o) => o.id == costume.id);
    final assignedId = fenceHeld
        ? controllerState.overlays
              .firstWhere((o) => o.id == costume.id)
              .overlay
              .characterId
        : costume.characterId;
    final assignedName = assignedId == null ? null : names[assignedId];
    // Client-side denial renders the localized 403 narrative here (the
    // controller never issues the request when denied).
    final membership = ref.watch(currentMembershipProvider(season.id));
    final denied = switch (membership) {
      AsyncData(:final value) => !value.canAssignCostumes,
      _ => false,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10nOf(context).costumeDetailCharacter,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (denied)
          Text(
            l10nOf(context).costumeDetailAssignGate,
            key: const Key('costume-assign-denied'),
          )
        else
          ListTile(
            // Gherkin contract keys: optimistic vs projected assignment.
            key: Key(
              fenceHeld
                  ? 'overlay-assign-${costume.id}-$assignedId'
                  : assignedId == null
                  ? 'costume-unassigned-${costume.id}'
                  : 'assigned-${costume.id}-$assignedId',
            ),
            contentPadding: EdgeInsets.zero,
            title: Text(
              assignedName ?? l10nOf(context).costumeDetailUnassigned,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (costume.characterId != null)
                  IconButton(
                    key: Key('costume-unassign-${costume.id}'),
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: l10nOf(context).costumeDetailUnassignTooltip,
                    onPressed: () => _confirmUnassign(context, ref),
                  ),
                FilledButton.tonal(
                  key: Key(
                    'assign-costume-${costume.id}-${costume.characterId ?? "none"}',
                  ),
                  onPressed: characters.rows.isEmpty
                      ? null
                      : () => _pickCharacter(context, ref, characters.rows),
                  child: Text(
                    costume.characterId == null
                        ? l10nOf(context).costumeDetailAssign
                        : l10nOf(context).costumeDetailReassign,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _pickCharacter(
    BuildContext context,
    WidgetRef ref,
    List<CharacterView> characters,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => AssignCharacterSheet(
        characters: [
          for (final c in characters)
            (
              id: c.id,
              name: c.name,
              category: serializers
                  .serializeWith(CharacterCategory.serializer, c.category)
                  .toString(),
            ),
        ],
        assignedId: costume.characterId,
      ),
    );
    if (picked == null || !context.mounted) return;
    // The assignment section re-keys to `overlay-assign-<costume>-<picked>`
    // while the version fence holds (Gherkin + widget contract) — no
    // transient SnackBar needed. Handled: failures surface via the
    // command-error provider.
    final assignResult = await ref
        .read(costumesControllerProvider(season.id).notifier)
        .assign(costume: costume, characterId: picked);
    assignResult.match<void>((_) {}, (_) {});
  }

  Future<void> _confirmUnassign(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.costumeDetailUnassignTitle),
        content: Text(l10n.costumeDetailUnassignMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('costume-unassign-confirm-${costume.id}'),
            onPressed: () async {
              // Handled: failures surface via the command-error provider.
              final unassignResult = await ref
                  .read(costumesControllerProvider(season.id).notifier)
                  .unassign(costume: costume);
              unassignResult.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.costumeDetailUnassignTooltip),
          ),
        ],
      ),
    );
  }
}

class _NotesSection extends ConsumerStatefulWidget {
  const _NotesSection({required this.season, required this.costume});

  final SeasonView season;
  final CostumeView costume;

  @override
  ConsumerState<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends ConsumerState<_NotesSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.costume.notes);
  }

  @override
  void didUpdateWidget(covariant _NotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.costume.notes != widget.costume.notes &&
        _controller.text != widget.costume.notes) {
      _controller.text = widget.costume.notes;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l10nOf(context).costumeDetailNotes,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      TextField(
        key: Key('costume-notes-${widget.costume.id}'),
        controller: _controller,
        maxLines: 3,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: l10nOf(context).costumeDetailNotesHint,
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          key: Key('costume-notes-save-${widget.costume.id}'),
          onPressed: () async {
            // Handled: failures surface via the command-error provider.
            final notesResult = await ref
                .read(costumesControllerProvider(widget.season.id).notifier)
                .updateNotes(costume: widget.costume, notes: _controller.text);
            final saved = notesResult.match((_) => false, (_) => true);
            if (saved && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  key: const Key('costume-saved-confirmation'),
                  content: Text(l10nOf(context).costumeDetailSaved),
                ),
              );
            }
          },
          child: Text(l10nOf(context).costumeDetailSaveNotes),
        ),
      ),
    ],
  );
}

/// Category section (issue #543): the costume's single category in the
/// identity section — always visible with its icon next to the text (the
/// `categories.icon` glossary rule: icons are redundant reinforcement,
/// never the sole carrier of meaning).
///
/// The picker section Inlinelists the season's projected, NON-ARCHIVED
/// vocabulary (read-DTO join via `costumeCategoriesViewProvider`, no extra
/// network dependency) plus the deliberate "no category" row, which
/// dispatches `setCategory(categoryId: null)` (clearing must be
/// possible). The set/clear command runs in the controller with the
/// AUTHZ-GATE capability check BEFORE any network call; denial renders
/// the localized 403 narrative via the command-error banner.
///
/// // AUTHZ-GATE: `assign_costumes` capability checked in the controller
/// before any network call; denial renders the 403 narrative and never
/// issues the request.
class CostumeCategorySection extends ConsumerWidget {
  const CostumeCategorySection({
    super.key,
    required this.season,
    required this.costume,
  });

  final SeasonView season;
  final CostumeView costume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    // Fence-held overlays render the optimistic key (Gherkin contract);
    // reconciled rows render the authoritative key.
    final controllerState = ref.watch(costumesControllerProvider(season.id));
    final fenceHeld = controllerState.overlays.any((o) => o.id == costume.id);
    final effective = fenceHeld
        ? controllerState.overlays.firstWhere((o) => o.id == costume.id).overlay
        : costume;
    // "Ohne Kategorie" is reserved for a null category ID (CodeRabbit
    // #4126529938): the projected name is best-effort — a set category
    // whose name is not (yet) resolved is NOT uncategorised. The label is
    // keyed on the ID, never on the denormalised name.
    final currentName = switch (effective.categoryId) {
      null => l10n.costumeCategoryUncategorized,
      _ => effective.categoryName ?? effective.categoryId!,
    };
    return Column(
      key: const Key('costume-category-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.costumeDetailCategoryTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ListTile(
          // Gherkin contract keys: optimistic vs projected category (same
          // pattern as the assignment tile above).
          key: Key(
            fenceHeld
                ? 'overlay-category-${costume.id}-${effective.categoryId ?? "none"}'
                : 'costume-category-${costume.id}-${effective.categoryId ?? "none"}',
          ),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            BreakdownMaterialIcons.forCostumeCategory(effective.categoryName),
            key: Key('costume-category-icon-${costume.id}'),
            size: 20,
          ),
          title: Text(
            currentName,
            key: Key('costume-category-current-${costume.id}'),
          ),
        ),
        const SizedBox(height: 0),
        FilledButton.tonal(
          key: Key('costume-category-pick-${costume.id}'),
          onPressed: () => _showPicker(context, ref),
          child: Text(l10n.costumeDetailPickCategory),
        ),
      ],
    );
  }

  Future<void> _showPicker(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final l10n = l10nOf(context);
          final view = sheetRef.watch(costumeCategoriesViewProvider(season.id));
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    l10n.costumeDetailPickCategory,
                    key: const Key('costume-category-picker-title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView(
                    key: const Key('costume-category-picker-list'),
                    shrinkWrap: true,
                    children: [
                      // The deliberate "no category" row (None clears the
                      // costume's category — visible text, never hidden).
                      ListTile(
                        key: const Key('costume-category-option-none'),
                        leading: Icon(
                          BreakdownMaterialIcons.forCostumeCategory(null),
                        ),
                        title: Text(l10n.costumeCategoryUncategorized),
                        selected: costume.categoryId == null,
                        onTap: () => _pick(context, ref, null, null),
                      ),
                      for (final option in costumeCategoryOptions(view.rows))
                        ListTile(
                          key: Key(
                            'costume-category-option-${option.category.id}',
                          ),
                          leading: Icon(
                            BreakdownMaterialIcons.forCostumeCategory(
                              option.category.name,
                            ),
                          ),
                          title: Text(option.category.name),
                          selected: costume.categoryId == option.category.id,
                          onTap: () => _pick(
                            context,
                            ref,
                            option.category.id,
                            option.category.name,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    String? categoryId,
    String? categoryName,
  ) async {
    // CodeRabbit #4126529948: the bottom sheet is a route — after it is
    // popped its context must not be used across the asynchronous command
    // gap. The picker builder context IS the screen context here (the
    // sheet builder receives the section's own context), so resolve the
    // messenger + localized copy BEFORE popping; the command runs on the
    // same section instance whose later builds never depend on this
    // per-dispatch closure context.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final savedCopy = l10nOf(context).costumeDetailCategorySaved;
    Navigator.of(context).pop();
    final result = await ref
        .read(costumesControllerProvider(season.id).notifier)
        .setCategory(
          costume: costume,
          categoryId: categoryId,
          categoryName: categoryName,
        );
    final saved = result.match((_) => false, (_) => true);
    if (saved && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('costume-category-saved-confirmation'),
          content: Text(savedCopy),
        ),
      );
    }
  }
}

/// Visible, non-archived picker options in server order. Deliberately
/// public and pure for the unit tier: archived vocabulary must never be a
/// new categorisation option (the backend list query serves the same
/// predicate).
List<CostumeCategoryOption> costumeCategoryOptions(
  List<CostumeCategoryView> rows,
) => [
  for (final c in rows)
    if (!c.archived) CostumeCategoryOption(category: c),
];

class CostumeCategoryOption {
  const CostumeCategoryOption({required this.category});

  final CostumeCategoryView category;
}

class _DetailsSection extends ConsumerStatefulWidget {
  const _DetailsSection({required this.season, required this.costume});

  final SeasonView season;
  final CostumeView costume;

  @override
  ConsumerState<_DetailsSection> createState() => _DetailsSectionState();
}

/// Issue #545: the inline detail editor — the row list itself owns which
/// detail is being edited (`_editingDetailId`) and whether the create draft
/// is open (`_draftOpen`). No modal: the editor expands where the detail
/// sits, so the keyboard cannot clip it and the scroll context survives.
class _DetailsSectionState extends ConsumerState<_DetailsSection> {
  String? _editingDetailId;
  bool _draftOpen = false;

  void _openEdit(String detailId) {
    setState(() {
      _editingDetailId = detailId;
      _draftOpen = false;
    });
  }

  void _openDraft() {
    setState(() {
      _editingDetailId = null;
      _draftOpen = true;
    });
  }

  void _close() {
    setState(() {
      _editingDetailId = null;
      _draftOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    final details = widget.costume.details;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.costumeDetailDetails,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (details.isEmpty && _editingDetailId == null && !_draftOpen)
          Text(
            l10n.costumeDetailNoDetails,
            key: const Key('costume-details-empty'),
          ),
        for (final d in details)
          _DetailRow(
            key: Key('detail-row-${d.id}'),
            season: widget.season,
            costume: widget.costume,
            detail: d,
            editing: _editingDetailId == d.id,
            onEdit: () => _openEdit(d.id),
            onClose: _close,
          ),
        if (!_draftOpen)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('costume-detail-add-${widget.costume.id}'),
              icon: const Icon(Icons.add),
              label: Text(l10n.costumeDetailAddDetail),
              onPressed: _openDraft,
            ),
          ),
        if (_draftOpen)
          _DetailEditor(
            key: const Key('detail-draft'),
            season: widget.season,
            costume: widget.costume,
            initial: null,
            onClose: _close,
          ),
      ],
    );
  }
}

/// One detail row: title/subtitle composition + trailing edit/delete
/// affordances, with the inline editor expanding below the row while it is
/// the open one (issue #545).
///
/// // AUTHZ-GATE: the edit/delete affordances dispatch through the
/// controller's `assign_costumes` capability check BEFORE any network call;
/// denial renders the localized 403 narrative and never issues the request.
class _DetailRow extends ConsumerWidget {
  const _DetailRow({
    super.key,
    required this.season,
    required this.costume,
    required this.detail,
    required this.editing,
    required this.onEdit,
    required this.onClose,
  });

  final SeasonView season;
  final CostumeView costume;
  final CostumeDetailView detail;
  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = detail.subject != null && detail.subject!.isNotEmpty
        ? detail.subject
        : null;
    return Card(
      key: Key('costume-detail-${detail.id}'),
      child: Column(
        children: [
          ListTile(
            key: Key('detail-row-${detail.id}'),
            // Issue #543: details are pure description (subject + text);
            // the category lives on the costume itself.
            title: Text(subject ?? detail.text),
            subtitle: subject == null ? null : Text(detail.text),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('costume-detail-edit-${detail.id}'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: l10nOf(context).commonEdit,
                  // Scroll the row into view first so the editor that
                  // expands below it is actually on screen (issue #545 —
                  // analog of `_CostumesScreenState._selectCostume`).
                  onPressed: () {
                    // Fire-and-forget scroll affordance — the editor's
                    // mount does not depend on the animation completing.
                    unawaited(Scrollable.ensureVisible(context));
                    onEdit();
                  },
                ),
                IconButton(
                  key: Key('costume-detail-delete-${detail.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10nOf(context).commonDelete,
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ),
          ),
          if (editing)
            _DetailEditor(
              key: Key('detail-editor-${detail.id}'),
              season: season,
              costume: costume,
              initial: detail,
              onClose: onClose,
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) {
    final l10n = l10nOf(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('costume-detail-delete-dialog'),
        title: Text(l10n.costumeDetailDeleteTitle),
        content: Text(
          l10n.costumeDetailDeleteMessage(
            detail.subject != null && detail.subject!.isNotEmpty
                ? detail.subject!
                : detail.text,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: Key('costume-detail-delete-confirm-${detail.id}'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // Handled: failures surface via the command-error provider.
              final deleteResult = await ref
                  .read(costumesControllerProvider(season.id).notifier)
                  .removeDetail(costume: costume, detailId: detail.id);
              deleteResult.match<void>((_) {}, (_) {});
            },
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

/// The inline detail editor (issue #545) — `initial == null` means create
/// mode; a non-null [initial] prefills the edit mode. ONE widget drives
/// both paths: the create row and every row's edit affordance open the same
/// form in place, so a detail author never loses scroll or focus context
/// and the keyboard cannot collide with a modal.
///
/// The controllers live in widget state and dispose when the editor
/// unmounts — since there is no dialog route around it, the old comment
/// workaround's reasoning still applies, just rendered inside the row.
class _DetailEditor extends ConsumerStatefulWidget {
  const _DetailEditor({
    super.key,
    required this.season,
    required this.costume,
    required this.initial,
    required this.onClose,
  });

  final SeasonView season;
  final CostumeView costume;

  /// The detail being edited, or `null` in create mode.
  final CostumeDetailView? initial;
  final VoidCallback onClose;

  @override
  ConsumerState<_DetailEditor> createState() => _DetailEditorState();
}

class _DetailEditorState extends ConsumerState<_DetailEditor> {
  late final TextEditingController _subject;
  late final TextEditingController _text;
  late final GlobalKey<FormState> _formKey;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _subject = TextEditingController(text: initial?.subject ?? '');
    _text = TextEditingController(text: initial?.text ?? '');
    _formKey = GlobalKey<FormState>();
  }

  @override
  void dispose() {
    _subject.dispose();
    _text.dispose();
    super.dispose();
  }

  bool get _textValid => _text.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = l10nOf(context);
    // Issue #543: no category field here — the category is set on the
    // costume (identity section), not per detail.
    return Padding(
      key: widget.initial == null ? const Key('add-detail-editor') : null,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('add-detail-subject'),
              controller: _subject,
              decoration: InputDecoration(
                labelText: l10n.costumeDetailSubject,
                helperText: l10n.costumeDetailSubjectOptional,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('add-detail-text'),
              controller: _text,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                // `text` is the ONLY required field; the asterisk marks it,
                // and the helper text makes the optionality contrast with
                // the subject field explicit.
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.costumeDetailText),
                    const SizedBox(width: 2),
                    const Text('*'),
                  ],
                ),
                helperText: l10n.costumeDetailTextRequiredHint,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.costumeDetailTextRequired
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('add-detail-cancel'),
                  onPressed: widget.onClose,
                  child: Text(l10nOf(context).commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('add-detail-submit'),
                  // The affordance itself validates: no submit-only error.
                  onPressed: !_textValid
                      ? null
                      : () async {
                          if (!(_formKey.currentState?.validate() ?? false)) {
                            return;
                          }
                          await _submit(context);
                        },
                  child: Text(l10nOf(context).commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final savedCopy = l10nOf(context).costumeDetailSaved;
    final text = _text.text.trim();
    final subject = _subject.text.trim().isEmpty ? null : _subject.text.trim();
    final notifier = ref.read(
      costumesControllerProvider(widget.season.id).notifier,
    );
    // Handled: failures surface via the command-error provider.
    final detailResult = widget.initial == null
        ? await notifier.addDetail(
            costume: widget.costume,
            text: text,
            subject: subject,
          )
        : await notifier.updateDetail(
            costume: widget.costume,
            detailId: widget.initial!.id,
            text: text,
            subject: subject,
          );
    final saved = detailResult.match((_) => false, (_) => true);
    if (saved && mounted) widget.onClose();
    if (saved && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('costume-saved-confirmation'),
          content: Text(savedCopy),
        ),
      );
    }
  }
}

/// Photos section: gallery (from `CostumeView.photos`), capture affordance
/// (gated), progress for prepare+upload, delete with confirmation.
///
/// // AUTHZ-GATE: capture/upload/delete run the membership capability check
/// inside the controller before any network call; denial renders the
/// localized 403 narrative and never issues the request.
class _PhotosSection extends ConsumerStatefulWidget {
  const _PhotosSection({required this.season, required this.costume});

  final SeasonView season;
  final CostumeView costume;

  @override
  ConsumerState<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<_PhotosSection> {
  bool _busy = false;

  /// The single-costume DETAIL, fetched on open.
  ///
  /// The gallery renders `CostumeView.photos` from this row. The costume
  /// handed in via the widget tree is the costume LIST row, which the server
  /// enriches in batch — `list_by_season` runs `enrich_many` (3 queries per
  /// page, details + photos + variants included since the #543/#544
  /// tranche), so list rows DO carry child collections. The fetch is kept
  /// anyway because the rendered row can be an OPTIMISTIC OVERLAY, not the
  /// projected row: an upload/delete just acknowledged by a command does not
  /// exist in the last fetched list snapshot, so the enriched single-costume
  /// read refreshes this row on gallery-affecting commands (`_loadDetail`
  /// after upload/delete). Falls back to the list view while loading and on
  /// failure (a photo-less costume then simply shows the empty-gallery
  /// affordance as before).
  CostumeView? _detail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;
    final res = await ref
        .read(costumesControllerProvider(widget.season.id).notifier)
        .loadDetail(widget.costume.id);
    if (!mounted) return;
    // Only a successful detail may replace the rendered view: an Err leaves
    // the list view in place (and its command-error surface owns the message).
    res.match<void>((_) {}, (view) {
      if (!mounted) return;
      setState(() => _detail = view);
    });
  }

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider(widget.season.id));
    final canUpload = switch (membership) {
      AsyncData(:final value) => value.canUploadContinuityPhotos,
      _ => false,
    };
    final denied = switch (membership) {
      AsyncData(:final value) => !value.canUploadContinuityPhotos,
      _ => false,
    };
    // Photo affordances are gated on the membership capability only. The
    // costume's season *scope* is the server's call (issue #532): an
    // unassigned costume that stands in the season's repertoire (which is how
    // the client creates every costume, issue #453) CAN manage photos, so no
    // client-side character-assignment gate remains here. A costume with no
    // scope at all is rejected by the server with `domain.validation`, which
    // surfaces through the photo command-error copy.
    final canManagePhotos = canUpload;
    // Do not construct the network-backed photo repository while the
    // capability is denied or still pending. This keeps the overview's
    // inline editor renderable during membership resolution and enforces the
    // client-side photo gate before any bytes request.
    final repo = canUpload ? ref.watch(costumePhotoRepositoryProvider) : null;
    final lru = ref.watch(photoBytesLruProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10nOf(context).costumeDetailPhotos,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            if (_busy)
              const SizedBox(
                key: Key('photo-prepare-progress'),
                width: 20,
                height: 20,
                child: LinearProgressIndicator(),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (denied)
          Text(
            l10nOf(context).photoErrorForbidden,
            key: const Key('photo-denied-narrative'),
          ),
        if (repo != null)
          PhotoGallery(
            costume: _detail ?? widget.costume,
            repository: repo,
            lru: lru,
            canCapture: canManagePhotos,
            onCapture: canManagePhotos
                ? () => _capture(ImageSource.camera)
                : null,
            onDelete: canManagePhotos
                ? (photo) => _confirmDelete(photo.id)
                : null,
            onRetryCapture: canManagePhotos
                ? () => _capture(ImageSource.camera)
                : null,
          )
        else if (widget.costume.photos.isEmpty)
          Text(
            l10nOf(context).photoGalleryEmpty,
            key: Key('photo-gallery-empty-${widget.costume.id}'),
          ),
        if (canManagePhotos) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                key: Key('photo-capture-camera-${widget.costume.id}'),
                onPressed: _busy ? null : () => _capture(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: Text(l10nOf(context).costumeDetailCamera),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: Key('photo-capture-gallery-${widget.costume.id}'),
                onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text(l10nOf(context).costumeDetailGallery),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _capture(ImageSource source) async {
    final picker = ref.read(imagePickerProvider);
    final seen = ref.read(photoRationaleSeenProvider);
    setState(() => _busy = true);
    try {
      final outcome = await runCaptureIntent(
        source: source,
        picker: picker,
        rationaleSeen: seen,
        markRationaleSeen: () =>
            ref.read(photoRationaleSeenProvider.notifier).markSeen(),
        showRationale: () => _showRationale(),
      );
      if (!mounted) return;
      switch (outcome) {
        case CapturePicked(:final file):
          await _prepareAndUpload(file);
        case CaptureDenied(:final source):
          await _showDenied(source);
        case CaptureUnavailable():
          _showUnavailable();
        case CaptureCancelled():
          break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// In-app rationale BEFORE the first system permission prompt.
  Future<bool> _showRationale() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10nOf(dialogContext).costumeDetailPromptTitle),
        content: Text(l10nOf(dialogContext).costumeDetailPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10nOf(dialogContext).costumeDetailNotNow),
          ),
          FilledButton(
            key: const Key('photo-rationale-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10nOf(dialogContext).costumeDetailContinue),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  Future<void> _showDenied(ImageSource source) {
    final denied = CaptureDenied(source);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(captureDeniedTitle(l10nOf(dialogContext), denied)),
        content: Text(captureOutcomeCopy(l10nOf(dialogContext), denied)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10nOf(dialogContext).settingsClose),
          ),
          FilledButton(
            key: const Key('photo-open-settings'),
            onPressed: () async {
              await ref.read(openAppSettingsProvider)();
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text(l10nOf(dialogContext).costumeDetailOpenSettings),
          ),
        ],
      ),
    );
  }

  void _showUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          captureOutcomeCopy(l10nOf(context), const CaptureUnavailable()),
        ),
      ),
    );
  }

  Future<void> _prepareAndUpload(XFile file) async {
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      // The picked file can vanish or be unreadable after the picker
      // returns; surface it like any other prepare failure instead of
      // escaping the press handler silently.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoErrorCopy(
              l10nOf(context),
              const ProblemError(code: 'photo.read_failed'),
            ),
          ),
        ),
      );
      return;
    }
    final contentType =
        contentTypeForExtension(file.name.split('.').lastOrNull ?? '') ??
        'image/jpeg';
    // Background-isolate prepare (the UI thread stays free; the seam
    // is synchronous in widget tests where isolates never complete).
    final prepared = await ref.read(preparePhotoProvider)(
      PrepareInput(bytes: bytes, contentType: contentType),
    );
    if (!mounted) return;
    switch (prepared) {
      case PrepareReady(:final bytes, :final contentType):
        // Handled: failures surface via the command-error provider.
        final uploadResult = await ref
            .read(costumesControllerProvider(widget.season.id).notifier)
            .uploadPhoto(
              costumeId: widget.costume.id,
              bytes: Uint8ListBytes(bytes),
              contentType: contentType,
            );
        uploadResult.match<void>((_) {}, (_) {});
        // A successful upload must re-read the enriched row: the gallery renders
        // `_detail`, which still holds the pre-command snapshot (the overlay
        // row is optimistic and the list refetch is bounded, not immediate).
        // Only on success — a failed command must not rewrite what is shown.
        if (uploadResult.isRight()) await _loadDetail();
      case PrepareFailure(:final code):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              photoErrorCopy(l10nOf(context), ProblemError(code: code)),
            ),
          ),
        );
    }
  }

  Future<void> _confirmDelete(String photoId) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10nOf(dialogContext).photoDeleteTitle),
        content: Text(l10nOf(dialogContext).costumeDetailDeletePhotoMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10nOf(dialogContext).commonCancel),
          ),
          FilledButton(
            key: Key('photo-delete-confirm-$photoId'),
            onPressed: () async {
              // Handled: failures surface via the command-error provider.
              final deleteResult = await ref
                  .read(costumesControllerProvider(widget.season.id).notifier)
                  .deletePhoto(costumeId: widget.costume.id, photoId: photoId);
              deleteResult.match<void>((_) {}, (_) {});
              // Close the dialog BEFORE the reload: _loadDetail awaits a network
              // read, and while the dialog stays open the (still enabled) delete
              // button could dispatch the same delete again — a failed second
              // request would surface a command error although the first delete
              // already succeeded. `_loadDetail` guards on the State's own
              // `mounted`, so popping first is safe.
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              // Same reason as the upload path: without this the DELETED photo
              // stays visible in the gallery until the section is rebuilt,
              // because `_detail` still holds the pre-delete row. The comment
              // on `_detail` explains why a list snapshot cannot help here.
              if (deleteResult.isRight()) await _loadDetail();
            },
            child: Text(l10nOf(dialogContext).commonDelete),
          ),
        ],
      ),
    );
  }
}
