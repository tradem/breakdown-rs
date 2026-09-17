// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'setup_wizard_screen.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// AI-configuration availability for the completion CTA (design D4): the
/// EXISTING ai-config read decides — no new endpoint, no extra AUTHZ
/// surface (the config read already ships its gate comment, reused
/// verbatim). `false` while the discovery is loading/failed; the honest
/// degradation renders the prerequisite info card (a failed discovery is
/// not "a configuration exists").

@ProviderFor(wizardAiConfigAvailable)
final wizardAiConfigAvailableProvider = WizardAiConfigAvailableProvider._();

/// AI-configuration availability for the completion CTA (design D4): the
/// EXISTING ai-config read decides — no new endpoint, no extra AUTHZ
/// surface (the config read already ships its gate comment, reused
/// verbatim). `false` while the discovery is loading/failed; the honest
/// degradation renders the prerequisite info card (a failed discovery is
/// not "a configuration exists").

final class WizardAiConfigAvailableProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// AI-configuration availability for the completion CTA (design D4): the
  /// EXISTING ai-config read decides — no new endpoint, no extra AUTHZ
  /// surface (the config read already ships its gate comment, reused
  /// verbatim). `false` while the discovery is loading/failed; the honest
  /// degradation renders the prerequisite info card (a failed discovery is
  /// not "a configuration exists").
  WizardAiConfigAvailableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wizardAiConfigAvailableProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wizardAiConfigAvailableHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return wizardAiConfigAvailable(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$wizardAiConfigAvailableHash() =>
    r'bb8382970db3bd298462b59117b59c19cc7a3b1c';
