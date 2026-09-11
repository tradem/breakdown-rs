// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkpoint_progress.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CheckpointProgress extends CheckpointProgress {
  @override
  final int partitionId;
  @override
  final String projectionId;
  @override
  final int sequence;

  factory _$CheckpointProgress(
          [void Function(CheckpointProgressBuilder)? updates]) =>
      (CheckpointProgressBuilder()..update(updates))._build();

  _$CheckpointProgress._(
      {required this.partitionId,
      required this.projectionId,
      required this.sequence})
      : super._();
  @override
  CheckpointProgress rebuild(
          void Function(CheckpointProgressBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CheckpointProgressBuilder toBuilder() =>
      CheckpointProgressBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CheckpointProgress &&
        partitionId == other.partitionId &&
        projectionId == other.projectionId &&
        sequence == other.sequence;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, partitionId.hashCode);
    _$hash = $jc(_$hash, projectionId.hashCode);
    _$hash = $jc(_$hash, sequence.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CheckpointProgress')
          ..add('partitionId', partitionId)
          ..add('projectionId', projectionId)
          ..add('sequence', sequence))
        .toString();
  }
}

class CheckpointProgressBuilder
    implements Builder<CheckpointProgress, CheckpointProgressBuilder> {
  _$CheckpointProgress? _$v;

  int? _partitionId;
  int? get partitionId => _$this._partitionId;
  set partitionId(int? partitionId) => _$this._partitionId = partitionId;

  String? _projectionId;
  String? get projectionId => _$this._projectionId;
  set projectionId(String? projectionId) => _$this._projectionId = projectionId;

  int? _sequence;
  int? get sequence => _$this._sequence;
  set sequence(int? sequence) => _$this._sequence = sequence;

  CheckpointProgressBuilder() {
    CheckpointProgress._defaults(this);
  }

  CheckpointProgressBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _partitionId = $v.partitionId;
      _projectionId = $v.projectionId;
      _sequence = $v.sequence;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CheckpointProgress other) {
    _$v = other as _$CheckpointProgress;
  }

  @override
  void update(void Function(CheckpointProgressBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CheckpointProgress build() => _build();

  _$CheckpointProgress _build() {
    final _$result = _$v ??
        _$CheckpointProgress._(
          partitionId: BuiltValueNullFieldError.checkNotNull(
              partitionId, r'CheckpointProgress', 'partitionId'),
          projectionId: BuiltValueNullFieldError.checkNotNull(
              projectionId, r'CheckpointProgress', 'projectionId'),
          sequence: BuiltValueNullFieldError.checkNotNull(
              sequence, r'CheckpointProgress', 'sequence'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
