// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'script_context.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ScriptContext extends ScriptContext {
  @override
  final BuiltList<DraftScene> scenes;
  @override
  final int? scenesDetected;
  @override
  final int? scenesExtracted;
  @override
  final int? scenesSynthesized;
  @override
  final String? title;
  @override
  final BuiltList<Uncertainty> uncertainties;

  factory _$ScriptContext([void Function(ScriptContextBuilder)? updates]) =>
      (ScriptContextBuilder()..update(updates))._build();

  _$ScriptContext._(
      {required this.scenes,
      this.scenesDetected,
      this.scenesExtracted,
      this.scenesSynthesized,
      this.title,
      required this.uncertainties})
      : super._();
  @override
  ScriptContext rebuild(void Function(ScriptContextBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ScriptContextBuilder toBuilder() => ScriptContextBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ScriptContext &&
        scenes == other.scenes &&
        scenesDetected == other.scenesDetected &&
        scenesExtracted == other.scenesExtracted &&
        scenesSynthesized == other.scenesSynthesized &&
        title == other.title &&
        uncertainties == other.uncertainties;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scenes.hashCode);
    _$hash = $jc(_$hash, scenesDetected.hashCode);
    _$hash = $jc(_$hash, scenesExtracted.hashCode);
    _$hash = $jc(_$hash, scenesSynthesized.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, uncertainties.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ScriptContext')
          ..add('scenes', scenes)
          ..add('scenesDetected', scenesDetected)
          ..add('scenesExtracted', scenesExtracted)
          ..add('scenesSynthesized', scenesSynthesized)
          ..add('title', title)
          ..add('uncertainties', uncertainties))
        .toString();
  }
}

class ScriptContextBuilder
    implements Builder<ScriptContext, ScriptContextBuilder> {
  _$ScriptContext? _$v;

  ListBuilder<DraftScene>? _scenes;
  ListBuilder<DraftScene> get scenes =>
      _$this._scenes ??= ListBuilder<DraftScene>();
  set scenes(ListBuilder<DraftScene>? scenes) => _$this._scenes = scenes;

  int? _scenesDetected;
  int? get scenesDetected => _$this._scenesDetected;
  set scenesDetected(int? scenesDetected) =>
      _$this._scenesDetected = scenesDetected;

  int? _scenesExtracted;
  int? get scenesExtracted => _$this._scenesExtracted;
  set scenesExtracted(int? scenesExtracted) =>
      _$this._scenesExtracted = scenesExtracted;

  int? _scenesSynthesized;
  int? get scenesSynthesized => _$this._scenesSynthesized;
  set scenesSynthesized(int? scenesSynthesized) =>
      _$this._scenesSynthesized = scenesSynthesized;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  ListBuilder<Uncertainty>? _uncertainties;
  ListBuilder<Uncertainty> get uncertainties =>
      _$this._uncertainties ??= ListBuilder<Uncertainty>();
  set uncertainties(ListBuilder<Uncertainty>? uncertainties) =>
      _$this._uncertainties = uncertainties;

  ScriptContextBuilder() {
    ScriptContext._defaults(this);
  }

  ScriptContextBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scenes = $v.scenes.toBuilder();
      _scenesDetected = $v.scenesDetected;
      _scenesExtracted = $v.scenesExtracted;
      _scenesSynthesized = $v.scenesSynthesized;
      _title = $v.title;
      _uncertainties = $v.uncertainties.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ScriptContext other) {
    _$v = other as _$ScriptContext;
  }

  @override
  void update(void Function(ScriptContextBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ScriptContext build() => _build();

  _$ScriptContext _build() {
    _$ScriptContext _$result;
    try {
      _$result = _$v ??
          _$ScriptContext._(
            scenes: scenes.build(),
            scenesDetected: scenesDetected,
            scenesExtracted: scenesExtracted,
            scenesSynthesized: scenesSynthesized,
            title: title,
            uncertainties: uncertainties.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'scenes';
        scenes.build();

        _$failedField = 'uncertainties';
        uncertainties.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ScriptContext', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
