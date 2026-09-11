// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'projector_health_snapshot.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ProjectorHealthSnapshot extends ProjectorHealthSnapshot {
  @override
  final BuiltList<CheckpointProgress> checkpoints;
  @override
  final int deadLetterCount;
  @override
  final BuiltList<DeadLetterEntry> deadLetters;

  factory _$ProjectorHealthSnapshot(
          [void Function(ProjectorHealthSnapshotBuilder)? updates]) =>
      (ProjectorHealthSnapshotBuilder()..update(updates))._build();

  _$ProjectorHealthSnapshot._(
      {required this.checkpoints,
      required this.deadLetterCount,
      required this.deadLetters})
      : super._();
  @override
  ProjectorHealthSnapshot rebuild(
          void Function(ProjectorHealthSnapshotBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ProjectorHealthSnapshotBuilder toBuilder() =>
      ProjectorHealthSnapshotBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ProjectorHealthSnapshot &&
        checkpoints == other.checkpoints &&
        deadLetterCount == other.deadLetterCount &&
        deadLetters == other.deadLetters;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, checkpoints.hashCode);
    _$hash = $jc(_$hash, deadLetterCount.hashCode);
    _$hash = $jc(_$hash, deadLetters.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ProjectorHealthSnapshot')
          ..add('checkpoints', checkpoints)
          ..add('deadLetterCount', deadLetterCount)
          ..add('deadLetters', deadLetters))
        .toString();
  }
}

class ProjectorHealthSnapshotBuilder
    implements
        Builder<ProjectorHealthSnapshot, ProjectorHealthSnapshotBuilder> {
  _$ProjectorHealthSnapshot? _$v;

  ListBuilder<CheckpointProgress>? _checkpoints;
  ListBuilder<CheckpointProgress> get checkpoints =>
      _$this._checkpoints ??= ListBuilder<CheckpointProgress>();
  set checkpoints(ListBuilder<CheckpointProgress>? checkpoints) =>
      _$this._checkpoints = checkpoints;

  int? _deadLetterCount;
  int? get deadLetterCount => _$this._deadLetterCount;
  set deadLetterCount(int? deadLetterCount) =>
      _$this._deadLetterCount = deadLetterCount;

  ListBuilder<DeadLetterEntry>? _deadLetters;
  ListBuilder<DeadLetterEntry> get deadLetters =>
      _$this._deadLetters ??= ListBuilder<DeadLetterEntry>();
  set deadLetters(ListBuilder<DeadLetterEntry>? deadLetters) =>
      _$this._deadLetters = deadLetters;

  ProjectorHealthSnapshotBuilder() {
    ProjectorHealthSnapshot._defaults(this);
  }

  ProjectorHealthSnapshotBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _checkpoints = $v.checkpoints.toBuilder();
      _deadLetterCount = $v.deadLetterCount;
      _deadLetters = $v.deadLetters.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ProjectorHealthSnapshot other) {
    _$v = other as _$ProjectorHealthSnapshot;
  }

  @override
  void update(void Function(ProjectorHealthSnapshotBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ProjectorHealthSnapshot build() => _build();

  _$ProjectorHealthSnapshot _build() {
    _$ProjectorHealthSnapshot _$result;
    try {
      _$result = _$v ??
          _$ProjectorHealthSnapshot._(
            checkpoints: checkpoints.build(),
            deadLetterCount: BuiltValueNullFieldError.checkNotNull(
                deadLetterCount, r'ProjectorHealthSnapshot', 'deadLetterCount'),
            deadLetters: deadLetters.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'checkpoints';
        checkpoints.build();

        _$failedField = 'deadLetters';
        deadLetters.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ProjectorHealthSnapshot', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
