// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3 (opencode)
// Co-authored-by: deepseek-v4-flash (neuralwatt)
// Co-authored-by: space-bunny-free (opencode)

import 'dart:typed_data';

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../auth/membership/capability.dart';
import '../../../auth/membership/membership_providers.dart';
import '../../../core/problem_error.dart';
import '../../../l10n/app_localizations_provider.dart';
import '../../costumes/costumes_controller.dart';
import '../../photos/capture.dart';
import '../../photos/prepare.dart';
import '../../photos/widgets/photo_gallery.dart';
import '../scene_shoots_controller.dart';
import '../scene_shoots_state.dart';

/// Continuity strip on the shoot card: the shoot's linked continuity
/// (Anschluss) photos with capture + unlink, reusing the Phase 2 capture
/// pipeline (point-of-use rationale → isolate prepare → raw-bytes upload).
///
/// Photo bytes are costume-scoped (`POST /v1/costumes/{id}/photos`), so a
/// capture picks the owning costume from the season's costume read DTOs
/// and the acknowledged photo is then linked to the scene-shoot context
/// (`link_continuity_photo`). Thumbnails resolve through the same
/// read-DTO join: each linked id is looked up in the season costumes'
/// embedded photos and renders through the shared [PhotoTile] (LRU +
/// variant watch). Linked ids with no owning costume in the projection
/// (prop-only shots, deleted costume photos) render a neutral row with
/// the unlink affordance — never a throw, never a guessed byte fetch.
///
/// // AUTHZ-GATE: capture/upload/unlink run the `upload_continuity_photos`
/// capability check (display via [currentMembershipProvider], enforcement
/// in the controller before any network call); denial renders the
/// localized 403 narrative and never issues the request.
class ContinuityStrip extends ConsumerStatefulWidget {
  const ContinuityStrip({
    super.key,
    required this.shoot,
    required this.scope,
    required this.enabled,
  });

  final SceneShootView shoot;
  final SceneShootDayScope scope;
  final bool enabled;

  @override
  ConsumerState<ContinuityStrip> createState() => _ContinuityStripState();
}

