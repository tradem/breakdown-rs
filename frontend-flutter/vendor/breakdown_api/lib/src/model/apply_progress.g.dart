// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_progress.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyProgress extends ApplyProgress {
  @override
  final int? applied;
  @override
  final String? runId;
  @override
  final ApplyStage stage;
  @override
  final DateTime startedAt;
  @override
  final int? total;
  @override
  final DateTime updatedAt;

  factory _$ApplyProgress([void Function(ApplyProgressBuilder)? updates]) =>
      (ApplyProgressBuilder()..update(updates))._build();

  _$ApplyProgress._(
      {this.applied,
      this.runId,
      required this.stage,
      required this.startedAt,
      this.total,
      required this.updatedAt})
      : super._();
  @override
  ApplyProgress rebuild(void Function(ApplyProgressBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyProgressBuilder toBuilder() => ApplyProgressBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyProgress &&
        applied == other.applied &&
        runId == other.runId &&
        stage == other.stage &&
        startedAt == other.startedAt &&
        total == other.total &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, runId.hashCode);
    _$hash = $jc(_$hash, stage.hashCode);
    _$hash = $jc(_$hash, startedAt.hashCode);
    _$hash = $jc(_$hash, total.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyProgress')
          ..add('applied', applied)
          ..add('runId', runId)
          ..add('stage', stage)
          ..add('startedAt', startedAt)
          ..add('total', total)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class ApplyProgressBuilder
    implements Builder<ApplyProgress, ApplyProgressBuilder> {
  _$ApplyProgress? _$v;

  int? _applied;
  int? get applied => _$this._applied;
  set applied(int? applied) => _$this._applied = applied;

  String? _runId;
  String? get runId => _$this._runId;
  set runId(String? runId) => _$this._runId = runId;

  ApplyStage? _stage;
  ApplyStage? get stage => _$this._stage;
  set stage(ApplyStage? stage) => _$this._stage = stage;

  DateTime? _startedAt;
  DateTime? get startedAt => _$this._startedAt;
  set startedAt(DateTime? startedAt) => _$this._startedAt = startedAt;

  int? _total;
  int? get total => _$this._total;
  set total(int? total) => _$this._total = total;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  ApplyProgressBuilder() {
    ApplyProgress._defaults(this);
  }

  ApplyProgressBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _applied = $v.applied;
      _runId = $v.runId;
      _stage = $v.stage;
      _startedAt = $v.startedAt;
      _total = $v.total;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyProgress other) {
    _$v = other as _$ApplyProgress;
  }

  @override
  void update(void Function(ApplyProgressBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyProgress build() => _build();

  _$ApplyProgress _build() {
    final _$result = _$v ??
        _$ApplyProgress._(
          applied: applied,
          runId: runId,
          stage: BuiltValueNullFieldError.checkNotNull(
              stage, r'ApplyProgress', 'stage'),
          startedAt: BuiltValueNullFieldError.checkNotNull(
              startedAt, r'ApplyProgress', 'startedAt'),
          total: total,
          updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt, r'ApplyProgress', 'updatedAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
