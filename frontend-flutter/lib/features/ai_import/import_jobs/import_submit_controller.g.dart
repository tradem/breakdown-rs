// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_submit_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The submission controller (`flutter-ai-import-workflow` task 3.1).
///
/// The submit dispatch is the AUTHZ-GATE'd write path (task 5.1): the
/// season costume-dept capability is checked via
/// `currentMembershipProvider` BEFORE any network call; a client-side
/// denial renders the localized 403 narrative and issues ZERO calls
/// (provable by the fake-repository call count in tests).
///
/// The upload carries the episode context (design §2.3): the picked
/// episode's id + series id are persisted with the job record right after
/// the 202/200 ack, so the apply step later never guesses an
/// `episode_id`.

@ProviderFor(AiImportSubmitController)
final aiImportSubmitControllerProvider = AiImportSubmitControllerProvider._();

/// The submission controller (`flutter-ai-import-workflow` task 3.1).
///
/// The submit dispatch is the AUTHZ-GATE'd write path (task 5.1): the
/// season costume-dept capability is checked via
/// `currentMembershipProvider` BEFORE any network call; a client-side
/// denial renders the localized 403 narrative and issues ZERO calls
/// (provable by the fake-repository call count in tests).
///
/// The upload carries the episode context (design §2.3): the picked
/// episode's id + series id are persisted with the job record right after
/// the 202/200 ack, so the apply step later never guesses an
/// `episode_id`.
final class AiImportSubmitControllerProvider
    extends $NotifierProvider<AiImportSubmitController, AiImportKind> {
  /// The submission controller (`flutter-ai-import-workflow` task 3.1).
  ///
  /// The submit dispatch is the AUTHZ-GATE'd write path (task 5.1): the
  /// season costume-dept capability is checked via
  /// `currentMembershipProvider` BEFORE any network call; a client-side
  /// denial renders the localized 403 narrative and issues ZERO calls
  /// (provable by the fake-repository call count in tests).
  ///
  /// The upload carries the episode context (design §2.3): the picked
  /// episode's id + series id are persisted with the job record right after
  /// the 202/200 ack, so the apply step later never guesses an
  /// `episode_id`.
  AiImportSubmitControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportSubmitControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportSubmitControllerHash();

  @$internal
  @override
  AiImportSubmitController create() => AiImportSubmitController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiImportKind value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiImportKind>(value),
    );
  }
}

String _$aiImportSubmitControllerHash() =>
    r'3eca7218161a72f9d00a5da6a295091f4fa8e36c';

/// The submission controller (`flutter-ai-import-workflow` task 3.1).
///
/// The submit dispatch is the AUTHZ-GATE'd write path (task 5.1): the
/// season costume-dept capability is checked via
/// `currentMembershipProvider` BEFORE any network call; a client-side
/// denial renders the localized 403 narrative and issues ZERO calls
/// (provable by the fake-repository call count in tests).
///
/// The upload carries the episode context (design §2.3): the picked
/// episode's id + series id are persisted with the job record right after
/// the 202/200 ack, so the apply step later never guesses an
/// `episode_id`.

abstract class _$AiImportSubmitController extends $Notifier<AiImportKind> {
  AiImportKind build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AiImportKind, AiImportKind>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AiImportKind, AiImportKind>,
              AiImportKind,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
