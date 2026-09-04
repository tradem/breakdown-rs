// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merged_scene.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MergedScene extends MergedScene {
  @override
  final SceneView scene;
  @override
  final BuiltList<ShootingScheduleRow> scheduleRows;

  factory _$MergedScene([void Function(MergedSceneBuilder)? updates]) =>
      (MergedSceneBuilder()..update(updates))._build();

  _$MergedScene._({required this.scene, required this.scheduleRows})
      : super._();
  @override
  MergedScene rebuild(void Function(MergedSceneBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MergedSceneBuilder toBuilder() => MergedSceneBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MergedScene &&
        scene == other.scene &&
        scheduleRows == other.scheduleRows;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scene.hashCode);
    _$hash = $jc(_$hash, scheduleRows.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MergedScene')
          ..add('scene', scene)
          ..add('scheduleRows', scheduleRows))
        .toString();
  }
}

class MergedSceneBuilder implements Builder<MergedScene, MergedSceneBuilder> {
  _$MergedScene? _$v;

  SceneViewBuilder? _scene;
  SceneViewBuilder get scene => _$this._scene ??= SceneViewBuilder();
  set scene(SceneViewBuilder? scene) => _$this._scene = scene;

  ListBuilder<ShootingScheduleRow>? _scheduleRows;
  ListBuilder<ShootingScheduleRow> get scheduleRows =>
      _$this._scheduleRows ??= ListBuilder<ShootingScheduleRow>();
  set scheduleRows(ListBuilder<ShootingScheduleRow>? scheduleRows) =>
      _$this._scheduleRows = scheduleRows;

  MergedSceneBuilder() {
    MergedScene._defaults(this);
  }

  MergedSceneBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scene = $v.scene.toBuilder();
      _scheduleRows = $v.scheduleRows.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MergedScene other) {
    _$v = other as _$MergedScene;
  }

  @override
  void update(void Function(MergedSceneBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MergedScene build() => _build();

  _$MergedScene _build() {
    _$MergedScene _$result;
    try {
      _$result = _$v ??
          _$MergedScene._(
            scene: scene.build(),
            scheduleRows: scheduleRows.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'scene';
        scene.build();
        _$failedField = 'scheduleRows';
        scheduleRows.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MergedScene', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
