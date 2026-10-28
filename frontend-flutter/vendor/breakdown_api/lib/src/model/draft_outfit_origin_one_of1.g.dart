// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_origin_one_of1.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfitOriginOneOf1 extends DraftOutfitOriginOneOf1 {
  @override
  final DraftOutfitOriginOneOf1InferredFromContext inferredFromContext;

  factory _$DraftOutfitOriginOneOf1(
          [void Function(DraftOutfitOriginOneOf1Builder)? updates]) =>
      (DraftOutfitOriginOneOf1Builder()..update(updates))._build();

  _$DraftOutfitOriginOneOf1._({required this.inferredFromContext}) : super._();
  @override
  DraftOutfitOriginOneOf1 rebuild(
          void Function(DraftOutfitOriginOneOf1Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitOriginOneOf1Builder toBuilder() =>
      DraftOutfitOriginOneOf1Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfitOriginOneOf1 &&
        inferredFromContext == other.inferredFromContext;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, inferredFromContext.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftOutfitOriginOneOf1')
          ..add('inferredFromContext', inferredFromContext))
        .toString();
  }
}

class DraftOutfitOriginOneOf1Builder
    implements
        Builder<DraftOutfitOriginOneOf1, DraftOutfitOriginOneOf1Builder> {
  _$DraftOutfitOriginOneOf1? _$v;

  DraftOutfitOriginOneOf1InferredFromContextBuilder? _inferredFromContext;
  DraftOutfitOriginOneOf1InferredFromContextBuilder get inferredFromContext =>
      _$this._inferredFromContext ??=
          DraftOutfitOriginOneOf1InferredFromContextBuilder();
  set inferredFromContext(
          DraftOutfitOriginOneOf1InferredFromContextBuilder?
              inferredFromContext) =>
      _$this._inferredFromContext = inferredFromContext;

  DraftOutfitOriginOneOf1Builder() {
    DraftOutfitOriginOneOf1._defaults(this);
  }

  DraftOutfitOriginOneOf1Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _inferredFromContext = $v.inferredFromContext.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftOutfitOriginOneOf1 other) {
    _$v = other as _$DraftOutfitOriginOneOf1;
  }

  @override
  void update(void Function(DraftOutfitOriginOneOf1Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfitOriginOneOf1 build() => _build();

  _$DraftOutfitOriginOneOf1 _build() {
    _$DraftOutfitOriginOneOf1 _$result;
    try {
      _$result = _$v ??
          _$DraftOutfitOriginOneOf1._(
            inferredFromContext: inferredFromContext.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'inferredFromContext';
        inferredFromContext.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DraftOutfitOriginOneOf1', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
