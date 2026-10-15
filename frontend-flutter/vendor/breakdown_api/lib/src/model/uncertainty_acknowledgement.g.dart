// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'uncertainty_acknowledgement.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UncertaintyAcknowledgement extends UncertaintyAcknowledgement {
  @override
  final String field;
  @override
  final int sceneIndex;

  factory _$UncertaintyAcknowledgement(
          [void Function(UncertaintyAcknowledgementBuilder)? updates]) =>
      (UncertaintyAcknowledgementBuilder()..update(updates))._build();

  _$UncertaintyAcknowledgement._(
      {required this.field, required this.sceneIndex})
      : super._();
  @override
  UncertaintyAcknowledgement rebuild(
          void Function(UncertaintyAcknowledgementBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UncertaintyAcknowledgementBuilder toBuilder() =>
      UncertaintyAcknowledgementBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UncertaintyAcknowledgement &&
        field == other.field &&
        sceneIndex == other.sceneIndex;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, sceneIndex.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UncertaintyAcknowledgement')
          ..add('field', field)
          ..add('sceneIndex', sceneIndex))
        .toString();
  }
}

class UncertaintyAcknowledgementBuilder
    implements
        Builder<UncertaintyAcknowledgement, UncertaintyAcknowledgementBuilder> {
  _$UncertaintyAcknowledgement? _$v;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  int? _sceneIndex;
  int? get sceneIndex => _$this._sceneIndex;
  set sceneIndex(int? sceneIndex) => _$this._sceneIndex = sceneIndex;

  UncertaintyAcknowledgementBuilder() {
    UncertaintyAcknowledgement._defaults(this);
  }

  UncertaintyAcknowledgementBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _field = $v.field;
      _sceneIndex = $v.sceneIndex;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UncertaintyAcknowledgement other) {
    _$v = other as _$UncertaintyAcknowledgement;
  }

  @override
  void update(void Function(UncertaintyAcknowledgementBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UncertaintyAcknowledgement build() => _build();

  _$UncertaintyAcknowledgement _build() {
    final _$result = _$v ??
        _$UncertaintyAcknowledgement._(
          field: BuiltValueNullFieldError.checkNotNull(
              field, r'UncertaintyAcknowledgement', 'field'),
          sceneIndex: BuiltValueNullFieldError.checkNotNull(
              sceneIndex, r'UncertaintyAcknowledgement', 'sceneIndex'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
