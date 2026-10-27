// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfit_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OutfitView extends OutfitView {
  @override
  final String characterId;
  @override
  final String? characterName;
  @override
  final String id;
  @override
  final String name;
  @override
  final String notes;
  @override
  final BuiltList<OutfitPhotoView> photos;
  @override
  final BuiltList<String> pieceIds;
  @override
  final BuiltList<OutfitPieceView> pieces;
  @override
  final String? seasonId;
  @override
  final DateTime updatedAt;
  @override
  final String? variantOf;
  @override
  final int version;

  factory _$OutfitView([void Function(OutfitViewBuilder)? updates]) =>
      (OutfitViewBuilder()..update(updates))._build();

  _$OutfitView._(
      {required this.characterId,
      this.characterName,
      required this.id,
      required this.name,
      required this.notes,
      required this.photos,
      required this.pieceIds,
      required this.pieces,
      this.seasonId,
      required this.updatedAt,
      this.variantOf,
      required this.version})
      : super._();
  @override
  OutfitView rebuild(void Function(OutfitViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OutfitViewBuilder toBuilder() => OutfitViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OutfitView &&
        characterId == other.characterId &&
        characterName == other.characterName &&
        id == other.id &&
        name == other.name &&
        notes == other.notes &&
        photos == other.photos &&
        pieceIds == other.pieceIds &&
        pieces == other.pieces &&
        seasonId == other.seasonId &&
        updatedAt == other.updatedAt &&
        variantOf == other.variantOf &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, photos.hashCode);
    _$hash = $jc(_$hash, pieceIds.hashCode);
    _$hash = $jc(_$hash, pieces.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, variantOf.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OutfitView')
          ..add('characterId', characterId)
          ..add('characterName', characterName)
          ..add('id', id)
          ..add('name', name)
          ..add('notes', notes)
          ..add('photos', photos)
          ..add('pieceIds', pieceIds)
          ..add('pieces', pieces)
          ..add('seasonId', seasonId)
          ..add('updatedAt', updatedAt)
          ..add('variantOf', variantOf)
          ..add('version', version))
        .toString();
  }
}

class OutfitViewBuilder implements Builder<OutfitView, OutfitViewBuilder> {
  _$OutfitView? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  ListBuilder<OutfitPhotoView>? _photos;
  ListBuilder<OutfitPhotoView> get photos =>
      _$this._photos ??= ListBuilder<OutfitPhotoView>();
  set photos(ListBuilder<OutfitPhotoView>? photos) => _$this._photos = photos;

  ListBuilder<String>? _pieceIds;
  ListBuilder<String> get pieceIds =>
      _$this._pieceIds ??= ListBuilder<String>();
  set pieceIds(ListBuilder<String>? pieceIds) => _$this._pieceIds = pieceIds;

  ListBuilder<OutfitPieceView>? _pieces;
  ListBuilder<OutfitPieceView> get pieces =>
      _$this._pieces ??= ListBuilder<OutfitPieceView>();
  set pieces(ListBuilder<OutfitPieceView>? pieces) => _$this._pieces = pieces;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  String? _variantOf;
  String? get variantOf => _$this._variantOf;
  set variantOf(String? variantOf) => _$this._variantOf = variantOf;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  OutfitViewBuilder() {
    OutfitView._defaults(this);
  }

  OutfitViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _characterName = $v.characterName;
      _id = $v.id;
      _name = $v.name;
      _notes = $v.notes;
      _photos = $v.photos.toBuilder();
      _pieceIds = $v.pieceIds.toBuilder();
      _pieces = $v.pieces.toBuilder();
      _seasonId = $v.seasonId;
      _updatedAt = $v.updatedAt;
      _variantOf = $v.variantOf;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OutfitView other) {
    _$v = other as _$OutfitView;
  }

  @override
  void update(void Function(OutfitViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OutfitView build() => _build();

  _$OutfitView _build() {
    _$OutfitView _$result;
    try {
      _$result = _$v ??
          _$OutfitView._(
            characterId: BuiltValueNullFieldError.checkNotNull(
                characterId, r'OutfitView', 'characterId'),
            characterName: characterName,
            id: BuiltValueNullFieldError.checkNotNull(id, r'OutfitView', 'id'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'OutfitView', 'name'),
            notes: BuiltValueNullFieldError.checkNotNull(
                notes, r'OutfitView', 'notes'),
            photos: photos.build(),
            pieceIds: pieceIds.build(),
            pieces: pieces.build(),
            seasonId: seasonId,
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'OutfitView', 'updatedAt'),
            variantOf: variantOf,
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'OutfitView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'photos';
        photos.build();
        _$failedField = 'pieceIds';
        pieceIds.build();
        _$failedField = 'pieces';
        pieces.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'OutfitView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
