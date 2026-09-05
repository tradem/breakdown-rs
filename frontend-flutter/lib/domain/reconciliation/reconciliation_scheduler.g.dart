// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reconciliation_scheduler.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The reconciliation backoff seam (overridden with a controllable fake in
/// tests).

@ProviderFor(reconciliationScheduler)
final reconciliationSchedulerProvider = ReconciliationSchedulerProvider._();

/// The reconciliation backoff seam (overridden with a controllable fake in
/// tests).

final class ReconciliationSchedulerProvider
    extends
        $FunctionalProvider<
          ReconciliationScheduler,
          ReconciliationScheduler,
          ReconciliationScheduler
        >
    with $Provider<ReconciliationScheduler> {
  /// The reconciliation backoff seam (overridden with a controllable fake in
  /// tests).
  ReconciliationSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reconciliationSchedulerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reconciliationSchedulerHash();

  @$internal
  @override
  $ProviderElement<ReconciliationScheduler> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReconciliationScheduler create(Ref ref) {
    return reconciliationScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReconciliationScheduler value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReconciliationScheduler>(value),
    );
  }
}

String _$reconciliationSchedulerHash() =>
    r'0f4a742ba7b53da9a2ecf4ecf5c28ef57acd38da';
