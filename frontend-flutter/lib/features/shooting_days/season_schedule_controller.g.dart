// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_schedule_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Composes the active season's shooting-day board (issue #610).
///
/// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
/// view composes blocks → episodes → days through the existing
/// authenticated seams. Failure semantics mirror the Script composition:
/// an unreadable block list is a `Left` (the view errors), a single failed
/// episode yields a visible partial-load notice.
///
/// A sticky block scope for THIS season narrows the board to that block; a
/// scope from another season is ignored (same reuse rule as the scope chip).

@ProviderFor(seasonScheduleFetch)
final seasonScheduleFetchProvider = SeasonScheduleFetchFamily._();

/// Composes the active season's shooting-day board (issue #610).
///
/// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
/// view composes blocks → episodes → days through the existing
/// authenticated seams. Failure semantics mirror the Script composition:
/// an unreadable block list is a `Left` (the view errors), a single failed
/// episode yields a visible partial-load notice.
///
/// A sticky block scope for THIS season narrows the board to that block; a
/// scope from another season is ignored (same reuse rule as the scope chip).

final class SeasonScheduleFetchProvider
    extends
        $FunctionalProvider<
          AsyncValue<Result<SeasonSchedule>>,
          Result<SeasonSchedule>,
          FutureOr<Result<SeasonSchedule>>
        >
    with
        $FutureModifier<Result<SeasonSchedule>>,
        $FutureProvider<Result<SeasonSchedule>> {
  /// Composes the active season's shooting-day board (issue #610).
  ///
  /// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
  /// view composes blocks → episodes → days through the existing
  /// authenticated seams. Failure semantics mirror the Script composition:
  /// an unreadable block list is a `Left` (the view errors), a single failed
  /// episode yields a visible partial-load notice.
  ///
  /// A sticky block scope for THIS season narrows the board to that block; a
  /// scope from another season is ignored (same reuse rule as the scope chip).
  SeasonScheduleFetchProvider._({
    required SeasonScheduleFetchFamily super.from,
    required SeasonView super.argument,
  }) : super(
         retry: null,
         name: r'seasonScheduleFetchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$seasonScheduleFetchHash();

  @override
  String toString() {
    return r'seasonScheduleFetchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Result<SeasonSchedule>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Result<SeasonSchedule>> create(Ref ref) {
    final argument = this.argument as SeasonView;
    return seasonScheduleFetch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SeasonScheduleFetchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$seasonScheduleFetchHash() =>
    r'156f4b10004dd22e2d8ddf2dd35963bd4ca95fd9';

/// Composes the active season's shooting-day board (issue #610).
///
/// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
/// view composes blocks → episodes → days through the existing
/// authenticated seams. Failure semantics mirror the Script composition:
/// an unreadable block list is a `Left` (the view errors), a single failed
/// episode yields a visible partial-load notice.
///
/// A sticky block scope for THIS season narrows the board to that block; a
/// scope from another season is ignored (same reuse rule as the scope chip).

final class SeasonScheduleFetchFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Result<SeasonSchedule>>,
          SeasonView
        > {
  SeasonScheduleFetchFamily._()
    : super(
        retry: null,
        name: r'seasonScheduleFetchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Composes the active season's shooting-day board (issue #610).
  ///
  /// `GET /v1/episodes/{id}/shooting-days` is episode-scoped, so the season
  /// view composes blocks → episodes → days through the existing
  /// authenticated seams. Failure semantics mirror the Script composition:
  /// an unreadable block list is a `Left` (the view errors), a single failed
  /// episode yields a visible partial-load notice.
  ///
  /// A sticky block scope for THIS season narrows the board to that block; a
  /// scope from another season is ignored (same reuse rule as the scope chip).

  SeasonScheduleFetchProvider call(SeasonView season) =>
      SeasonScheduleFetchProvider._(argument: season, from: this);

  @override
  String toString() => r'seasonScheduleFetchProvider';
}
