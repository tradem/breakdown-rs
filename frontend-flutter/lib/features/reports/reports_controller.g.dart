// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reports_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Staged temp directory for report PDFs (production: the platform
/// cache/temporary directory — never the persistent documents directory,
/// never Drift). Tests override with `Directory.systemTemp`.

@ProviderFor(reportsTempDir)
final reportsTempDirProvider = ReportsTempDirProvider._();

/// Staged temp directory for report PDFs (production: the platform
/// cache/temporary directory — never the persistent documents directory,
/// never Drift). Tests override with `Directory.systemTemp`.

final class ReportsTempDirProvider
    extends
        $FunctionalProvider<
          AsyncValue<Directory>,
          Directory,
          FutureOr<Directory>
        >
    with $FutureModifier<Directory>, $FutureProvider<Directory> {
  /// Staged temp directory for report PDFs (production: the platform
  /// cache/temporary directory — never the persistent documents directory,
  /// never Drift). Tests override with `Directory.systemTemp`.
  ReportsTempDirProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportsTempDirProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportsTempDirHash();

  @$internal
  @override
  $FutureProviderElement<Directory> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Directory> create(Ref ref) {
    return reportsTempDir(ref);
  }
}

String _$reportsTempDirHash() => r'180e3f83ed224abecd0488e83abdb44c07741da5';

/// Share seam (production: platform sheet via `share_plus`).

@ProviderFor(reportShareService)
final reportShareServiceProvider = ReportShareServiceProvider._();

/// Share seam (production: platform sheet via `share_plus`).

final class ReportShareServiceProvider
    extends
        $FunctionalProvider<
          ReportShareService,
          ReportShareService,
          ReportShareService
        >
    with $Provider<ReportShareService> {
  /// Share seam (production: platform sheet via `share_plus`).
  ReportShareServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reportShareServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reportShareServiceHash();

  @$internal
  @override
  $ProviderElement<ReportShareService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReportShareService create(Ref ref) {
    return reportShareService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportShareService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReportShareService>(value),
    );
  }
}

String _$reportShareServiceHash() =>
    r'288a7028dd81e5b9eca722c9ba509ba54534c746';

/// The injected Soll-Ist fetch seam
/// (`GET /v1/shooting-days/{id}/report/soll-ist`). Tests override this
/// provider with a fake.

@ProviderFor(reportsSollIstFetch)
final reportsSollIstFetchProvider = ReportsSollIstFetchFamily._();

/// The injected Soll-Ist fetch seam
/// (`GET /v1/shooting-days/{id}/report/soll-ist`). Tests override this
/// provider with a fake.