class _ContinuityStripState extends ConsumerState<ContinuityStrip> {
  bool _busy = false;
  String? _costumeId;

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(
      currentMembershipProvider(widget.scope.seasonId),
    );
    final canManage = switch (membership) {
      AsyncData(:final value) => value.canUploadContinuityPhotos,
      _ => false,
    };
    final denied = switch (membership) {
      AsyncData(:final value) => !value.canUploadContinuityPhotos,
      _ => false,
    };
    final costumes = ref.watch(costumesViewProvider(widget.scope.seasonId));
    final repo = ref.watch(costumePhotoRepositoryProvider);
    final lru = ref.watch(photoBytesLruProvider);
    final resolved = _resolve(costumes.rows, widget.shoot.continuityPhotoIds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10nOf(context)
                  .continuityTitle('${widget.shoot.continuityPhotoIds.length}'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            if (_busy)
              SizedBox(
                key: Key('continuity-prepare-progress-${widget.shoot.id}'),
                width: 20,
                height: 20,
                child: const LinearProgressIndicator(),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (denied && widget.enabled)
          Text(
            l10nOf(context).continuityRoleGate,
            key: const Key('continuity-denied-narrative'),
          ),
        if (resolved.isEmpty && !widget.enabled)
          Text(l10nOf(context).continuityEmpty),
        Wrap(
          key: Key('continuity-strip-${widget.shoot.id}'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in resolved)
              switch (entry) {
                _LinkedPhoto(:final costumeId, :final photo) => SizedBox(
                  width: 96,
                  child: PhotoTile(
                    costumeId: costumeId,
                    photo: photo,
                    repository: repo,
                    lru: lru,
                    onDelete: widget.enabled
                        ? () => _confirmUnlink(photo.id)
                        : null,
                    onRetryCapture:
                        widget.enabled &&
                            canManage &&
                            !_busy &&
                            _costumeId != null
                        ? () => _capture(ImageSource.camera)
                        : null,
                  ),
                ),
                _OrphanPhoto(:final id) => Chip(
                  key: Key('continuity-orphan-$id'),
                  label: Text(
                    l10nOf(context).continuityPhotoLabel(
                      id.length > 8 ? id.substring(0, 8) : id,
                    ),
                  ),
                  deleteIcon: widget.enabled
                      ? Icon(
                          Icons.link_off,
                          key: Key('continuity-orphan-unlink-$id'),
                        )
                      : null,
                  onDeleted: widget.enabled ? () => _confirmUnlink(id) : null,
                ),
              },
          ],
        ),
        if (widget.enabled && canManage) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: Key('continuity-costume-pick-${widget.shoot.id}'),
            initialValue: _costumeId,
            hint: Text(l10nOf(context).continuityStoreOn),
            items: [
              for (final c in costumes.rows)
                DropdownMenuItem(
                  // Gherkin contract key for the continuity capture
                  // critical scenario (costume pick on device).
                  key: Key('continuity-costume-option-${c.id}'),
                  value: c.id,
                  child: Text(_costumeLabel(c)),
                ),
            ],
            onChanged: (v) => setState(() => _costumeId = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonalIcon(
                key: Key('continuity-capture-camera-${widget.shoot.id}'),
                onPressed: _busy || _costumeId == null
                    ? null
                    : () => _capture(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: Text(l10nOf(context).costumeDetailCamera),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: Key('continuity-capture-gallery-${widget.shoot.id}'),
                onPressed: _busy || _costumeId == null
                    ? null
                    : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: Text(l10nOf(context).costumeDetailGallery),
              ),
            ],
          ),
          if (_costumeId == null)
            Text(
              l10nOf(context).continuityCostumeHint,
              key: Key('continuity-costume-hint-${widget.shoot.id}'),
            ),
        ],
      ],
    );
  }

  Future<void> _capture(ImageSource source) async {
    final costumeId = _costumeId;
    // Belt and braces: the buttons disable without a costume, and the
    // controller gates the upload + link — this guard only short-circuits
    // the picker intent itself.
    if (costumeId == null) return;
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
          await _prepareUploadAndLink(costumeId, file);
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
        title: Text(l10nOf(dialogContext).continuityRationaleTitle),
        content: Text(l10nOf(dialogContext).continuityRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10nOf(dialogContext).costumeDetailNotNow),
          ),
          FilledButton(
            key: const Key('continuity-rationale-accept'),
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
            key: const Key('continuity-open-settings'),
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

  Future<void> _prepareUploadAndLink(String costumeId, XFile file) async {
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
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
        // Both steps are AUTHZ-GATE'd in the controller: a denial issues
        // zero network calls and surfaces the 403 narrative. Failures
        // surface via the command-error provider.
        final upload = await ref
            .read(sceneShootsControllerProvider(widget.scope).notifier)
            .uploadContinuityBytes(
              costumeId: costumeId,
              bytes: bytes,
              contentType: contentType,
            );
        if (!mounted) return;
        await upload.match((_) async {}, (view) async {
          final link = await ref
              .read(sceneShootsControllerProvider(widget.scope).notifier)
              .linkContinuityPhoto(shoot: widget.shoot, photoId: view.id);
          link.match<void>((_) {}, (_) {});
        });
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

  Future<void> _confirmUnlink(String photoId) {
    // Double-tap guard: the confirm button disables itself on first tap
    // so a second command with the same shoot version cannot dispatch
    // (the server would reject it as a conflict for a successful action).
    var tapped = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10nOf(dialogContext).continuityUnlinkTitle),
          content: Text(l10nOf(dialogContext).continuityUnlinkBody),
          actions: [
            TextButton(
              onPressed: tapped
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(l10nOf(dialogContext).commonCancel),
            ),
            FilledButton(
              key: Key('continuity-unlink-confirm-$photoId'),
              onPressed: tapped
                  ? null
                  : () async {
                      setDialogState(() => tapped = true);
                      // Handled: failures surface via the command-error
                      // provider.
                      final res = await ref
                          .read(
                            sceneShootsControllerProvider(widget.scope)
                                .notifier,
                          )
                          .unlinkContinuityPhoto(
                            shoot: widget.shoot,
                            photoId: photoId,
                          );
                      res.match<void>((_) {}, (_) {});
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
              child: Text(l10nOf(dialogContext).continuityUnlinkButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// One resolved continuity entry: either a photo found in the season's
/// costume projection (thumbnail-capable) or an orphan id.
sealed class _ResolvedContinuity {
  const _ResolvedContinuity();
}

class _LinkedPhoto extends _ResolvedContinuity {
  const _LinkedPhoto({required this.costumeId, required this.photo});

  final String costumeId;
  final CostumePhotoView photo;
}

class _OrphanPhoto extends _ResolvedContinuity {
  const _OrphanPhoto(this.id);

  final String id;
}

/// Joins linked continuity ids against the season costumes' embedded
/// photos (read-DTO join — the client never fetches bytes blind).
List<_ResolvedContinuity> _resolve(
  List<CostumeView> costumes,
  Iterable<String> linkedIds,
) {
  final byPhotoId = <String, (String, CostumePhotoView)>{};
  for (final costume in costumes) {
    for (final photo in costume.photos) {
      byPhotoId.putIfAbsent(photo.id, () => (costume.id, photo));
    }
  }
  return [
    for (final id in linkedIds)
      switch (byPhotoId[id]) {
        (String costumeId, CostumePhotoView photo) => _LinkedPhoto(
          costumeId: costumeId,
          photo: photo,
        ),
        null => _OrphanPhoto(id),
      },
  ];
}

String _costumeLabel(CostumeView costume) {
  final id = costume.id.length > 8 ? costume.id.substring(0, 8) : costume.id;
  final notes = costume.notes.trim();
  return notes.isEmpty ? 'Costume $id' : 'Costume $id — $notes';
}
