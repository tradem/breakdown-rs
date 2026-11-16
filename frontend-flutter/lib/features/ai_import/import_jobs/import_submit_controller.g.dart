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
/// season piece-dept capability is checked via
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
/// season piece-dept capability is checked via
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
  /// season piece-dept capability is checked via
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
    r'a180e996272e6bd28d60b1a2ef649b01a785592f';

/// The submission controller (`flutter-ai-import-workflow` task 3.1).
///
/// The submit dispatch is the AUTHZ-GATE'd write path (task 5.1): the
/// season piece-dept capability is checked via
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

/// The pending document (picked file). Cleared after every dispatch —
/// by [selectKind] (a kind switch invalidates the body) and by the
/// screen after a successful dispatch.

@ProviderFor(PendingDocument)
final pendingDocumentProvider = PendingDocumentProvider._();

/// The pending document (picked file). Cleared after every dispatch —
/// by [selectKind] (a kind switch invalidates the body) and by the
/// screen after a successful dispatch.
final class PendingDocumentProvider
    extends $NotifierProvider<PendingDocument, AiImportDocument?> {
  /// The pending document (picked file). Cleared after every dispatch —
  /// by [selectKind] (a kind switch invalidates the body) and by the
  /// screen after a successful dispatch.
  PendingDocumentProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingDocumentProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingDocumentHash();

  @$internal
  @override
  PendingDocument create() => PendingDocument();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiImportDocument? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiImportDocument?>(value),
    );
  }
}

String _$pendingDocumentHash() => r'427283b6ddba0a76e91a13f52cfbf39868057f78';

/// The pending document (picked file). Cleared after every dispatch —
/// by [selectKind] (a kind switch invalidates the body) and by the
/// screen after a successful dispatch.

