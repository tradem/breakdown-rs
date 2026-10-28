// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unapplied_outfit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UnappliedOutfit extends UnappliedOutfit {
  @override
  final String characterName;
  @override
  final String? detail;
  @override
  final String draftRef;
  @override
  final String name;
  @override
  final int ordinal;
  @override
  final UnappliedOutfitReason reason;

  factory _$UnappliedOutfit([void Function(UnappliedOutfitBuilder)? updates]) =>
      (UnappliedOutfitBuilder()..update(updates))._build();

  _$UnappliedOutfit._(
      {required this.characterName,
      this.detail,
      required this.draftRef,
      required this.name,
      required this.ordinal,
      required this.reason})
      : super._();
  @override
  UnappliedOutfit rebuild(void Function(UnappliedOutfitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UnappliedOutfitBuilder toBuilder() => UnappliedOutfitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UnappliedOutfit &&
        characterName == other.characterName &&
        detail == other.detail &&
        draftRef == other.draftRef &&
        name == other.name &&
        ordinal == other.ordinal &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, draftRef.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, ordinal.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UnappliedOutfit')
          ..add('characterName', characterName)
          ..add('detail', detail)
          ..add('draftRef', draftRef)
          ..add('name', name)
          ..add('ordinal', ordinal)
          ..add('reason', reason))
        .toString();
  }
}

class UnappliedOutfitBuilder
    implements Builder<UnappliedOutfit, UnappliedOutfitBuilder> {
  _$UnappliedOutfit? _$v;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  String? _draftRef;
  String? get draftRef => _$this._draftRef;
  set draftRef(String? draftRef) => _$this._draftRef = draftRef;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _ordinal;
  int? get ordinal => _$this._ordinal;
  set ordinal(int? ordinal) => _$this._ordinal = ordinal;

  UnappliedOutfitReason? _reason;
  UnappliedOutfitReason? get reason => _$this._reason;
  set reason(UnappliedOutfitReason? reason) => _$this._reason = reason;

  UnappliedOutfitBuilder() {
    UnappliedOutfit._defaults(this);
  }

  UnappliedOutfitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterName = $v.characterName;
      _detail = $v.detail;
      _draftRef = $v.draftRef;
      _name = $v.name;
      _ordinal = $v.ordinal;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UnappliedOutfit other) {
    _$v = other as _$UnappliedOutfit;
  }

  @override
  void update(void Function(UnappliedOutfitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UnappliedOutfit build() => _build();

  _$UnappliedOutfit _build() {
    final _$result = _$v ??
        _$UnappliedOutfit._(
          characterName: BuiltValueNullFieldError.checkNotNull(
              characterName, r'UnappliedOutfit', 'characterName'),
          detail: detail,
          draftRef: BuiltValueNullFieldError.checkNotNull(
              draftRef, r'UnappliedOutfit', 'draftRef'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'UnappliedOutfit', 'name'),
          ordinal: BuiltValueNullFieldError.checkNotNull(
              ordinal, r'UnappliedOutfit', 'ordinal'),
          reason: BuiltValueNullFieldError.checkNotNull(
              reason, r'UnappliedOutfit', 'reason'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
