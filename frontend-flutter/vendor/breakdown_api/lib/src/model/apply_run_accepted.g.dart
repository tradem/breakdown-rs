// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_accepted.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyRunAccepted extends ApplyRunAccepted {
  @override
  final ApplyState applyState;
  @override
  final String runId;
  @override
  final ApplyStage stage;
  @override
  final DateTime startedAt;

  factory _$ApplyRunAccepted(
          [void Function(ApplyRunAcceptedBuilder)? updates]) =>
      (ApplyRunAcceptedBuilder()..update(updates))._build();

  _$ApplyRunAccepted._(
      {required this.applyState,
      required this.runId,
      required this.stage,
      required this.startedAt})
      : super._();
  @override
  ApplyRunAccepted rebuild(void Function(ApplyRunAcceptedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunAcceptedBuilder toBuilder() =>
      ApplyRunAcceptedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunAccepted &&
        applyState == other.applyState &&
        runId == other.runId &&
        stage == other.stage &&
        startedAt == other.startedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applyState.hashCode);
    _$hash = $jc(_$hash, runId.hashCode);
    _$hash = $jc(_$hash, stage.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunAccepted')
          ..add('applyState', applyState)
          ..add('runId', runId)
          ..add('stage', stage)
          ..add('startedAt', startedAt))
        .toString();
  }
}

class ApplyRunAcceptedBuilder
    implements Builder<ApplyRunAccepted, ApplyRunAcceptedBuilder> {
  _$ApplyRunAccepted? _$v;

  ApplyState? _applyState;
  ApplyState? get applyState => _$this._applyState;
  set applyState(ApplyState? applyState) => _$this._applyState = applyState;

  String? _runId;
  String? get runId => _$this._runId;
  set runId(String? runId) => _$this._runId = runId;

  ApplyStage? _stage;
  ApplyStage? get stage => _$this._stage;
  set stage(ApplyStage? stage) => _$this._stage = stage;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  ApplyRunAcceptedBuilder() {
    ApplyRunAccepted._defaults(this);
  }

  ApplyRunAcceptedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applyState = $v.applyState;
      _runId = $v.runId;
      _stage = $v.stage;
      _startedAt = $v.startedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunAccepted other) {
    _$v = other as _$ApplyRunAccepted;
  }

  @override
  void update(void Function(ApplyRunAcceptedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunAccepted build() => _build();

  _$ApplyRunAccepted _build() {
    final _$result = _$v ??
        _$ApplyRunAccepted._(
          applyState: BuiltValueNullFieldError.checkNotNull(
              applyState, r'ApplyRunAccepted', 'applyState'),
          runId: BuiltValueNullFieldError.checkNotNull(
              runId, r'ApplyRunAccepted', 'runId'),
          stage: BuiltValueNullFieldError.checkNotNull(
              stage, r'ApplyRunAccepted', 'stage'),
          startedAt: BuiltValueNullFieldError.checkNotNull(
              startedAt, r'ApplyRunAccepted', 'startedAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
