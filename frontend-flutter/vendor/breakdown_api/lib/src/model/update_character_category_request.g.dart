// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_character_category_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateCharacterCategoryRequest extends UpdateCharacterCategoryRequest {
  @override
  final CharacterCategory category;
  @override
  final int version;

  factory _$UpdateCharacterCategoryRequest(
          [void Function(UpdateCharacterCategoryRequestBuilder)? updates]) =>
      (UpdateCharacterCategoryRequestBuilder()..update(updates))._build();

  _$UpdateCharacterCategoryRequest._(
      {required this.category, required this.version})
      : super._();
  @override
  UpdateCharacterCategoryRequest rebuild(
          void Function(UpdateCharacterCategoryRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateCharacterCategoryRequestBuilder toBuilder() =>
      UpdateCharacterCategoryRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateCharacterCategoryRequest &&
        category == other.category &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateCharacterCategoryRequest')
          ..add('category', category)
          ..add('version', version))
        .toString();
  }
}

class UpdateCharacterCategoryRequestBuilder
    implements
        Builder<UpdateCharacterCategoryRequest,
            UpdateCharacterCategoryRequestBuilder> {
  _$UpdateCharacterCategoryRequest? _$v;

  CharacterCategory? _category;
  CharacterCategory? get category => _$this._category;
  set category(CharacterCategory? category) => _$this._category = category;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateCharacterCategoryRequestBuilder() {
    UpdateCharacterCategoryRequest._defaults(this);
  }

  UpdateCharacterCategoryRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _category = $v.category;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateCharacterCategoryRequest other) {
    _$v = other as _$UpdateCharacterCategoryRequest;
  }

  @override
  void update(void Function(UpdateCharacterCategoryRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateCharacterCategoryRequest build() => _build();

  _$UpdateCharacterCategoryRequest _build() {
    final _$result = _$v ??
        _$UpdateCharacterCategoryRequest._(
          category: BuiltValueNullFieldError.checkNotNull(
              category, r'UpdateCharacterCategoryRequest', 'category'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateCharacterCategoryRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
