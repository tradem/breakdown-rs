// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capture.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(PhotoRationaleSeen)
final photoRationaleSeenProvider = PhotoRationaleSeenProvider._();

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
final class PhotoRationaleSeenProvider
    extends $NotifierProvider<PhotoRationaleSeen, bool> {
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
  PhotoRationaleSeenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoRationaleSeenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoRationaleSeenHash();

  @$internal
  @override
  PhotoRationaleSeen create() => PhotoRationaleSeen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$photoRationaleSeenHash() =>
    r'fc6a78e95b027f8cc8926bc0fd0fce16a2e0ef98';

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

abstract class _$PhotoRationaleSeen extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(openAppSettings)
final openAppSettingsProvider = OpenAppSettingsProvider._();

final class OpenAppSettingsProvider
    extends
        $FunctionalProvider<OpenAppSettings, OpenAppSettings, OpenAppSettings>
    with $Provider<OpenAppSettings> {
  OpenAppSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'openAppSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$openAppSettingsHash();

  @$internal
  @override
  $ProviderElement<OpenAppSettings> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  OpenAppSettings create(Ref ref) {
    return openAppSettings(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OpenAppSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OpenAppSettings>(value),
    );
  }
}

String _$openAppSettingsHash() => r'c6523989710981e24231ca08ebd8c777e0a57958';

/// Injectable prepare seam provider: production runs [defaultPreparePhoto]
/// (background isolate); widget tests override with the synchronous
/// [prepareImageCore] since isolates never complete headless in
/// `flutter_test`.

@ProviderFor(preparePhoto)
final preparePhotoProvider = PreparePhotoProvider._();

/// Injectable prepare seam provider: production runs [defaultPreparePhoto]
/// (background isolate); widget tests override with the synchronous
/// [prepareImageCore] since isolates never complete headless in
/// `flutter_test`.

final class PreparePhotoProvider
    extends $FunctionalProvider<PreparePhoto, PreparePhoto, PreparePhoto>
    with $Provider<PreparePhoto> {
  /// Injectable prepare seam provider: production runs [defaultPreparePhoto]
  /// (background isolate); widget tests override with the synchronous
  /// [prepareImageCore] since isolates never complete headless in
  /// `flutter_test`.
  PreparePhotoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'preparePhotoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$preparePhotoHash();

  @$internal
  @override
  $ProviderElement<PreparePhoto> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PreparePhoto create(Ref ref) {
    return preparePhoto(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PreparePhoto value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PreparePhoto>(value),
    );
  }
}

String _$preparePhotoHash() => r'2aa17c84e6438f738941da7060b14dcd0d8fe37f';

/// Thin, injectable wrapper around [ImagePicker] so widget tests fake the
/// picker (no real camera hardware in CI — Tier-2 fakes the capture).

@ProviderFor(imagePicker)
final imagePickerProvider = ImagePickerProvider._();

/// Thin, injectable wrapper around [ImagePicker] so widget tests fake the
/// picker (no real camera hardware in CI — Tier-2 fakes the capture).

final class ImagePickerProvider
    extends $FunctionalProvider<ImagePicker, ImagePicker, ImagePicker>
    with $Provider<ImagePicker> {
  /// Thin, injectable wrapper around [ImagePicker] so widget tests fake the
  /// picker (no real camera hardware in CI — Tier-2 fakes the capture).
  ImagePickerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'imagePickerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$imagePickerHash();

  @$internal
  @override
  $ProviderElement<ImagePicker> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ImagePicker create(Ref ref) {
    return imagePicker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImagePicker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImagePicker>(value),
    );
  }
}

String _$imagePickerHash() => r'7740c09b2d6b395ce466f1b72b93b31db7bfd740';
