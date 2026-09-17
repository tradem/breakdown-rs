// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'setup_wizard_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The season setup wizard controller (design D1/D2).
///
/// A single `@riverpod` notifier owning the whole [SetupWizardState]:
/// step navigation, draft editing, template application, and the
/// sequential dispatch reduction over the **existing repositories** the
/// individual screens use ([SeasonRepository], [BlockRepository],
/// [EpisodeRepository]) — the wizard adds only sequencing and progress.
///
/// Auto-dispose: the state is ephemeral by design (decision 3 — no draft
/// persistence); leaving the wizard disposes it, reopening starts fresh.

@ProviderFor(SetupWizardController)
final setupWizardControllerProvider = SetupWizardControllerProvider._();

/// The season setup wizard controller (design D1/D2).
///
/// A single `@riverpod` notifier owning the whole [SetupWizardState]:
/// step navigation, draft editing, template application, and the
/// sequential dispatch reduction over the **existing repositories** the
/// individual screens use ([SeasonRepository], [BlockRepository],
/// [EpisodeRepository]) — the wizard adds only sequencing and progress.
///
/// Auto-dispose: the state is ephemeral by design (decision 3 — no draft
/// persistence); leaving the wizard disposes it, reopening starts fresh.
final class SetupWizardControllerProvider
    extends $NotifierProvider<SetupWizardController, SetupWizardState> {
  /// The season setup wizard controller (design D1/D2).
  ///
  /// A single `@riverpod` notifier owning the whole [SetupWizardState]:
  /// step navigation, draft editing, template application, and the
  /// sequential dispatch reduction over the **existing repositories** the
  /// individual screens use ([SeasonRepository], [BlockRepository],
  /// [EpisodeRepository]) — the wizard adds only sequencing and progress.
  ///
  /// Auto-dispose: the state is ephemeral by design (decision 3 — no draft
  /// persistence); leaving the wizard disposes it, reopening starts fresh.
  SetupWizardControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'setupWizardControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$setupWizardControllerHash();

  @$internal
  @override
  SetupWizardController create() => SetupWizardController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SetupWizardState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SetupWizardState>(value),
    );
  }
}

String _$setupWizardControllerHash() =>
    r'897b94d10efd3f00aa66f714b62eaad4e4d1338d';

/// The season setup wizard controller (design D1/D2).
///
/// A single `@riverpod` notifier owning the whole [SetupWizardState]:
/// step navigation, draft editing, template application, and the
/// sequential dispatch reduction over the **existing repositories** the
/// individual screens use ([SeasonRepository], [BlockRepository],
/// [EpisodeRepository]) — the wizard adds only sequencing and progress.
///
/// Auto-dispose: the state is ephemeral by design (decision 3 — no draft
/// persistence); leaving the wizard disposes it, reopening starts fresh.

abstract class _$SetupWizardController extends $Notifier<SetupWizardState> {
  SetupWizardState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SetupWizardState, SetupWizardState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SetupWizardState, SetupWizardState>,
              SetupWizardState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
