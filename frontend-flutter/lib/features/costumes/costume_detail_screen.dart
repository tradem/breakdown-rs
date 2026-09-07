// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

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

/// `CostumeDetailScreen` — detail elements (denormalized `category_name`),
/// add-detail form (category picker from the season categories projection),
/// notes editor, assign/unassign (character picker, version echo), and the
/// photo gallery (capture → prepare → raw-bytes upload → variant watch).
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
    // Keep the variant watch alive while visible; terminal events refresh
    // through the cache write in `getAndCache` (the projection rebuilds).
    ref.listen(costumePhotoWatchProvider(season.id, costumeId), (_, _) {});
    final state = ref.watch(costumesControllerProvider(season.id));
    final controller = ref.read(costumesControllerProvider(season.id).notifier);
    final costume = _resolveCostume(state);

    return Scaffold(
      appBar: AppBar(title: const Text('Costume')),
      body: costume == null
          ? const Center(
              child: CircularProgressIndicator(key: Key('costume-loading')),
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                key: Key('costume-detail-$costumeId'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (state.commandError case final error?)
                    _InlineError(
                      text: costumeErrorCopy(error),
                      onDismiss: controller.dismissCommandError,
                    ),
                  _AssignmentSection(season: season, costume: costume),
                  const Divider(height: 32),
                  _NotesSection(season: season, costume: costume),
                  const Divider(height: 32),
                  _DetailsSection(season: season, costume: costume),
                  const Divider(height: 32),
                  _PhotosSection(season: season, costume: costume),
                ],
              ),
            ),
    );
  }

  /// Resolves the effective row: the fence-held overlay first (its notes,
  /// details and assignment are newer than the cached projection), then
  /// the cached row. The overlay version already advanced to the ack, so
  /// follow-up commands echo it instead of the pre-command version.
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
                tooltip: 'Dismiss',
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
        Text('Character', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (denied)
          const Text(
            'You need an active costume role in this season to assign '
            'characters.',
            key: Key('costume-assign-denied'),
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
            title: Text(assignedName ?? 'Unassigned'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (costume.characterId != null)
                  IconButton(
                    key: Key('costume-unassign-${costume.id}'),
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Unassign',
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
                    costume.characterId == null ? 'Assign' : 'Reassign',
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
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unassign character?'),
        content: const Text(
          'The costume keeps its details and notes; only the character '
          'binding is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
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
            child: const Text('Unassign'),
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
      Text('Notes', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        key: Key('costume-notes-${widget.costume.id}'),
        controller: _controller,
        maxLines: 3,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Fitting notes…',
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
            notesResult.match<void>((_) {}, (_) {});
          },
          child: const Text('Save notes'),
        ),
      ),
    ],
  );
}

class _DetailsSection extends ConsumerWidget {
  const _DetailsSection({required this.season, required this.costume});

  final SeasonView season;
  final CostumeView costume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Subscribe early so the category picker reads warm rows (providers
    // are lazy — a one-shot read in the dialog alone would still load).
    final categories = ref.watch(costumeCategoriesViewProvider(season.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (costume.details.isEmpty)
          const Text(
            'No details yet — add the first one below.',
            key: Key('costume-details-empty'),
          )
        else
          for (final d in costume.details)
            Card(
              key: Key('costume-detail-${d.id}'),
              child: ListTile(
                title: Text(d.subject ?? d.text),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.subject != null && d.subject!.isNotEmpty)
                      Text(d.text),
                    if (d.categoryName != null)
                      Text(
                        d.categoryName!,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: Key('costume-detail-add-${costume.id}'),
          onPressed: () => _showAddDetail(context, ref, categories.rows),
          child: const Text('Add detail'),
        ),
      ],
    );
  }

  Future<void> _showAddDetail(
    BuildContext context,
    WidgetRef ref,
    List<CostumeCategoryView> categories,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => _AddDetailForm(
        season: season,
        costume: costume,
        categories: categories,
      ),
    );
  }
}

