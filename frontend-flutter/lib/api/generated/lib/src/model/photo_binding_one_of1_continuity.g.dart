// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_binding_one_of1_continuity.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoBindingOneOf1Continuity extends PhotoBindingOneOf1Continuity {
  @override
  final String? costumeId;
  @override
  final String sceneShootId;

  factory _$PhotoBindingOneOf1Continuity(
          [void Function(PhotoBindingOneOf1ContinuityBuilder)? updates]) =>
      (PhotoBindingOneOf1ContinuityBuilder()..update(updates))._build();

  _$PhotoBindingOneOf1Continuity._({this.costumeId, required this.sceneShootId})
      : super._();
  @override
  PhotoBindingOneOf1Continuity rebuild(
          void Function(PhotoBindingOneOf1ContinuityBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoBindingOneOf1ContinuityBuilder toBuilder() =>
      PhotoBindingOneOf1ContinuityBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoBindingOneOf1Continuity &&
        costumeId == other.costumeId &&
        sceneShootId == other.sceneShootId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, costumeId.hashCode);
    _$hash = $jc(_$hash, sceneShootId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoBindingOneOf1Continuity')
          ..add('costumeId', costumeId)
          ..add('sceneShootId', sceneShootId))
        .toString();
  }
}

class PhotoBindingOneOf1ContinuityBuilder
    implements
        Builder<PhotoBindingOneOf1Continuity,
            PhotoBindingOneOf1ContinuityBuilder> {
  _$PhotoBindingOneOf1Continuity? _$v;

  String? _costumeId;
  String? get costumeId => _$this._costumeId;
  set costumeId(String? costumeId) => _$this._costumeId = costumeId;

  String? _sceneShootId;
  String? get sceneShootId => _$this._sceneShootId;
  set sceneShootId(String? sceneShootId) => _$this._sceneShootId = sceneShootId;

  PhotoBindingOneOf1ContinuityBuilder() {
    PhotoBindingOneOf1Continuity._defaults(this);
  }

  PhotoBindingOneOf1ContinuityBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _costumeId = $v.costumeId;
      _sceneShootId = $v.sceneShootId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoBindingOneOf1Continuity other) {
    _$v = other as _$PhotoBindingOneOf1Continuity;
  }

  @override
  void update(void Function(PhotoBindingOneOf1ContinuityBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoBindingOneOf1Continuity build() => _build();

  _$PhotoBindingOneOf1Continuity _build() {
    final _$result = _$v ??
        _$PhotoBindingOneOf1Continuity._(
          costumeId: costumeId,
          sceneShootId: BuiltValueNullFieldError.checkNotNull(
              sceneShootId, r'PhotoBindingOneOf1Continuity', 'sceneShootId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
