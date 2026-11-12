// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_target.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The season the AI import screen acts in (issue #771).
///
/// The entry point decides it: the season-setup wizard's completion CTA passes
/// the created season explicitly, every other entry has no season of its own and
/// inherits the season the user is acting in.
///
/// "Acting in" has two sources, in this order:
///
/// 1. the ambient block scope ([activeBlockProvider]) — the acted-on block,
///    which is also what the request carries as `X-Active-Block`;
/// 2. the shell's ACTIVE SEASON ([ShellController.activeSeason]) — the season
///    the season chip shows and every tab renders. Picking a season there sets
///    no block (a block is picked later, or not at all), so without this
///    fallback the very common "pick a season, then import" path reached a
///    screen that claimed no season was selected at all and could never enable
///    the submit affordance. The block the target still needs is resolved by
///    [blockScopeResolution] from this season, so the card keeps offering its
///    picker / create / block-less arms.
///
/// `null` means "no season context at all" — the import then has NO resolvable
/// target and must not dispatch, which is the honest state the screen renders
/// instead of sending an upload blindly.
///
/// This is the ONE seam: the target line, the picker's candidates, the submit
/// affordance and the dispatch guard all read this season, so the target the
/// user is shown and the season the request declares cannot drift apart.

@ProviderFor(aiImportSeasonContext)
final aiImportSeasonContextProvider = AiImportSeasonContextFamily._();

/// The season the AI import screen acts in (issue #771).
///
/// The entry point decides it: the season-setup wizard's completion CTA passes
/// the created season explicitly, every other entry has no season of its own and
/// inherits the season the user is acting in.
///
/// "Acting in" has two sources, in this order:
///
/// 1. the ambient block scope ([activeBlockProvider]) — the acted-on block,
///    which is also what the request carries as `X-Active-Block`;
/// 2. the shell's ACTIVE SEASON ([ShellController.activeSeason]) — the season
///    the season chip shows and every tab renders. Picking a season there sets
///    no block (a block is picked later, or not at all), so without this
///    fallback the very common "pick a season, then import" path reached a
///    screen that claimed no season was selected at all and could never enable
///    the submit affordance. The block the target still needs is resolved by
///    [blockScopeResolution] from this season, so the card keeps offering its
///    picker / create / block-less arms.
///
/// `null` means "no season context at all" — the import then has NO resolvable
/// target and must not dispatch, which is the honest state the screen renders
/// instead of sending an upload blindly.
///
/// This is the ONE seam: the target line, the picker's candidates, the submit
/// affordance and the dispatch guard all read this season, so the target the
/// user is shown and the season the request declares cannot drift apart.

