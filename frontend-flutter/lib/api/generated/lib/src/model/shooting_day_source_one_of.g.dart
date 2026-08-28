// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_day_source_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootingDaySourceOneOf extends ShootingDaySourceOneOf {
  @override
  final ShootingDaySourceOneOfAiExtracted aiExtracted;

  factory _$ShootingDaySourceOneOf(
          [void Function(ShootingDaySourceOneOfBuilder)? updates]) =>
      (ShootingDaySourceOneOfBuilder()..update(updates))._build();

  _$ShootingDaySourceOneOf._({required this.aiExtracted}) : super._();
  @override
  ShootingDaySourceOneOf rebuild(
          void Function(ShootingDaySourceOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootingDaySourceOneOfBuilder toBuilder() =>
      ShootingDaySourceOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootingDaySourceOneOf && aiExtracted == other.aiExtracted;
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
    return (newBuiltValueToStringHelper(r'ShootingDaySourceOneOf')
          ..add('aiExtracted', aiExtracted))
        .toString();
  }
}

class ShootingDaySourceOneOfBuilder
    implements Builder<ShootingDaySourceOneOf, ShootingDaySourceOneOfBuilder> {
  _$ShootingDaySourceOneOf? _$v;

  ShootingDaySourceOneOfAiExtractedBuilder? _aiExtracted;
  ShootingDaySourceOneOfAiExtractedBuilder get aiExtracted =>
      _$this._aiExtracted ??= ShootingDaySourceOneOfAiExtractedBuilder();
  set aiExtracted(ShootingDaySourceOneOfAiExtractedBuilder? aiExtracted) =>
      _$this._aiExtracted = aiExtracted;

  ShootingDaySourceOneOfBuilder() {
    ShootingDaySourceOneOf._defaults(this);
  }

  ShootingDaySourceOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _aiExtracted = $v.aiExtracted.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShootingDaySourceOneOf other) {
    _$v = other as _$ShootingDaySourceOneOf;
  }

  @override
  void update(void Function(ShootingDaySourceOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootingDaySourceOneOf build() => _build();

  _$ShootingDaySourceOneOf _build() {
    _$ShootingDaySourceOneOf _$result;
    try {
      _$result = _$v ??
          _$ShootingDaySourceOneOf._(
            aiExtracted: aiExtracted.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'aiExtracted';
        aiExtracted.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ShootingDaySourceOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