/// Add-detail dialog content: owns its `TextEditingController`s in widget
/// state so they dispose exactly when the dialog route unmounts (after the
/// exit transition) — never while the exit animation still rebuilds, which a
/// `whenComplete` on the dialog future cannot guarantee.
class _AddDetailForm extends ConsumerStatefulWidget {
  const _AddDetailForm({
    required this.season,
    required this.costume,
    required this.categories,
  });

  final SeasonView season;
  final CostumeView costume;
  final List<CostumeCategoryView> categories;

  @override
  ConsumerState<_AddDetailForm> createState() => _AddDetailFormState();
}

class _AddDetailFormState extends ConsumerState<_AddDetailForm> {
  late final TextEditingController _subject;
  late final TextEditingController _text;
  late final GlobalKey<FormState> _formKey;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _subject = TextEditingController();
    _text = TextEditingController();
    _formKey = GlobalKey<FormState>();
  }

  @override
  void dispose() {
    _subject.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add detail'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            key: const Key('add-detail-subject'),
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          TextFormField(
            key: const Key('add-detail-text'),
            controller: _text,
            decoration: const InputDecoration(labelText: 'Text'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Text is required' : null,
          ),
          DropdownButtonFormField<String>(
            key: const Key('add-detail-category'),
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in widget.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('add-detail-submit'),
        onPressed: () async {
          if (!(_formKey.currentState?.validate() ?? false)) return;
          // Handled: failures surface via the command-error provider.
          final detailResult = await ref
              .read(costumesControllerProvider(widget.season.id).notifier)
              .addDetail(
                costume: widget.costume,
                text: _text.text.trim(),
                subject: _subject.text.trim().isEmpty
                    ? null
                    : _subject.text.trim(),
                categoryId: _categoryId,
              );
          detailResult.match<void>((_) {}, (_) {});
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: const Text('Add'),
      ),
    ],
  );
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

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider(widget.season.id));
    final canUpload = switch (membership) {
      AsyncData(:final value) => value.canUploadContinuityPhotos,
      _ => false,
    };
    final canCapture = canUpload;
    final denied = switch (membership) {
      AsyncData(:final value) => !value.canUploadContinuityPhotos,
      _ => false,
    };
    final repo = ref.watch(costumePhotoRepositoryProvider);
    final lru = ref.watch(photoBytesLruProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Photos', style: Theme.of(context).textTheme.titleMedium),
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
          const Text(
            'You need an active costume role in this season to manage '
            'photos.',
            key: Key('photo-denied-narrative'),
          ),
        PhotoGallery(
          costume: widget.costume,
          repository: repo,
          lru: lru,
          canCapture: canCapture,
          onCapture: canCapture ? () => _capture(ImageSource.camera) : null,
          onDelete: (photo) => _confirmDelete(photo.id),
          onRetryCapture: canCapture
              ? () => _capture(ImageSource.camera)
              : null,
        ),
        if (canCapture) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                key: Key('photo-capture-camera-${widget.costume.id}'),
                onPressed: _busy ? null : () => _capture(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Camera'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: Key('photo-capture-gallery-${widget.costume.id}'),
                onPressed: _busy ? null : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
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
        title: const Text('Document costumes with photos?'),
        content: const Text(
          'Photos let the wardrobe team document costumes and track '
          'continuity. The system will ask for camera access next.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const Key('photo-rationale-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
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
        title: Text(captureDeniedTitle(denied)),
        content: Text(captureOutcomeCopy(denied)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('photo-open-settings'),
            onPressed: () async {
              await ref.read(openAppSettingsProvider)();
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  void _showUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(captureOutcomeCopy(const CaptureUnavailable()))),
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
            photoErrorCopy(const ProblemError(code: 'photo.read_failed')),
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
      case PrepareFailure(:final code):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(photoErrorCopy(ProblemError(code: code)))),
        );
    }
  }

  Future<void> _confirmDelete(String photoId) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text(
          'The photo and its variants are removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('photo-delete-confirm-$photoId'),
            onPressed: () async {
              // Handled: failures surface via the command-error provider.
              final deleteResult = await ref
                  .read(costumesControllerProvider(widget.season.id).notifier)
                  .deletePhoto(costumeId: widget.costume.id, photoId: photoId);
              deleteResult.match<void>((_) {}, (_) {});
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
