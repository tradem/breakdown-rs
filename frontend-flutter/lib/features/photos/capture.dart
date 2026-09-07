// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'prepare.dart';

part 'capture.g.dart';

/// Point-of-use camera capture with in-app rationale (Task 3.2, spec
/// flutter-photos-feature).
///
/// * The system picker/camera flow (`image_picker`) is triggered ONLY at the
///   point of use (store compliance — no background service or wake-up holds
///   the camera pipeline alive).
/// * Before the FIRST system permission prompt, the app shows its own
///   plain-language rationale, remembered by [photoRationaleSeenProvider]
///   (session-scoped local flag).
/// * A denial at the system prompt ends the flow with a re-rationale plus an
///   "open settings" affordance (injectable [openAppSettings] seam).
/// * A permission revoked between sessions surfaces as
///   `camera.unavailable` copy — state is never assumed from the previous
///   session, and permission state is never read or cached outside the
///   capture intent.
///
/// Camera-permission behavioral matrix (spec scenarios):
/// * denied at prompt → rationale re-shown with "open settings" affordance;
/// * granted then revoked between sessions → `camera.unavailable` copy;
/// * permission state is never cached from system APIs outside the intent.

/// Session-scoped flag: the in-app rationale was shown. Kept in its own
/// keepAlive notifier so the dialog appears once per session, before the
/// first system prompt — never on later captures.
@Riverpod(keepAlive: true)
class PhotoRationaleSeen extends _$PhotoRationaleSeen {
  @override
  bool build() => false;

  void markSeen() => state = true;
}

/// Opens the OS app-settings screen (the "open settings" affordance).
/// Injectable seam: tests override with a recording fake; production wires
/// the platform channel. Returns `true` when the settings UI opened.
typedef OpenAppSettings = Future<bool> Function();

/// Default opener via the `app_settings` package (real Android +
/// iOS handlers — `SystemChannels.platform` defines no `openAppSettings`
/// method, so a raw platform-channel call always fails closed). Returns
/// `false` when the platform cannot open settings — the dialog copy still
/// guides the user.
Future<bool> defaultOpenAppSettings() async {
  try {
    await AppSettings.openAppSettings();
    return true;
  } on Object {
    return false;
  }
}

@riverpod
OpenAppSettings openAppSettings(Ref ref) => defaultOpenAppSettings;

/// Injectable prepare seam provider: production runs [defaultPreparePhoto]
/// (background isolate); widget tests override with the synchronous
/// [prepareImageCore] since isolates never complete headless in
/// `flutter_test`.
@riverpod
PreparePhoto preparePhoto(Ref ref) => defaultPreparePhoto;

/// Thin, injectable wrapper around [ImagePicker] so widget tests fake the
/// picker (no real camera hardware in CI — Tier-2 fakes the capture).
@riverpod
ImagePicker imagePicker(Ref ref) => ImagePicker();

/// Outcome of a capture intent (never a throw — AGENTS.md §5).
sealed class CaptureOutcome {
  const CaptureOutcome();
}

/// The user picked a file (caller runs prepare → upload).
class CapturePicked extends CaptureOutcome {
  const CapturePicked(this.file);

  final XFile file;
}

/// The user cancelled the picker (no error, no retry affordance).
class CaptureCancelled extends CaptureOutcome {
  const CaptureCancelled();
}

/// The system permission was denied at the prompt → re-rationale with the
/// "open settings" affordance. Source-aware: the copy and dialog title
/// adapt to camera vs photo-library denial.
class CaptureDenied extends CaptureOutcome {
  const CaptureDenied(this.source);

  final ImageSource source;
}

/// The camera is unavailable (revoked between sessions, no camera hardware,
/// or a platform failure) → `camera.unavailable` copy.
class CaptureUnavailable extends CaptureOutcome {
  const CaptureUnavailable();
}

/// Runs one capture intent: rationale (first time) → system picker.
///
/// [showRationale] displays the in-app rationale dialog and resolves `true`
/// when the user accepts (proceed to the system prompt). It is invoked at
/// most once per session (guarded by [photoRationaleSeenProvider]).
Future<CaptureOutcome> runCaptureIntent({
  required ImageSource source,
  required Future<bool> Function() showRationale,
  required ImagePicker picker,
  required bool rationaleSeen,
  required void Function() markRationaleSeen,
}) async {
  if (!rationaleSeen) {
    final accepted = await showRationale();
    markRationaleSeen();
    if (!accepted) return const CaptureCancelled();
  }
  try {
    final file = await picker.pickImage(source: source);
    if (file == null) return const CaptureCancelled();
    return CapturePicked(file);
  } on PlatformException catch (e) {
    // Denial codes are source-aware: the camera prompt denies with
    // `camera_access_denied`, the photo-library prompt with
    // `photo_access_denied`. Anything else (no camera, revoked
    // mid-flight, platform failure) is unavailable — never assumed from
    // the previous session.
    if (e.code == kCameraAccessDeniedCode) {
      return CaptureDenied(source);
    }
    if (e.code == kPhotoAccessDeniedCode) {
      return CaptureDenied(source);
    }
    return const CaptureUnavailable();
  } on Object {
    return const CaptureUnavailable();
  }
}

/// Localized client-side copy for capture outcomes, keyed on stable codes
/// (never server `detail` text — these are client-side codes).
String captureOutcomeCopy(CaptureOutcome outcome) => switch (outcome) {
  CaptureDenied(:final source) => switch (source) {
    ImageSource.camera =>
      'Camera access is disabled. Enable camera access in settings to '
          'document costumes.',
    _ =>
      'Photo library access is disabled. Enable photo access in settings '
          'to document costumes.',
  },
  CaptureUnavailable() =>
    'The camera is currently unavailable. Check settings and try again.',
  CapturePicked() || CaptureCancelled() => '',
};

/// Dialog title matching [captureOutcomeCopy] (camera vs photo-library).
String captureDeniedTitle(CaptureOutcome outcome) => switch (outcome) {
  CaptureDenied(source: ImageSource.camera) => 'Camera access disabled',
  _ => 'Photo library access disabled',
};

/// Debug helper: the platform exception codes the denied branch keys on.
@visibleForTesting
const String kCameraAccessDeniedCode = 'camera_access_denied';

/// Debug helper: the photo-library denial code (gallery source).
@visibleForTesting
const String kPhotoAccessDeniedCode = 'photo_access_denied';
