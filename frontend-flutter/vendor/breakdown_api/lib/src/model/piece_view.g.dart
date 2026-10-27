// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'piece_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PieceView extends PieceView {
  @override
  final String? categoryId;
  @override
  final String? categoryName;
  @override
  final BuiltList<PieceDetailView> details;
  @override
  final String id;
  @override
  final String name;
  @override
  final String notes;
  @override
  final BuiltList<PiecePhotoView> photos;
  @override
  final BuiltList<String> seasonIds;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$PieceView([void Function(PieceViewBuilder)? updates]) =>
      (PieceViewBuilder()..update(updates))._build();

  _$PieceView._(
      {this.categoryId,
      this.categoryName,
      required this.details,
      required this.id,
      required this.name,
      required this.notes,
      required this.photos,
      required this.seasonIds,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  PieceView rebuild(void Function(PieceViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PieceViewBuilder toBuilder() => PieceViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PieceView &&
        categoryId == other.categoryId &&
        categoryName == other.categoryName &&
        details == other.details &&
        id == other.id &&
        name == other.name &&
        notes == other.notes &&
        photos == other.photos &&
        seasonIds == other.seasonIds &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, categoryName.hashCode);
    _$hash = $jc(_$hash, details.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, photos.hashCode);
    _$hash = $jc(_$hash, seasonIds.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PieceView')
          ..add('categoryId', categoryId)
          ..add('categoryName', categoryName)
          ..add('details', details)
          ..add('id', id)
          ..add('name', name)
          ..add('notes', notes)
          ..add('photos', photos)
          ..add('seasonIds', seasonIds)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class PieceViewBuilder implements Builder<PieceView, PieceViewBuilder> {
  _$PieceView? _$v;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _categoryName;
  String? get categoryName => _$this._categoryName;
  set categoryName(String? categoryName) => _$this._categoryName = categoryName;

  ListBuilder<PieceDetailView>? _details;
  ListBuilder<PieceDetailView> get details =>
      _$this._details ??= ListBuilder<PieceDetailView>();
  set details(ListBuilder<PieceDetailView>? details) =>
      _$this._details = details;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  ListBuilder<PiecePhotoView>? _photos;
  ListBuilder<PiecePhotoView> get photos =>
      _$this._photos ??= ListBuilder<PiecePhotoView>();
  set photos(ListBuilder<PiecePhotoView>? photos) => _$this._photos = photos;

  ListBuilder<String>? _seasonIds;
  ListBuilder<String> get seasonIds =>
      _$this._seasonIds ??= ListBuilder<String>();
  set seasonIds(ListBuilder<String>? seasonIds) =>
      _$this._seasonIds = seasonIds;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  PieceViewBuilder() {
    PieceView._defaults(this);
  }

  PieceViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _categoryId = $v.categoryId;
      _categoryName = $v.categoryName;
      _details = $v.details.toBuilder();
      _id = $v.id;
      _name = $v.name;
      _notes = $v.notes;
      _photos = $v.photos.toBuilder();
      _seasonIds = $v.seasonIds.toBuilder();
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PieceView other) {
    _$v = other as _$PieceView;
  }

  @override
  void update(void Function(PieceViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PieceView build() => _build();

  _$PieceView _build() {
    _$PieceView _$result;
    try {
      _$result = _$v ??
          _$PieceView._(
            categoryId: categoryId,
            categoryName: categoryName,
            details: details.build(),
            id: BuiltValueNullFieldError.checkNotNull(id, r'PieceView', 'id'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'PieceView', 'name'),
            notes: BuiltValueNullFieldError.checkNotNull(
                notes, r'PieceView', 'notes'),
            photos: photos.build(),
            seasonIds: seasonIds.build(),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'PieceView', 'updatedAt'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'PieceView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'details';
        details.build();

        _$failedField = 'photos';
        photos.build();
        _$failedField = 'seasonIds';
        seasonIds.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PieceView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
