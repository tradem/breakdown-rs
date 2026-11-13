// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_progress_frame.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyProgressFrame extends ApplyProgressFrame {
  @override
  final ApplyProgress? applyProgress;
  @override
  final ApplyRunOutcome? applyResult;
  @override
  final ApplyState? applyState;
  @override
  final String jobId;
  @override
  final String? runId;

  factory _$ApplyProgressFrame(
          [void Function(ApplyProgressFrameBuilder)? updates]) =>
      (ApplyProgressFrameBuilder()..update(updates))._build();

  _$ApplyProgressFrame._(
      {this.applyProgress,
      this.applyResult,
      this.applyState,
      required this.jobId,
      this.runId})
      : super._();
  @override
  ApplyProgressFrame rebuild(
          void Function(ApplyProgressFrameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyProgressFrameBuilder toBuilder() =>
      ApplyProgressFrameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyProgressFrame &&
        applyProgress == other.applyProgress &&
        applyResult == other.applyResult &&
        applyState == other.applyState &&
        jobId == other.jobId &&
        runId == other.runId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applyProgress.hashCode);
    _$hash = $jc(_$hash, applyResult.hashCode);
    _$hash = $jc(_$hash, applyState.hashCode);
    _$hash = $jc(_$hash, jobId.hashCode);
    _$hash = $jc(_$hash, runId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyProgressFrame')
          ..add('applyProgress', applyProgress)
          ..add('applyResult', applyResult)
          ..add('applyState', applyState)
          ..add('jobId', jobId)
          ..add('runId', runId))
        .toString();
  }
}

class ApplyProgressFrameBuilder
    implements Builder<ApplyProgressFrame, ApplyProgressFrameBuilder> {
  _$ApplyProgressFrame? _$v;

  ApplyProgressBuilder? _applyProgress;
  ApplyProgressBuilder get applyProgress =>
      _$this._applyProgress ??= ApplyProgressBuilder();
  set applyProgress(ApplyProgressBuilder? applyProgress) =>
      _$this._applyProgress = applyProgress;

  ApplyRunOutcomeBuilder? _applyResult;
  ApplyRunOutcomeBuilder get applyResult =>
      _$this._applyResult ??= ApplyRunOutcomeBuilder();
  set applyResult(ApplyRunOutcomeBuilder? applyResult) =>
      _$this._applyResult = applyResult;

  ApplyState? _applyState;
  ApplyState? get applyState => _$this._applyState;
  set applyState(ApplyState? applyState) => _$this._applyState = applyState;

  String? _jobId;
  String? get jobId => _$this._jobId;
  set jobId(String? jobId) => _$this._jobId = jobId;

  String? _runId;
  String? get runId => _$this._runId;
  set runId(String? runId) => _$this._runId = runId;

  ApplyProgressFrameBuilder() {
    ApplyProgressFrame._defaults(this);
  }

  ApplyProgressFrameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applyProgress = $v.applyProgress?.toBuilder();
      _applyResult = $v.applyResult?.toBuilder();
      _applyState = $v.applyState;
      _jobId = $v.jobId;
      _runId = $v.runId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyProgressFrame other) {
    _$v = other as _$ApplyProgressFrame;
  }

  @override
  void update(void Function(ApplyProgressFrameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyProgressFrame build() => _build();

  _$ApplyProgressFrame _build() {
    _$ApplyProgressFrame _$result;
    try {
      _$result = _$v ??
          _$ApplyProgressFrame._(
            applyProgress: _applyProgress?.build(),
            applyResult: _applyResult?.build(),
            applyState: applyState,
            jobId: BuiltValueNullFieldError.checkNotNull(
                jobId, r'ApplyProgressFrame', 'jobId'),
            runId: runId,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'applyProgress';
        _applyProgress?.build();
        _$failedField = 'applyResult';
        _applyResult?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyProgressFrame', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