abstract class _$PendingDocument extends $Notifier<AiImportDocument?> {
  AiImportDocument? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AiImportDocument?, AiImportDocument?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AiImportDocument?, AiImportDocument?>,
              AiImportDocument?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// "Block extrahieren": this dispatch takes its target block from the SCRIPT
/// (issue #898) instead of writing into the active block.
///
/// `true` makes the upload omit `X-Active-Block` and declare only its season —
/// the block-less dispatch of issue #829 — so the job starts without a block and
/// the preview adopts the block the script states (the existing block carrying
/// that number, or a block created with it).
///
/// Two hard rules follow from what this flag is NOT: it is **per dispatch**, not
/// a mode (the kind switch and a successful dispatch clear it, so no stale flag
/// can turn a later upload block-less behind the user's back), and it is **never
/// expressed by clearing `activeBlockProvider`** — that scope is the shell's
/// block pill and the target of other screens, so dropping it to mean "this
/// import" would silently re-target them.
///
/// `keepAlive` because the flag outlives its subscriber: the dispatch resets it
/// through a captured notifier after the upload resolves, and a controller the
/// screen dropped mid-upload must still consume the intent (review of #898).

@ProviderFor(AiImportExtractBlock)
final aiImportExtractBlockProvider = AiImportExtractBlockProvider._();

/// "Block extrahieren": this dispatch takes its target block from the SCRIPT
/// (issue #898) instead of writing into the active block.
///
/// `true` makes the upload omit `X-Active-Block` and declare only its season —
/// the block-less dispatch of issue #829 — so the job starts without a block and
/// the preview adopts the block the script states (the existing block carrying
/// that number, or a block created with it).
///
/// Two hard rules follow from what this flag is NOT: it is **per dispatch**, not
/// a mode (the kind switch and a successful dispatch clear it, so no stale flag
/// can turn a later upload block-less behind the user's back), and it is **never
/// expressed by clearing `activeBlockProvider`** — that scope is the shell's
/// block pill and the target of other screens, so dropping it to mean "this
/// import" would silently re-target them.
///
/// `keepAlive` because the flag outlives its subscriber: the dispatch resets it
/// through a captured notifier after the upload resolves, and a controller the
/// screen dropped mid-upload must still consume the intent (review of #898).
final class AiImportExtractBlockProvider
    extends $NotifierProvider<AiImportExtractBlock, bool> {
  /// "Block extrahieren": this dispatch takes its target block from the SCRIPT
  /// (issue #898) instead of writing into the active block.
  ///
  /// `true` makes the upload omit `X-Active-Block` and declare only its season —
  /// the block-less dispatch of issue #829 — so the job starts without a block and
  /// the preview adopts the block the script states (the existing block carrying
  /// that number, or a block created with it).
  ///
  /// Two hard rules follow from what this flag is NOT: it is **per dispatch**, not
  /// a mode (the kind switch and a successful dispatch clear it, so no stale flag
  /// can turn a later upload block-less behind the user's back), and it is **never
  /// expressed by clearing `activeBlockProvider`** — that scope is the shell's
  /// block pill and the target of other screens, so dropping it to mean "this
  /// import" would silently re-target them.
  ///
  /// `keepAlive` because the flag outlives its subscriber: the dispatch resets it
  /// through a captured notifier after the upload resolves, and a controller the
  /// screen dropped mid-upload must still consume the intent (review of #898).
  AiImportExtractBlockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiImportExtractBlockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiImportExtractBlockHash();

  @$internal
  @override
  AiImportExtractBlock create() => AiImportExtractBlock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$aiImportExtractBlockHash() =>
    r'8ab8a847c136b6ce59b591681a2d39a75f17f118';

/// "Block extrahieren": this dispatch takes its target block from the SCRIPT
/// (issue #898) instead of writing into the active block.
///
/// `true` makes the upload omit `X-Active-Block` and declare only its season —
/// the block-less dispatch of issue #829 — so the job starts without a block and
/// the preview adopts the block the script states (the existing block carrying
/// that number, or a block created with it).
///
/// Two hard rules follow from what this flag is NOT: it is **per dispatch**, not
/// a mode (the kind switch and a successful dispatch clear it, so no stale flag
/// can turn a later upload block-less behind the user's back), and it is **never
/// expressed by clearing `activeBlockProvider`** — that scope is the shell's
/// block pill and the target of other screens, so dropping it to mean "this
/// import" would silently re-target them.
///
/// `keepAlive` because the flag outlives its subscriber: the dispatch resets it
/// through a captured notifier after the upload resolves, and a controller the
/// screen dropped mid-upload must still consume the intent (review of #898).

abstract class _$AiImportExtractBlock extends $Notifier<bool> {
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

/// Non-fatal context-stamp warning (design §2.3): the upload ack was
/// accepted and the job exists server-side, but the client-local
/// episode/series context could not be persisted. The submit screen
/// surfaces it as a warning while STILL navigating to the job; cleared
/// at the start of every dispatch.

@ProviderFor(AiStampWarning)
final aiStampWarningProvider = AiStampWarningProvider._();

/// Non-fatal context-stamp warning (design §2.3): the upload ack was
/// accepted and the job exists server-side, but the client-local
/// episode/series context could not be persisted. The submit screen
/// surfaces it as a warning while STILL navigating to the job; cleared
/// at the start of every dispatch.
final class AiStampWarningProvider
    extends $NotifierProvider<AiStampWarning, ProblemError?> {
  /// Non-fatal context-stamp warning (design §2.3): the upload ack was
  /// accepted and the job exists server-side, but the client-local
  /// episode/series context could not be persisted. The submit screen
  /// surfaces it as a warning while STILL navigating to the job; cleared
  /// at the start of every dispatch.
  AiStampWarningProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiStampWarningProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiStampWarningHash();

  @$internal
  @override
  AiStampWarning create() => AiStampWarning();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }
}

String _$aiStampWarningHash() => r'1fecc6237f00a8d268a41798640b22a2c2129442';

/// Non-fatal context-stamp warning (design §2.3): the upload ack was
/// accepted and the job exists server-side, but the client-local
/// episode/series context could not be persisted. The submit screen
/// surfaces it as a warning while STILL navigating to the job; cleared
/// at the start of every dispatch.

abstract class _$AiStampWarning extends $Notifier<ProblemError?> {
  ProblemError? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ProblemError?, ProblemError?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProblemError?, ProblemError?>,
              ProblemError?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// The episode the user picked as the apply target for the NEXT import
/// (submit-time context, design §2.3). Controller state — not navigation
/// state; cleared after the dispatch settles.

@ProviderFor(PendingEpisode)
final pendingEpisodeProvider = PendingEpisodeProvider._();

/// The episode the user picked as the apply target for the NEXT import
/// (submit-time context, design §2.3). Controller state — not navigation
/// state; cleared after the dispatch settles.
final class PendingEpisodeProvider
    extends $NotifierProvider<PendingEpisode, EpisodeView?> {
  /// The episode the user picked as the apply target for the NEXT import
  /// (submit-time context, design §2.3). Controller state — not navigation
  /// state; cleared after the dispatch settles.
  PendingEpisodeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingEpisodeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingEpisodeHash();

  @$internal
  @override
  PendingEpisode create() => PendingEpisode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(EpisodeView? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<EpisodeView?>(value),
    );
  }
}

String _$pendingEpisodeHash() => r'5561e4831be07a14f30f56229cf2e29ae2fc0ab1';

/// The episode the user picked as the apply target for the NEXT import
/// (submit-time context, design §2.3). Controller state — not navigation
/// state; cleared after the dispatch settles.

abstract class _$PendingEpisode extends $Notifier<EpisodeView?> {
  EpisodeView? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<EpisodeView?, EpisodeView?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<EpisodeView?, EpisodeView?>,
              EpisodeView?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
