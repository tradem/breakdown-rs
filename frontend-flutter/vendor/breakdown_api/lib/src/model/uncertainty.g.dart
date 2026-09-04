// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'uncertainty.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Uncertainty extends Uncertainty {
  @override
  final String field;
  @override
  final String note;
  @override
  final int sceneIndex;
  @override
  final String? suggestedValue;

  factory _$Uncertainty([void Function(UncertaintyBuilder)? updates]) =>
      (UncertaintyBuilder()..update(updates))._build();

  _$Uncertainty._(
      {required this.field,
      required this.note,
      required this.sceneIndex,
      this.suggestedValue})
      : super._();
  @override
  Uncertainty rebuild(void Function(UncertaintyBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UncertaintyBuilder toBuilder() => UncertaintyBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Uncertainty &&
        field == other.field &&
        note == other.note &&
        sceneIndex == other.sceneIndex &&
        suggestedValue == other.suggestedValue;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, sceneIndex.hashCode);
    _$hash = $jc(_$hash, suggestedValue.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Uncertainty')
          ..add('field', field)
          ..add('note', note)
          ..add('sceneIndex', sceneIndex)
          ..add('suggestedValue', suggestedValue))
        .toString();
  }
}

class UncertaintyBuilder implements Builder<Uncertainty, UncertaintyBuilder> {
  _$Uncertainty? _$v;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  int? _sceneIndex;
  int? get sceneIndex => _$this._sceneIndex;
  set sceneIndex(int? sceneIndex) => _$this._sceneIndex = sceneIndex;

  String? _suggestedValue;
  String? get suggestedValue => _$this._suggestedValue;
  set suggestedValue(String? suggestedValue) =>
      _$this._suggestedValue = suggestedValue;

  UncertaintyBuilder() {
    Uncertainty._defaults(this);
  }

  UncertaintyBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _field = $v.field;
      _note = $v.note;
      _sceneIndex = $v.sceneIndex;
      _suggestedValue = $v.suggestedValue;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Uncertainty other) {
    _$v = other as _$Uncertainty;
  }

  @override
  void update(void Function(UncertaintyBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Uncertainty build() => _build();

  _$Uncertainty _build() {
    final _$result = _$v ??
        _$Uncertainty._(
          field: BuiltValueNullFieldError.checkNotNull(
              field, r'Uncertainty', 'field'),
          note: BuiltValueNullFieldError.checkNotNull(
              note, r'Uncertainty', 'note'),
          sceneIndex: BuiltValueNullFieldError.checkNotNull(
              sceneIndex, r'Uncertainty', 'sceneIndex'),
          suggestedValue: suggestedValue,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
