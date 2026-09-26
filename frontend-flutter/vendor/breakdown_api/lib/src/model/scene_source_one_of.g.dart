// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_source_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneSourceOneOf extends SceneSourceOneOf {
  @override
  final SceneSourceOneOfAiExtracted aiExtracted;

  factory _$SceneSourceOneOf(
          [void Function(SceneSourceOneOfBuilder)? updates]) =>
      (SceneSourceOneOfBuilder()..update(updates))._build();

  _$SceneSourceOneOf._({required this.aiExtracted}) : super._();
  @override
  SceneSourceOneOf rebuild(void Function(SceneSourceOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneSourceOneOfBuilder toBuilder() =>
      SceneSourceOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneSourceOneOf && aiExtracted == other.aiExtracted;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, aiExtracted.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneSourceOneOf')
          ..add('aiExtracted', aiExtracted))
        .toString();
  }
}

class SceneSourceOneOfBuilder
    implements Builder<SceneSourceOneOf, SceneSourceOneOfBuilder> {
  _$SceneSourceOneOf? _$v;

  SceneSourceOneOfAiExtractedBuilder? _aiExtracted;
  SceneSourceOneOfAiExtractedBuilder get aiExtracted =>
      _$this._aiExtracted ??= SceneSourceOneOfAiExtractedBuilder();
  set aiExtracted(SceneSourceOneOfAiExtractedBuilder? aiExtracted) =>
      _$this._aiExtracted = aiExtracted;

  SceneSourceOneOfBuilder() {
    SceneSourceOneOf._defaults(this);
  }

  SceneSourceOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _aiExtracted = $v.aiExtracted.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneSourceOneOf other) {
    _$v = other as _$SceneSourceOneOf;
  }

  @override
  void update(void Function(SceneSourceOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneSourceOneOf build() => _build();

  _$SceneSourceOneOf _build() {
    _$SceneSourceOneOf _$result;
    try {
      _$result = _$v ??
          _$SceneSourceOneOf._(
            aiExtracted: aiExtracted.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'aiExtracted';
        aiExtracted.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SceneSourceOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
