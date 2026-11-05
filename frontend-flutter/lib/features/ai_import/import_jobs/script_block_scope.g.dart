// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'script_block_scope.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The job's script-block scope, or `null` when the job row is unreadable.
///
/// `getJobAndCache` (NOT the SSE watch) is the same single-snapshot read the
/// naming card uses (issue #831): the app keeps exactly one SSE consumer (the
/// job-status controller, battery contract D5), and the repository's
/// write-through caches the row for the sibling reads.
///
/// A FAILED read throws into Riverpod's error channel and the surfaces render
/// their quiet "not known" arm — a header fact must never invent a block, and
/// no value is derived from the currently selected block either.

@ProviderFor(aiJobBlockScope)
final aiJobBlockScopeProvider = AiJobBlockScopeFamily._();

/// The job's script-block scope, or `null` when the job row is unreadable.
///
/// `getJobAndCache` (NOT the SSE watch) is the same single-snapshot read the
/// naming card uses (issue #831): the app keeps exactly one SSE consumer (the
/// job-status controller, battery contract D5), and the repository's
/// write-through caches the row for the sibling reads.
///
/// A FAILED read throws into Riverpod's error channel and the surfaces render
/// their quiet "not known" arm — a header fact must never invent a block, and
/// no value is derived from the currently selected block either.

final class AiJobBlockScopeProvider
    extends
        $FunctionalProvider<
          AsyncValue<ScriptBlockScope?>,
          ScriptBlockScope?,
          FutureOr<ScriptBlockScope?>
        >
    with
        $FutureModifier<ScriptBlockScope?>,
        $FutureProvider<ScriptBlockScope?> {
  /// The job's script-block scope, or `null` when the job row is unreadable.
  ///
  /// `getJobAndCache` (NOT the SSE watch) is the same single-snapshot read the
  /// naming card uses (issue #831): the app keeps exactly one SSE consumer (the
  /// job-status controller, battery contract D5), and the repository's
  /// write-through caches the row for the sibling reads.
  ///
  /// A FAILED read throws into Riverpod's error channel and the surfaces render
  /// their quiet "not known" arm — a header fact must never invent a block, and
  /// no value is derived from the currently selected block either.
  AiJobBlockScopeProvider._({
    required AiJobBlockScopeFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noAutoRetry,
         name: r'aiJobBlockScopeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$aiJobBlockScopeHash();

  @override
  String toString() {
    return r'aiJobBlockScopeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ScriptBlockScope?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ScriptBlockScope?> create(Ref ref) {
    final argument = this.argument as String;
    return aiJobBlockScope(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AiJobBlockScopeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$aiJobBlockScopeHash() => r'b32c022aa55b491386f3f69252ed392396f6575e';

/// The job's script-block scope, or `null` when the job row is unreadable.
///
/// `getJobAndCache` (NOT the SSE watch) is the same single-snapshot read the
/// naming card uses (issue #831): the app keeps exactly one SSE consumer (the
/// job-status controller, battery contract D5), and the repository's
/// write-through caches the row for the sibling reads.
///
/// A FAILED read throws into Riverpod's error channel and the surfaces render
/// their quiet "not known" arm — a header fact must never invent a block, and
/// no value is derived from the currently selected block either.

final class AiJobBlockScopeFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ScriptBlockScope?>, String> {
  AiJobBlockScopeFamily._()
    : super(
        retry: _noAutoRetry,
        name: r'aiJobBlockScopeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The job's script-block scope, or `null` when the job row is unreadable.
  ///
  /// `getJobAndCache` (NOT the SSE watch) is the same single-snapshot read the
  /// naming card uses (issue #831): the app keeps exactly one SSE consumer (the
  /// job-status controller, battery contract D5), and the repository's
  /// write-through caches the row for the sibling reads.
  ///
  /// A FAILED read throws into Riverpod's error channel and the surfaces render
  /// their quiet "not known" arm — a header fact must never invent a block, and
  /// no value is derived from the currently selected block either.

  AiJobBlockScopeProvider call(String jobId) =>
      AiJobBlockScopeProvider._(argument: jobId, from: this);

  @override
  String toString() => r'aiJobBlockScopeProvider';
}
