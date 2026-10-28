// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfit extends DraftOutfit {
  @override
  final String characterName;
  @override
  final String name;
  @override
  final String? notes;
  @override
  final DraftOutfitOrigin? origin;
  @override
  final BuiltList<DraftPiece>? pieces;
  @override
  final DraftOutfitProvenance? provenance;
  @override
  final String sourceQuote;

  factory _$DraftOutfit([void Function(DraftOutfitBuilder)? updates]) =>
      (DraftOutfitBuilder()..update(updates))._build();

  _$DraftOutfit._(
      {required this.characterName,
      required this.name,
      this.notes,
      this.origin,
      this.pieces,
      this.provenance,
      required this.sourceQuote})
      : super._();
  @override
  DraftOutfit rebuild(void Function(DraftOutfitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitBuilder toBuilder() => DraftOutfitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfit &&
        characterName == other.characterName &&
        name == other.name &&
        notes == other.notes &&
        origin == other.origin &&
        pieces == other.pieces &&
        provenance == other.provenance &&
        sourceQuote == other.sourceQuote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, origin.hashCode);
    _$hash = $jc(_$hash, pieces.hashCode);
    _$hash = $jc(_$hash, provenance.hashCode);
    _$hash = $jc(_$hash, sourceQuote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftOutfit')
          ..add('characterName', characterName)
          ..add('name', name)
          ..add('notes', notes)
          ..add('origin', origin)
          ..add('pieces', pieces)
          ..add('provenance', provenance)
          ..add('sourceQuote', sourceQuote))
        .toString();
  }
}

class DraftOutfitBuilder implements Builder<DraftOutfit, DraftOutfitBuilder> {
  _$DraftOutfit? _$v;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _notes;
  String? get notes => _$this._notes;
  set notes(String? notes) => _$this._notes = notes;

  DraftOutfitOrigin? _origin;
  DraftOutfitOrigin? get origin => _$this._origin;
  set origin(DraftOutfitOrigin? origin) => _$this._origin = origin;

  ListBuilder<DraftPiece>? _pieces;
  ListBuilder<DraftPiece> get pieces =>
      _$this._pieces ??= ListBuilder<DraftPiece>();
  set pieces(ListBuilder<DraftPiece>? pieces) => _$this._pieces = pieces;

  DraftOutfitProvenanceBuilder? _provenance;
  DraftOutfitProvenanceBuilder get provenance =>
      _$this._provenance ??= DraftOutfitProvenanceBuilder();
  set provenance(DraftOutfitProvenanceBuilder? provenance) =>
      _$this._provenance = provenance;

  String? _sourceQuote;
  String? get sourceQuote => _$this._sourceQuote;
  set sourceQuote(String? sourceQuote) => _$this._sourceQuote = sourceQuote;

  DraftOutfitBuilder() {
    DraftOutfit._defaults(this);
  }

  DraftOutfitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterName = $v.characterName;
      _name = $v.name;
      _notes = $v.notes;
      _origin = $v.origin;
      _pieces = $v.pieces?.toBuilder();
      _provenance = $v.provenance?.toBuilder();
      _sourceQuote = $v.sourceQuote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftOutfit other) {
    _$v = other as _$DraftOutfit;
  }

  @override
  void update(void Function(DraftOutfitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfit build() => _build();

  _$DraftOutfit _build() {
    _$DraftOutfit _$result;
    try {
      _$result = _$v ??
          _$DraftOutfit._(
            characterName: BuiltValueNullFieldError.checkNotNull(
                characterName, r'DraftOutfit', 'characterName'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'DraftOutfit', 'name'),
            notes: notes,
            origin: origin,
            pieces: _pieces?.build(),
            provenance: _provenance?.build(),
            sourceQuote: BuiltValueNullFieldError.checkNotNull(
                sourceQuote, r'DraftOutfit', 'sourceQuote'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pieces';
        _pieces?.build();
        _$failedField = 'provenance';
        _provenance?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'DraftOutfit', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
