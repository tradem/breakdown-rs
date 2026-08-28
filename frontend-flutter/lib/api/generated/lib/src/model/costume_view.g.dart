// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumeView extends CostumeView {
  @override
  final String? characterId;
  @override
  final BuiltList<CostumeDetailView> details;
  @override
  final String id;
  @override
  final String notes;
  @override
  final BuiltList<CostumePhotoView> photos;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$CostumeView([void Function(CostumeViewBuilder)? updates]) =>
      (CostumeViewBuilder()..update(updates))._build();

  _$CostumeView._(
      {this.characterId,
      required this.details,
      required this.id,
      required this.notes,
      required this.photos,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  CostumeView rebuild(void Function(CostumeViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumeViewBuilder toBuilder() => CostumeViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumeView &&
        characterId == other.characterId &&
        details == other.details &&
        id == other.id &&
        notes == other.notes &&
        photos == other.photos &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, details.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, photos.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumeView')
          ..add('characterId', characterId)
          ..add('details', details)
          ..add('id', id)
          ..add('notes', notes)
          ..add('photos', photos)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class CostumeViewBuilder implements Builder<CostumeView, CostumeViewBuilder> {
  _$CostumeView? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  ListBuilder<CostumeDetailView>? _details;
  ListBuilder<CostumeDetailView> get details =>
      _$this._details ??= ListBuilder<CostumeDetailView>();
  set details(ListBuilder<CostumeDetailView>? details) =>
      _$this._details = details;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  ListBuilder<CostumePhotoView>? _photos;
  ListBuilder<CostumePhotoView> get photos =>
      _$this._photos ??= ListBuilder<CostumePhotoView>();
  set photos(ListBuilder<CostumePhotoView>? photos) => _$this._photos = photos;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  CostumeViewBuilder() {
    CostumeView._defaults(this);
  }

  CostumeViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _details = $v.details.toBuilder();
      _id = $v.id;
      _notes = $v.notes;
      _photos = $v.photos.toBuilder();
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumeView other) {
    _$v = other as _$CostumeView;
  }

  @override
  void update(void Function(CostumeViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumeView build() => _build();

  _$CostumeView _build() {
    _$CostumeView _$result;
    try {
      _$result = _$v ??
          _$CostumeView._(
            characterId: characterId,
            details: details.build(),
            id: BuiltValueNullFieldError.checkNotNull(id, r'CostumeView', 'id'),
            notes: BuiltValueNullFieldError.checkNotNull(
                notes, r'CostumeView', 'notes'),
            photos: photos.build(),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'CostumeView', 'updatedAt'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'CostumeView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'details';
        details.build();

        _$failedField = 'photos';
        photos.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CostumeView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