final class AiImportSeasonContextProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// The season the AI import screen acts in (issue #771).
  ///
  /// The entry point decides it: the season-setup wizard's completion CTA passes
  /// the created season explicitly, every other entry has no season of its own and
  /// inherits the season the user is acting in.
  ///
  /// "Acting in" has two sources, in this order:
  ///
  /// 1. the ambient block scope ([activeBlockProvider]) — the acted-on block,
  ///    which is also what the request carries as `X-Active-Block`;
  /// 2. the shell's ACTIVE SEASON ([ShellController.activeSeason]) — the season
  ///    the season chip shows and every tab renders. Picking a season there sets
  ///    no block (a block is picked later, or not at all), so without this
  ///    fallback the very common "pick a season, then import" path reached a
  ///    screen that claimed no season was selected at all and could never enable
  ///    the submit affordance. The block the target still needs is resolved by
  ///    [blockScopeResolution] from this season, so the card keeps offering its
  ///    picker / create / block-less arms.
  ///
  /// `null` means "no season context at all" — the import then has NO resolvable
  /// target and must not dispatch, which is the honest state the screen renders
  /// instead of sending an upload blindly.
  ///
  /// This is the ONE seam: the target line, the picker's candidates, the submit
  /// affordance and the dispatch guard all read this season, so the target the
  /// user is shown and the season the request declares cannot drift apart.
  AiImportSeasonContextProvider._({
    required AiImportSeasonContextFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'aiImportSeasonContextProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiImportSeasonContextHash();

  @override
  String toString() {
    return r'aiImportSeasonContextProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    final argument = this.argument as String?;
    return aiImportSeasonContext(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AiImportSeasonContextProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiImportSeasonContextHash() =>
    r'd676291c0bfe175ff59cf7676fd7ac311dc9b6ce';

/// The season the AI import screen acts in (issue #771).
///
/// The entry point decides it: the season-setup wizard's completion CTA passes
/// the created season explicitly, every other entry has no season of its own and
/// inherits the season the user is acting in.
///
/// "Acting in" has two sources, in this order:
///
/// 1. the ambient block scope ([activeBlockProvider]) — the acted-on block,
///    which is also what the request carries as `X-Active-Block`;
/// 2. the shell's ACTIVE SEASON ([ShellController.activeSeason]) — the season
///    the season chip shows and every tab renders. Picking a season there sets
///    no block (a block is picked later, or not at all), so without this
///    fallback the very common "pick a season, then import" path reached a
///    screen that claimed no season was selected at all and could never enable
///    the submit affordance. The block the target still needs is resolved by
///    [blockScopeResolution] from this season, so the card keeps offering its
///    picker / create / block-less arms.
///
/// `null` means "no season context at all" — the import then has NO resolvable
/// target and must not dispatch, which is the honest state the screen renders
/// instead of sending an upload blindly.
///
/// This is the ONE seam: the target line, the picker's candidates, the submit
/// affordance and the dispatch guard all read this season, so the target the
/// user is shown and the season the request declares cannot drift apart.

final class AiImportSeasonContextFamily extends $Family
    with $FunctionalFamilyOverride<String?, String?> {
  AiImportSeasonContextFamily._()
    : super(
        retry: null,
        name: r'aiImportSeasonContextProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The season the AI import screen acts in (issue #771).
  ///
  /// The entry point decides it: the season-setup wizard's completion CTA passes
  /// the created season explicitly, every other entry has no season of its own and
  /// inherits the season the user is acting in.
  ///
  /// "Acting in" has two sources, in this order:
  ///
  /// 1. the ambient block scope ([activeBlockProvider]) — the acted-on block,
  ///    which is also what the request carries as `X-Active-Block`;
  /// 2. the shell's ACTIVE SEASON ([ShellController.activeSeason]) — the season
  ///    the season chip shows and every tab renders. Picking a season there sets
  ///    no block (a block is picked later, or not at all), so without this
  ///    fallback the very common "pick a season, then import" path reached a
  ///    screen that claimed no season was selected at all and could never enable
  ///    the submit affordance. The block the target still needs is resolved by
  ///    [blockScopeResolution] from this season, so the card keeps offering its
  ///    picker / create / block-less arms.
  ///
  /// `null` means "no season context at all" — the import then has NO resolvable
  /// target and must not dispatch, which is the honest state the screen renders
  /// instead of sending an upload blindly.
  ///
  /// This is the ONE seam: the target line, the picker's candidates, the submit
  /// affordance and the dispatch guard all read this season, so the target the
  /// user is shown and the season the request declares cannot drift apart.

  AiImportSeasonContextProvider call(String? explicitSeasonId) =>
      AiImportSeasonContextProvider._(argument: explicitSeasonId, from: this);

  @override
  String toString() => r'aiImportSeasonContextProvider';
}

/// The season NUMBER of the import target, resolved CACHE-ONLY.
///
/// A label that is not cached yields `null`, and the target line renders its
/// explicit "season unknown" narrative rather than triggering a network read on
/// the submit path (same discipline as the scope chip's cache-only number
/// backfill, issue #548). The block number is never resolved this way: it rides
/// on the acted-on `BlockView` / the resolved scope.

@ProviderFor(aiImportSeasonNumber)
final aiImportSeasonNumberProvider = AiImportSeasonNumberFamily._();

/// The season NUMBER of the import target, resolved CACHE-ONLY.
///
/// A label that is not cached yields `null`, and the target line renders its
/// explicit "season unknown" narrative rather than triggering a network read on
/// the submit path (same discipline as the scope chip's cache-only number
/// backfill, issue #548). The block number is never resolved this way: it rides
/// on the acted-on `BlockView` / the resolved scope.

final class AiImportSeasonNumberProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  /// The season NUMBER of the import target, resolved CACHE-ONLY.
  ///
  /// A label that is not cached yields `null`, and the target line renders its
  /// explicit "season unknown" narrative rather than triggering a network read on
  /// the submit path (same discipline as the scope chip's cache-only number
  /// backfill, issue #548). The block number is never resolved this way: it rides
  /// on the acted-on `BlockView` / the resolved scope.
  AiImportSeasonNumberProvider._({
    required AiImportSeasonNumberFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiImportSeasonNumberProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiImportSeasonNumberHash();

  @override
  String toString() {
    return r'aiImportSeasonNumberProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    final argument = this.argument as String;
    return aiImportSeasonNumber(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiImportSeasonNumberProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiImportSeasonNumberHash() =>
    r'17a6e2ec666a1ee3bf7410999bfd7cc83266d399';

/// The season NUMBER of the import target, resolved CACHE-ONLY.
///
/// A label that is not cached yields `null`, and the target line renders its
/// explicit "season unknown" narrative rather than triggering a network read on
/// the submit path (same discipline as the scope chip's cache-only number
/// backfill, issue #548). The block number is never resolved this way: it rides
/// on the acted-on `BlockView` / the resolved scope.

final class AiImportSeasonNumberFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String?>, String> {
  AiImportSeasonNumberFamily._()
    : super(
        retry: null,
        name: r'aiImportSeasonNumberProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The season NUMBER of the import target, resolved CACHE-ONLY.
  ///
  /// A label that is not cached yields `null`, and the target line renders its
  /// explicit "season unknown" narrative rather than triggering a network read on
  /// the submit path (same discipline as the scope chip's cache-only number
  /// backfill, issue #548). The block number is never resolved this way: it rides
  /// on the acted-on `BlockView` / the resolved scope.

  AiImportSeasonNumberProvider call(String seasonId) =>
      AiImportSeasonNumberProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'aiImportSeasonNumberProvider';
}

/// The import target's full season row (issue #828).
///
/// The target card's "create block" affordance opens the SHARED create-block
/// form, which takes a `SeasonView` and pre-fills the command's ids from it
/// (CQRS boundary — never from a second projection lookup). So this resolves
/// the row rather than hand-rolling a second form with a bare id:
///
/// * **cache first** — the normal case, because the user reached this screen
///   through a season/block scope that was itself read from the cache (the
///   cache-only number label [`aiImportSeasonNumber`] and the row share the
///   same read);
/// * **fetch on a miss** — the completed wizard's season, or a cold cache, is
///   not a reason to refuse the affordance; the repository is the single owner
///   of network + cache writes, so the row is fetched through it and cached.
///
/// `null` means the season genuinely could not be read (a transport failure):
/// the card then reports that instead of opening a form it cannot fill.

@ProviderFor(aiImportSeasonView)
final aiImportSeasonViewProvider = AiImportSeasonViewFamily._();

/// The import target's full season row (issue #828).
///
/// The target card's "create block" affordance opens the SHARED create-block
/// form, which takes a `SeasonView` and pre-fills the command's ids from it
/// (CQRS boundary — never from a second projection lookup). So this resolves
/// the row rather than hand-rolling a second form with a bare id:
///
/// * **cache first** — the normal case, because the user reached this screen
///   through a season/block scope that was itself read from the cache (the
///   cache-only number label [`aiImportSeasonNumber`] and the row share the
///   same read);
/// * **fetch on a miss** — the completed wizard's season, or a cold cache, is
///   not a reason to refuse the affordance; the repository is the single owner
///   of network + cache writes, so the row is fetched through it and cached.
///
/// `null` means the season genuinely could not be read (a transport failure):
/// the card then reports that instead of opening a form it cannot fill.

final class AiImportSeasonViewProvider
    extends
        $FunctionalProvider<
          AsyncValue<SeasonView?>,
          SeasonView?,
          FutureOr<SeasonView?>
        >
    with $FutureModifier<SeasonView?>, $FutureProvider<SeasonView?> {
  /// The import target's full season row (issue #828).
  ///
  /// The target card's "create block" affordance opens the SHARED create-block
  /// form, which takes a `SeasonView` and pre-fills the command's ids from it
  /// (CQRS boundary — never from a second projection lookup). So this resolves
  /// the row rather than hand-rolling a second form with a bare id:
  ///
  /// * **cache first** — the normal case, because the user reached this screen
  ///   through a season/block scope that was itself read from the cache (the
  ///   cache-only number label [`aiImportSeasonNumber`] and the row share the
  ///   same read);
  /// * **fetch on a miss** — the completed wizard's season, or a cold cache, is
  ///   not a reason to refuse the affordance; the repository is the single owner
  ///   of network + cache writes, so the row is fetched through it and cached.
  ///
  /// `null` means the season genuinely could not be read (a transport failure):
  /// the card then reports that instead of opening a form it cannot fill.
  AiImportSeasonViewProvider._({
    required AiImportSeasonViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'aiImportSeasonViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiImportSeasonViewHash();

  @override
  String toString() {
    return r'aiImportSeasonViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<SeasonView?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SeasonView?> create(Ref ref) {
    final argument = this.argument as String;
    return aiImportSeasonView(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiImportSeasonViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiImportSeasonViewHash() =>
    r'817e9abac2f9979834c13f85cc27ee8fae73ad88';

/// The import target's full season row (issue #828).
///
/// The target card's "create block" affordance opens the SHARED create-block
/// form, which takes a `SeasonView` and pre-fills the command's ids from it
/// (CQRS boundary — never from a second projection lookup). So this resolves
/// the row rather than hand-rolling a second form with a bare id:
///
/// * **cache first** — the normal case, because the user reached this screen
///   through a season/block scope that was itself read from the cache (the
///   cache-only number label [`aiImportSeasonNumber`] and the row share the
///   same read);
/// * **fetch on a miss** — the completed wizard's season, or a cold cache, is
///   not a reason to refuse the affordance; the repository is the single owner
///   of network + cache writes, so the row is fetched through it and cached.
///
/// `null` means the season genuinely could not be read (a transport failure):
/// the card then reports that instead of opening a form it cannot fill.

final class AiImportSeasonViewFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SeasonView?>, String> {
  AiImportSeasonViewFamily._()
    : super(
        retry: null,
        name: r'aiImportSeasonViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The import target's full season row (issue #828).
  ///
  /// The target card's "create block" affordance opens the SHARED create-block
  /// form, which takes a `SeasonView` and pre-fills the command's ids from it
  /// (CQRS boundary — never from a second projection lookup). So this resolves
  /// the row rather than hand-rolling a second form with a bare id:
  ///
  /// * **cache first** — the normal case, because the user reached this screen
  ///   through a season/block scope that was itself read from the cache (the
  ///   cache-only number label [`aiImportSeasonNumber`] and the row share the
  ///   same read);
  /// * **fetch on a miss** — the completed wizard's season, or a cold cache, is
  ///   not a reason to refuse the affordance; the repository is the single owner
  ///   of network + cache writes, so the row is fetched through it and cached.
  ///
  /// `null` means the season genuinely could not be read (a transport failure):
  /// the card then reports that instead of opening a form it cannot fill.

  AiImportSeasonViewProvider call(String seasonId) =>
      AiImportSeasonViewProvider._(argument: seasonId, from: this);

  @override
  String toString() => r'aiImportSeasonViewProvider';
}