final class ReportsSollIstFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<SollIstReport>>,
          Result<SollIstReport>,
          FutureOr<Result<SollIstReport>>
        >
    with
        $FutureModifier<Result<SollIstReport>>,
        $FutureProvider<Result<SollIstReport>> {
  /// The injected Soll-Ist fetch seam
  /// (`GET /v1/shooting-days/{id}/report/soll-ist`). Tests override this
  /// provider with a fake.
  ReportsSollIstFetchProvider._({
    required ReportsSollIstFetchFamily super.from,
    required ReportDayScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsSollIstFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsSollIstFetchHash();

  @override
  String toString() {
    return r'reportsSollIstFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<SollIstReport>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<SollIstReport>> create(Ref ref) {
    final argument = this.argument as ReportDayScope;
    return reportsSollIstFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsSollIstFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsSollIstFetchHash() =>
    r'd7eb6631a036e502881e846c0548f899d51956a6';

/// The injected Soll-Ist fetch seam
/// (`GET /v1/shooting-days/{id}/report/soll-ist`). Tests override this
/// provider with a fake.

final class ReportsSollIstFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<SollIstReport>>,
          ReportDayScope
        > {
  ReportsSollIstFetchFamily._()
    : super(
        retry: null,
        name: r'reportsSollIstFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected Soll-Ist fetch seam
  /// (`GET /v1/shooting-days/{id}/report/soll-ist`). Tests override this
  /// provider with a fake.

  ReportsSollIstFetchProvider call(ReportDayScope scope) =>
      ReportsSollIstFetchProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsSollIstFetchProvider';
}

/// The injected dispo fetch seam (planned-count input only).

@ProviderFor(reportsDispoFetch)
final reportsDispoFetchProvider = ReportsDispoFetchFamily._();

/// The injected dispo fetch seam (planned-count input only).

final class ReportsDispoFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<DispoRow>>>,
          Result<List<DispoRow>>,
          FutureOr<Result<List<DispoRow>>>
        >
    with
        $FutureModifier<Result<List<DispoRow>>>,
        $FutureProvider<Result<List<DispoRow>>> {
  /// The injected dispo fetch seam (planned-count input only).
  ReportsDispoFetchProvider._({
    required ReportsDispoFetchFamily super.from,
    required ReportDayScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsDispoFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsDispoFetchHash();

  @override
  String toString() {
    return r'reportsDispoFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<DispoRow>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<DispoRow>>> create(Ref ref) {
    final argument = this.argument as ReportDayScope;
    return reportsDispoFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsDispoFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsDispoFetchHash() => r'41f20adb6f052a0e4e0994528186bad7b3b4d86b';

/// The injected dispo fetch seam (planned-count input only).

final class ReportsDispoFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<DispoRow>>>,
          ReportDayScope
        > {
  ReportsDispoFetchFamily._()
    : super(
        retry: null,
        name: r'reportsDispoFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected dispo fetch seam (planned-count input only).

  ReportsDispoFetchProvider call(ReportDayScope scope) =>
      ReportsDispoFetchProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsDispoFetchProvider';
}

/// The injected shoot-day fetch seam (actual-count input only).

@ProviderFor(reportsShootDayFetch)
final reportsShootDayFetchProvider = ReportsShootDayFetchFamily._();

/// The injected shoot-day fetch seam (actual-count input only).

final class ReportsShootDayFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<List<ShootDayRow>>>,
          Result<List<ShootDayRow>>,
          FutureOr<Result<List<ShootDayRow>>>
        >
    with
        $FutureModifier<Result<List<ShootDayRow>>>,
        $FutureProvider<Result<List<ShootDayRow>>> {
  /// The injected shoot-day fetch seam (actual-count input only).
  ReportsShootDayFetchProvider._({
    required ReportsShootDayFetchFamily super.from,
    required ReportDayScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsShootDayFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsShootDayFetchHash();

  @override
  String toString() {
    return r'reportsShootDayFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<List<ShootDayRow>>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<List<ShootDayRow>>> create(Ref ref) {
    final argument = this.argument as ReportDayScope;
    return reportsShootDayFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsShootDayFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsShootDayFetchHash() =>
    r'b050b53c89701a44f43ff5fd2d867fbe1fcf6287';

/// The injected shoot-day fetch seam (actual-count input only).

final class ReportsShootDayFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<List<ShootDayRow>>>,
          ReportDayScope
        > {
  ReportsShootDayFetchFamily._()
    : super(
        retry: null,
        name: r'reportsShootDayFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The injected shoot-day fetch seam (actual-count input only).

  ReportsShootDayFetchProvider call(ReportDayScope scope) =>
      ReportsShootDayFetchProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsShootDayFetchProvider';
}

/// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
/// state with temp-file staging).

@ProviderFor(ReportsPdfCards)
final reportsPdfCardsProvider = ReportsPdfCardsFamily._();

/// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
/// state with temp-file staging).
final class ReportsPdfCardsProvider
    extends
        $NotifierProvider<ReportsPdfCards, Map<ReportPdfKind, PdfCardState>> {
  /// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
  /// state with temp-file staging).
  ReportsPdfCardsProvider._({
    required ReportsPdfCardsFamily super.from,
    required ReportDayScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsPdfCardsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsPdfCardsHash();

  @override
  String toString() {
    return r'reportsPdfCardsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReportsPdfCards create() => ReportsPdfCards();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<ReportPdfKind, PdfCardState> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<ReportPdfKind, PdfCardState>>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsPdfCardsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsPdfCardsHash() => r'e0706b59acdbdac089d3200e60bcb126621b5bad';

/// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
/// state with temp-file staging).

final class ReportsPdfCardsFamily extends $Family
    with
        $ClassFamilyOverride<
          ReportsPdfCards,
          Map<ReportPdfKind, PdfCardState>,
          Map<ReportPdfKind, PdfCardState>,
          Map<ReportPdfKind, PdfCardState>,
          ReportDayScope
        > {
  ReportsPdfCardsFamily._()
    : super(
        retry: null,
        name: r'reportsPdfCardsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
  /// state with temp-file staging).

  ReportsPdfCardsProvider call(ReportDayScope scope) =>
      ReportsPdfCardsProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsPdfCardsProvider';
}

/// Per-kind PDF card state (controller-owned, NOT Drift — ephemeral fetch
/// state with temp-file staging).

abstract class _$ReportsPdfCards
    extends $Notifier<Map<ReportPdfKind, PdfCardState>> {
  late final _$args = ref.$arg as ReportDayScope;
  ReportDayScope get scope => _$args;

  Map<ReportPdfKind, PdfCardState> build(ReportDayScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<ReportPdfKind, PdfCardState>,
              Map<ReportPdfKind, PdfCardState>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<ReportPdfKind, PdfCardState>,
                Map<ReportPdfKind, PdfCardState>
              >,
              Map<ReportPdfKind, PdfCardState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Last report command failure, surfaced keyed on `code`.

@ProviderFor(ReportsCommandError)
final reportsCommandErrorProvider = ReportsCommandErrorFamily._();

/// Last report command failure, surfaced keyed on `code`.
final class ReportsCommandErrorProvider
    extends $NotifierProvider<ReportsCommandError, ProblemError?> {
  /// Last report command failure, surfaced keyed on `code`.
  ReportsCommandErrorProvider._({
    required ReportsCommandErrorFamily super.from,
    required ReportDayScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsCommandErrorProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsCommandErrorHash();

  @override
  String toString() {
    return r'reportsCommandErrorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReportsCommandError create() => ReportsCommandError();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProblemError? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProblemError?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsCommandErrorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsCommandErrorHash() =>
    r'332181751758c36a2bc13505ae02077e5326a795';

/// Last report command failure, surfaced keyed on `code`.

final class ReportsCommandErrorFamily extends $Family
    with
        $ClassFamilyOverride<
          ReportsCommandError,
          ProblemError?,
          ProblemError?,
          ProblemError?,
          ReportDayScope
        > {
  ReportsCommandErrorFamily._()
    : super(
        retry: null,
        name: r'reportsCommandErrorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Last report command failure, surfaced keyed on `code`.

  ReportsCommandErrorProvider call(ReportDayScope scope) =>
      ReportsCommandErrorProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsCommandErrorProvider';
}

/// Last report command failure, surfaced keyed on `code`.

abstract class _$ReportsCommandError extends $Notifier<ProblemError?> {
  late final _$args = ref.$arg as ReportDayScope;
  ReportDayScope get scope => _$args;

  ProblemError? build(ReportDayScope scope);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Reports controller (seasons reference pattern): read-model fetches for
/// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
/// share per day. PDF bytes never touch Drift; staged temp files are
/// deleted on every non-save exit.

@ProviderFor(ReportsController)
final reportsControllerProvider = ReportsControllerFamily._();

/// Reports controller (seasons reference pattern): read-model fetches for
/// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
/// share per day. PDF bytes never touch Drift; staged temp files are
/// deleted on every non-save exit.
final class ReportsControllerProvider
    extends $NotifierProvider<ReportsController, ReportsScreenState> {
  /// Reports controller (seasons reference pattern): read-model fetches for
  /// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
  /// share per day. PDF bytes never touch Drift; staged temp files are
  /// deleted on every non-save exit.
  ReportsControllerProvider._({
    required ReportsControllerFamily super.from,
    required ReportDayScope super.argument,
  }) : super(
         retry: null,
         name: r'reportsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reportsControllerHash();

  @override
  String toString() {
    return r'reportsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReportsController create() => ReportsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReportsScreenState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReportsScreenState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reportsControllerHash() => r'18e28d8596bb9a12d4b31042625e56f737f29a93';

/// Reports controller (seasons reference pattern): read-model fetches for
/// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
/// share per day. PDF bytes never touch Drift; staged temp files are
/// deleted on every non-save exit.

final class ReportsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ReportsController,
          ReportsScreenState,
          ReportsScreenState,
          ReportsScreenState,
          ReportDayScope
        > {
  ReportsControllerFamily._()
    : super(
        retry: null,
        name: r'reportsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Reports controller (seasons reference pattern): read-model fetches for
  /// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
  /// share per day. PDF bytes never touch Drift; staged temp files are
  /// deleted on every non-save exit.

  ReportsControllerProvider call(ReportDayScope scope) =>
      ReportsControllerProvider._(argument: scope, from: this);

  @override
  String toString() => r'reportsControllerProvider';
}

/// Reports controller (seasons reference pattern): read-model fetches for
/// the on-screen Soll-Ist report plus user-initiated PDF fetch/preview/
/// share per day. PDF bytes never touch Drift; staged temp files are
/// deleted on every non-save exit.

abstract class _$ReportsController extends $Notifier<ReportsScreenState> {
  late final _$args = ref.$arg as ReportDayScope;
  ReportDayScope get scope => _$args;

  ReportsScreenState build(ReportDayScope scope);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ReportsScreenState, ReportsScreenState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReportsScreenState, ReportsScreenState>,
              ReportsScreenState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
