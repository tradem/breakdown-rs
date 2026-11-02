// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_import_report.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The published post-import report, kept until the user dismisses it.
///
/// `keepAlive: true`: the report is published at the END of the import stack
/// and consumed by the Script view, which is a DIFFERENT route tree node — the
/// value must survive the import stack's pop and any later tab switch until the
/// user closes it.

@ProviderFor(AiPostImportReport)
final aiPostImportReportProvider = AiPostImportReportProvider._();

/// The published post-import report, kept until the user dismisses it.
///
/// `keepAlive: true`: the report is published at the END of the import stack
/// and consumed by the Script view, which is a DIFFERENT route tree node — the
/// value must survive the import stack's pop and any later tab switch until the
/// user closes it.
final class AiPostImportReportProvider
    extends $NotifierProvider<AiPostImportReport, PostImportReport?> {
  /// The published post-import report, kept until the user dismisses it.
  ///
  /// `keepAlive: true`: the report is published at the END of the import stack
  /// and consumed by the Script view, which is a DIFFERENT route tree node — the
  /// value must survive the import stack's pop and any later tab switch until the
  /// user closes it.
  AiPostImportReportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiPostImportReportProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiPostImportReportHash();

  @$internal
  @override
  AiPostImportReport create() => AiPostImportReport();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PostImportReport? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PostImportReport?>(value),
    );
  }
}

String _$aiPostImportReportHash() =>
    r'552c9d66ac0c455893a966d91644f9e28f95467d';

/// The published post-import report, kept until the user dismisses it.
///
/// `keepAlive: true`: the report is published at the END of the import stack
/// and consumed by the Script view, which is a DIFFERENT route tree node — the
/// value must survive the import stack's pop and any later tab switch until the
/// user closes it.

abstract class _$AiPostImportReport extends $Notifier<PostImportReport?> {
  PostImportReport? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PostImportReport?, PostImportReport?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PostImportReport?, PostImportReport?>,
              PostImportReport?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
