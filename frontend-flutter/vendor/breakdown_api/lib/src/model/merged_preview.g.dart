// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merged_preview.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MergedPreview extends MergedPreview {
  @override
  final BuiltList<MergedScene> scenes;
  @override
  final BuiltList<ShootingScheduleRow> unmatchedScheduleRows;
  @override
  final BuiltList<SceneView> unmatchedScriptScenes;

  factory _$MergedPreview([void Function(MergedPreviewBuilder)? updates]) =>
      (MergedPreviewBuilder()..update(updates))._build();

  _$MergedPreview._(
      {required this.scenes,
      required this.unmatchedScheduleRows,
      required this.unmatchedScriptScenes})
      : super._();
  @override
  MergedPreview rebuild(void Function(MergedPreviewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MergedPreviewBuilder toBuilder() => MergedPreviewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MergedPreview &&
        scenes == other.scenes &&
        unmatchedScheduleRows == other.unmatchedScheduleRows &&
        unmatchedScriptScenes == other.unmatchedScriptScenes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scenes.hashCode);
    _$hash = $jc(_$hash, unmatchedScheduleRows.hashCode);
    _$hash = $jc(_$hash, unmatchedScriptScenes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MergedPreview')
          ..add('scenes', scenes)
          ..add('unmatchedScheduleRows', unmatchedScheduleRows)
          ..add('unmatchedScriptScenes', unmatchedScriptScenes))
        .toString();
  }
}

class MergedPreviewBuilder
    implements Builder<MergedPreview, MergedPreviewBuilder> {
  _$MergedPreview? _$v;

  ListBuilder<MergedScene>? _scenes;
  ListBuilder<MergedScene> get scenes =>
      _$this._scenes ??= ListBuilder<MergedScene>();
  set scenes(ListBuilder<MergedScene>? scenes) => _$this._scenes = scenes;

  ListBuilder<ShootingScheduleRow>? _unmatchedScheduleRows;
  ListBuilder<ShootingScheduleRow> get unmatchedScheduleRows =>
      _$this._unmatchedScheduleRows ??= ListBuilder<ShootingScheduleRow>();
  set unmatchedScheduleRows(
          ListBuilder<ShootingScheduleRow>? unmatchedScheduleRows) =>
      _$this._unmatchedScheduleRows = unmatchedScheduleRows;

  ListBuilder<SceneView>? _unmatchedScriptScenes;
  ListBuilder<SceneView> get unmatchedScriptScenes =>
      _$this._unmatchedScriptScenes ??= ListBuilder<SceneView>();
  set unmatchedScriptScenes(ListBuilder<SceneView>? unmatchedScriptScenes) =>
      _$this._unmatchedScriptScenes = unmatchedScriptScenes;

  MergedPreviewBuilder() {
    MergedPreview._defaults(this);
  }

  MergedPreviewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scenes = $v.scenes.toBuilder();
      _unmatchedScheduleRows = $v.unmatchedScheduleRows.toBuilder();
      _unmatchedScriptScenes = $v.unmatchedScriptScenes.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MergedPreview other) {
    _$v = other as _$MergedPreview;
  }

  @override
  void update(void Function(MergedPreviewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MergedPreview build() => _build();

  _$MergedPreview _build() {
    _$MergedPreview _$result;
    try {
      _$result = _$v ??
          _$MergedPreview._(
            scenes: scenes.build(),
            unmatchedScheduleRows: unmatchedScheduleRows.build(),
            unmatchedScriptScenes: unmatchedScriptScenes.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'scenes';
        scenes.build();
        _$failedField = 'unmatchedScheduleRows';
        unmatchedScheduleRows.build();
        _$failedField = 'unmatchedScriptScenes';
        unmatchedScriptScenes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MergedPreview', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
