// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unapplied_costume.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UnappliedCostume extends UnappliedCostume {
  @override
  final String characterName;
  @override
  final String description;
  @override
  final String? detail;
  @override
  final String draftRef;
  @override
  final int ordinal;
  @override
  final UnappliedCostumeReason reason;

  factory _$UnappliedCostume(
          [void Function(UnappliedCostumeBuilder)? updates]) =>
      (UnappliedCostumeBuilder()..update(updates))._build();

  _$UnappliedCostume._(
      {required this.characterName,
      required this.description,
      this.detail,
      required this.draftRef,
      required this.ordinal,
      required this.reason})
      : super._();
  @override
  UnappliedCostume rebuild(void Function(UnappliedCostumeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UnappliedCostumeBuilder toBuilder() =>
      UnappliedCostumeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UnappliedCostume &&
        characterName == other.characterName &&
        description == other.description &&
        detail == other.detail &&
        draftRef == other.draftRef &&
        ordinal == other.ordinal &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, draftRef.hashCode);
    _$hash = $jc(_$hash, ordinal.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UnappliedCostume')
          ..add('characterName', characterName)
          ..add('description', description)
          ..add('detail', detail)
          ..add('draftRef', draftRef)
          ..add('ordinal', ordinal)
          ..add('reason', reason))
        .toString();
  }
}

class UnappliedCostumeBuilder
    implements Builder<UnappliedCostume, UnappliedCostumeBuilder> {
  _$UnappliedCostume? _$v;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  String? _draftRef;
  String? get draftRef => _$this._draftRef;
  set draftRef(String? draftRef) => _$this._draftRef = draftRef;

  int? _ordinal;
  int? get ordinal => _$this._ordinal;
  set ordinal(int? ordinal) => _$this._ordinal = ordinal;

  UnappliedCostumeReason? _reason;
  UnappliedCostumeReason? get reason => _$this._reason;
  set reason(UnappliedCostumeReason? reason) => _$this._reason = reason;

  UnappliedCostumeBuilder() {
    UnappliedCostume._defaults(this);
  }

  UnappliedCostumeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterName = $v.characterName;
      _description = $v.description;
      _detail = $v.detail;
      _draftRef = $v.draftRef;
      _ordinal = $v.ordinal;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UnappliedCostume other) {
    _$v = other as _$UnappliedCostume;
  }

  @override
  void update(void Function(UnappliedCostumeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UnappliedCostume build() => _build();

  _$UnappliedCostume _build() {
    final _$result = _$v ??
        _$UnappliedCostume._(
          characterName: BuiltValueNullFieldError.checkNotNull(
              characterName, r'UnappliedCostume', 'characterName'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'UnappliedCostume', 'description'),
          detail: detail,
          draftRef: BuiltValueNullFieldError.checkNotNull(
              draftRef, r'UnappliedCostume', 'draftRef'),
          ordinal: BuiltValueNullFieldError.checkNotNull(
              ordinal, r'UnappliedCostume', 'ordinal'),
          reason: BuiltValueNullFieldError.checkNotNull(
              reason, r'UnappliedCostume', 'reason'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
